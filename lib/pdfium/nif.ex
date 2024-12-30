defmodule PDFium do
  @on_load :load_nif

  def load_nif do
    path = :filename.join(:code.priv_dir(:pdfium), ~c"pdfium_nif")
    :erlang.load_nif(path, 0)
  end

  def load_document(_filename), do: :erlang.nif_error(:nif_not_loaded)

  def get_page_count(_document), do: :erlang.nif_error(:nif_not_loaded)
end
