defmodule PDFium do
  defdelegate load_document(filename), to: PDFium.NIF

  defdelegate close_document(document), to: PDFium.NIF

  defdelegate get_page_count(document), to: PDFium.NIF

  defdelegate get_page_bitmap(document, page_number, dpi), to: PDFium.NIF

  defdelegate flatten(document, output_path), to: PDFium.NIF

  defdelegate load_font(data), to: PDFium.NIF

  defdelegate close_font(font), to: PDFium.NIF

  defdelegate measure_text(font, size, texts), to: PDFium.NIF
end
