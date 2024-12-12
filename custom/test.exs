defmodule PDFium do
  @on_load :load_nif

  def load_nif do
    :erlang.load_nif(~c"pdfium_nif", 0)
  end

  def load_document(_filename), do: :erlang.nif_error(:nif_not_loaded)

  def get_page_count(_document), do: :erlang.nif_error(:nif_not_loaded)
end

{:ok, ref} = PDFium.load_document("/Users/eugene/Downloads/7ade6db09604a8b41104763c6f16a987.pdf")
{:ok, pages} = PDFium.get_page_count(ref)

IO.inspect(pages, label: "pages")
