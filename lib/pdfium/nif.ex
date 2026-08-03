defmodule PDFium.NIF do
  @on_load :load_nif

  def load_nif do
    path = :filename.join(:code.priv_dir(:pdfium), ~c"pdfium_nif")
    :erlang.load_nif(path, 0)
  end

  def load_document(_filename), do: :erlang.nif_error(:nif_not_loaded)

  def close_document(_document), do: :erlang.nif_error(:nif_not_loaded)

  def get_page_count(_document), do: :erlang.nif_error(:nif_not_loaded)

  def get_page_bitmap(_document, _page_number, _dpi), do: :erlang.nif_error(:nif_not_loaded)

  def flatten(_document, _output_path), do: :erlang.nif_error(:nif_not_loaded)

  def load_font(_data), do: :erlang.nif_error(:nif_not_loaded)

  def close_font(_font), do: :erlang.nif_error(:nif_not_loaded)

  def measure_text(_font, _size, _texts), do: :erlang.nif_error(:nif_not_loaded)
end
