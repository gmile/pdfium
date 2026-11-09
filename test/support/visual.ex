defmodule PDFium.Test.Visual do
  import ExUnit.Assertions

  alias PDFium.Test.PNG

  @references Path.expand("../fixtures/visual", __DIR__)
  @gap 4
  @grey <<128, 128, 128, 255>>

  def sheet(document) do
    {:ok, count} = PDFium.get_page_count(document)
    lay_out(Enum.map(0..(count - 1)//1, &page(document, &1)))
  end

  def page(document, index, dpi \\ 72) do
    {:ok, pixels, width, height} = PDFium.get_page_bitmap(document, index, dpi)
    {pixels, width, height}
  end

  def assert_looks_like({pixels, width, height} = image, name) do
    reference = Path.join(@references, name <> ".png")

    cond do
      System.get_env("UPDATE_VISUALS") ->
        File.mkdir_p!(@references)
        File.write!(reference, PNG.encode(pixels, width, height))

      not File.exists?(reference) ->
        flunk("""
        There is no reference image for #{name}. Rendered it to #{write_actual(image, name)}.
        Run with UPDATE_VISUALS=1 to accept it.
        """)

      true ->
        compare(image, PNG.decode(File.read!(reference)), name)
    end
  end

  defp compare({pixels, width, height}, {pixels, width, height}, _name), do: :ok

  defp compare({_, width, height} = image, {_, expected_width, expected_height}, name)
       when width != expected_width or height != expected_height do
    flunk("""
    #{name} is #{width}x#{height}, the reference #{expected_width}x#{expected_height}.
    Rendered it to #{write_actual(image, name)}. Run with UPDATE_VISUALS=1 to accept it.
    """)
  end

  defp compare(
         {pixels, width, _height} = image,
         {expected, _expected_width, _expected_height},
         name
       ) do
    [{x, y, wanted, got} | _] = differing = differing(pixels, expected, width)
    xs = Enum.map(differing, &elem(&1, 0))
    ys = Enum.map(differing, &elem(&1, 1))

    flunk("""
    #{name} differs from its reference in #{length(differing)} pixels, \
    within x #{Enum.min(xs)}..#{Enum.max(xs)} and y #{Enum.min(ys)}..#{Enum.max(ys)}.
    The first is at (#{x}, #{y}): expected #{inspect(wanted)}, got #{inspect(got)}.
    Rendered it to #{write_actual(image, name)}. Run with UPDATE_VISUALS=1 to accept it.
    """)
  end

  defp differing(pixels, expected, width) do
    pixels
    |> pixels_of()
    |> Enum.zip(pixels_of(expected))
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{same, same}, _index} -> []
      {{got, wanted}, index} -> [{rem(index, width), div(index, width), wanted, got}]
    end)
  end

  defp pixels_of(binary),
    do: for(<<red, green, blue, alpha <- binary>>, do: {red, green, blue, alpha})

  defp write_actual({pixels, width, height}, name) do
    directory = Path.join(System.tmp_dir!(), "pdfium-visual")
    File.mkdir_p!(directory)
    path = Path.join(directory, name <> ".png")
    File.write!(path, PNG.encode(pixels, width, height))
    path
  end

  defp lay_out(pages) do
    height = pages |> Enum.map(&elem(&1, 2)) |> Enum.max()
    width = (pages |> Enum.map(&elem(&1, 1)) |> Enum.sum()) + @gap * (length(pages) - 1)
    gap = :binary.copy(@grey, @gap)

    pixels =
      for y <- 0..(height - 1), into: <<>> do
        pages
        |> Enum.map(&row(&1, y))
        |> Enum.intersperse(gap)
        |> IO.iodata_to_binary()
      end

    {pixels, width, height}
  end

  defp row({_pixels, width, height}, y) when y >= height, do: :binary.copy(@grey, width)
  defp row({pixels, width, _height}, y), do: binary_part(pixels, y * width * 4, width * 4)
end
