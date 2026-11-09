defmodule PDFium.Test.PNG do
  @signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  def encode(pixels, width, height) do
    stride = width * 4
    rows = for <<row::binary-size(^stride) <- pixels>>, into: <<>>, do: <<0, row::binary>>

    @signature <>
      chunk("IHDR", <<width::32, height::32, 8, 6, 0, 0, 0>>) <>
      chunk("IDAT", :zlib.compress(rows)) <>
      chunk("IEND", <<>>)
  end

  def decode(<<@signature, chunks::binary>>) do
    {header, data} = read_chunks(chunks, nil, [])
    <<width::32, height::32, 8, 6, 0, 0, 0>> = header
    rows = :zlib.uncompress(IO.iodata_to_binary(data))
    {unfilter(rows, width * 4, <<0::size(width * 32)>>, []), width, height}
  end

  defp chunk(type, data),
    do: <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>

  defp read_chunks(
         <<length::32, type::binary-size(4), data::binary-size(length), _crc::32, rest::binary>>,
         header,
         idat
       ) do
    case type do
      "IHDR" -> read_chunks(rest, data, idat)
      "IDAT" -> read_chunks(rest, header, [idat, data])
      "IEND" -> {header, idat}
      _other -> read_chunks(rest, header, idat)
    end
  end

  defp unfilter(<<>>, _stride, _previous, rows),
    do: rows |> Enum.reverse() |> IO.iodata_to_binary()

  defp unfilter(rows, stride, previous, done) do
    <<filter, row::binary-size(^stride), rest::binary>> = rows
    row = unfilter_row(filter, row, previous)
    unfilter(rest, stride, row, [row | done])
  end

  defp unfilter_row(0, row, _previous), do: row
  defp unfilter_row(filter, row, previous), do: unfilter_bytes(filter, row, previous, <<>>)

  defp unfilter_bytes(_filter, <<>>, _previous, done), do: done

  defp unfilter_bytes(filter, <<byte, row::binary>>, previous, done) do
    index = byte_size(done)
    left = if index >= 4, do: :binary.at(done, index - 4), else: 0
    upper_left = if index >= 4, do: :binary.at(previous, index - 4), else: 0
    value = rem(byte + predict(filter, left, :binary.at(previous, index), upper_left), 256)
    unfilter_bytes(filter, row, previous, <<done::binary, value>>)
  end

  defp predict(1, left, _up, _upper_left), do: left
  defp predict(2, _left, up, _upper_left), do: up
  defp predict(3, left, up, _upper_left), do: div(left + up, 2)

  defp predict(4, left, up, upper_left) do
    estimate = left + up - upper_left

    cond do
      abs(estimate - left) <= abs(estimate - up) and
          abs(estimate - left) <= abs(estimate - upper_left) ->
        left

      abs(estimate - up) <= abs(estimate - upper_left) ->
        up

      true ->
        upper_left
    end
  end
end
