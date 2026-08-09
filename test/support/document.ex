defmodule PDFium.Test.Document do
  @moduledoc """
  Writes the smallest document that says what a test needs it to say.

  Geometry is the thing a reader is allowed to vary — where the box starts,
  which way up the page is, how large it is — and a checked in file per
  combination would be a directory of binaries nobody can read or adjust. These
  are written instead, from a description the test states in full.
  """

  @typedoc """
  A page: the box it occupies, how far it is turned, and what is drawn on it.

  `content` is a content stream, so `"1 0 0 rg 0 0 10 10 re f"` fills a red
  square at the origin.
  """
  @type page :: [
          box: {number(), number(), number(), number()},
          rotation: 0 | 90 | 180 | 270,
          content: binary()
        ]

  @doc """
  Writes a document with the given pages and answers with where it was written.
  """
  @spec write!(Path.t(), [page()]) :: Path.t()
  @spec write!(Path.t(), [page()], keyword()) :: Path.t()
  def write!(path, pages, info \\ []) do
    File.write!(path, build(pages, info))
    path
  end

  @doc """
  A one page document filled edge to edge in the given colour.

  The colour is `{red, green, blue}`, each from 0 to 1.
  """
  @spec filled(Path.t(), {number(), number(), number()}, keyword()) :: Path.t()
  def filled(path, {red, green, blue}, options \\ []) do
    {left, bottom, right, top} = box = Keyword.get(options, :box, {0, 0, 612, 792})

    content =
      "#{red} #{green} #{blue} rg #{left} #{bottom} #{right - left} #{top - bottom} re f"

    write!(path, [[box: box, content: content] ++ Keyword.delete(options, :box)])
  end

  #########
  # Helpers

  @spec build([page()], keyword()) :: binary()
  defp build(pages, info) do
    header = "%PDF-1.7\n"
    page_object_numbers = Enum.map(1..length(pages)//1, &(3 + (&1 - 1) * 2))
    kids = Enum.map_join(page_object_numbers, " ", &"#{&1} 0 R")

    objects =
      [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [#{kids}] /Count #{length(pages)} >>"
      ] ++
        Enum.flat_map(Enum.zip(pages, page_object_numbers), &page_objects/1) ++
        info_object(info)

    {body, offsets} =
      Enum.reduce(objects, {header, []}, fn object, {body, offsets} ->
        number = length(offsets) + 1
        {body <> "#{number} 0 obj\n#{object}\nendobj\n", [byte_size(body) | offsets]}
      end)

    offsets = Enum.reverse(offsets)
    size = length(offsets) + 1

    table =
      "0000000000 65535 f \n" <>
        Enum.map_join(offsets, fn offset ->
          String.pad_leading(Integer.to_string(offset), 10, "0") <> " 00000 n \n"
        end)

    trailer =
      if info == [] do
        "<< /Size #{size} /Root 1 0 R >>"
      else
        "<< /Size #{size} /Root 1 0 R /Info #{size - 1} 0 R >>"
      end

    body <>
      "xref\n0 #{size}\n" <>
      table <>
      "trailer\n#{trailer}\nstartxref\n#{byte_size(body)}\n%%EOF\n"
  end

  @spec info_object(keyword()) :: [binary()]
  defp info_object([]), do: []

  defp info_object(info) do
    entries =
      Enum.map_join(info, " ", fn {name, value} -> "/#{name} #{pdf_string(value)}" end)

    ["<< #{entries} >>"]
  end

  @spec pdf_string(binary()) :: binary()
  defp pdf_string(value) do
    if ascii?(value) do
      "(" <> String.replace(value, ~r/([()\\])/, "\\\\\\1") <> ")"
    else
      "<FEFF" <> Base.encode16(:unicode.characters_to_binary(value, :utf8, {:utf16, :big})) <> ">"
    end
  end

  @spec ascii?(binary()) :: boolean()
  defp ascii?(value), do: for(<<byte <- value>>, byte > 127, do: byte) == []

  @spec page_objects({page(), pos_integer()}) :: [binary()]
  defp page_objects({page, number}) do
    {left, bottom, right, top} = Keyword.get(page, :box, {0, 0, 612, 792})
    rotation = Keyword.get(page, :rotation, 0)
    content = Keyword.get(page, :content, "")

    [
      """
      << /Type /Page /Parent 2 0 R /MediaBox [#{left} #{bottom} #{right} #{top}] \
      /Rotate #{rotation} /Resources << >> /Contents #{number + 1} 0 R >>\
      """,
      "<< /Length #{byte_size(content)} >>\nstream\n#{content}\nendstream"
    ]
  end
end
