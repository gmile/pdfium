defmodule PDFium do
  defdelegate load_document(filename), to: PDFium.NIF

  defdelegate close_document(document), to: PDFium.NIF

  defdelegate get_page_count(document), to: PDFium.NIF

  defdelegate get_page_bitmap(document, page_number, dpi), to: PDFium.NIF
end
