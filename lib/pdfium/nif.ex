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

  def get_page_boxes(_document), do: :erlang.nif_error(:nif_not_loaded)

  def get_page_sizes(_documents), do: :erlang.nif_error(:nif_not_loaded)

  def get_annotation_counts(_document), do: :erlang.nif_error(:nif_not_loaded)

  def get_meta_text(_document, _key), do: :erlang.nif_error(:nif_not_loaded)

  def flatten_page(_document, _page_index, _usage), do: :erlang.nif_error(:nif_not_loaded)
  def create_document, do: :erlang.nif_error(:nif_not_loaded)

  def save(_document, _output_path), do: :erlang.nif_error(:nif_not_loaded)

  def import_pages(_dest, _src, _page_indices, _at), do: :erlang.nif_error(:nif_not_loaded)

  def stamp(_document, _placements, _output_path), do: :erlang.nif_error(:nif_not_loaded)
end
