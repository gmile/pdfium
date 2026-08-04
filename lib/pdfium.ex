defmodule PDFium do
  defdelegate load_document(filename), to: PDFium.NIF

  defdelegate close_document(document), to: PDFium.NIF

  defdelegate get_page_count(document), to: PDFium.NIF

  defdelegate get_page_bitmap(document, page_number, dpi), to: PDFium.NIF

  defdelegate flatten(document, output_path), to: PDFium.NIF

  defdelegate load_font(data), to: PDFium.NIF

  defdelegate close_font(font), to: PDFium.NIF

  defdelegate measure_text(font, size, texts), to: PDFium.NIF

  @doc """
  Draws strings onto a page of the given size and writes it out on its own.

  Each placement is `{text, x, y}`, where the point is the pen: `y` is the
  baseline, and `x` the left edge of the first glyph's advance.
  """
  @spec draw_text(
          reference(),
          number(),
          {number(), number()},
          [{binary(), number(), number()}],
          Path.t()
        ) :: {:ok, :drawn} | {:error, atom()}
  # Coordinates are floats at the boundary. Whole numbers are the natural way to
  # say a page is 612 by 792, and a list of small integers is a charlist, which
  # is not what the other side is expecting to decode.
  def draw_text(font, size, {width, height}, placements, output_path) do
    texts = Enum.map(placements, &elem(&1, 0))
    xs = Enum.map(placements, &(elem(&1, 1) / 1))
    ys = Enum.map(placements, &(elem(&1, 2) / 1))

    PDFium.NIF.draw_text(font, size / 1, width / 1, height / 1, texts, xs, ys, output_path)
  end
end
