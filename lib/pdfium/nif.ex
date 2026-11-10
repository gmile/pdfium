defmodule PDFium.NIF do
  @moduledoc false

  @on_load :load_nif

  def load_nif do
    # Loaded straight from the working directory when there is no application
    # around it, which is how the precompiled artefact is smoke tested.
    path =
      case :code.priv_dir(:pdfium) do
        # Spelled as a path rather than a name: a bare name sends the loader
        # looking through the system library directories instead of here.
        {:error, :bad_name} -> ~c"./pdfium_nif"
        directory -> :filename.join(directory, ~c"pdfium_nif")
      end

    :erlang.load_nif(path, 0)
  end

  def fpdf_load_mem_document64(_contents, _password), do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_create_new_document, do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_close_document(_document), do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_get_page_count(_document), do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_get_security_handler_revision(_document), do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_get_meta_text(_document, _tag), do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_save_as_copy(_document, _flags), do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_import_pages_by_index(_dest, _src, _page_indices, _index),
    do: :erlang.nif_error(:nif_not_loaded)

  def get_page_bitmap(_document, _page_number, _dpi), do: :erlang.nif_error(:nif_not_loaded)

  def get_page_boxes(_document), do: :erlang.nif_error(:nif_not_loaded)

  def get_page_sizes(_document), do: :erlang.nif_error(:nif_not_loaded)

  def get_annotation_counts(_document), do: :erlang.nif_error(:nif_not_loaded)

  def flatten_page(_document, _page_index, _usage), do: :erlang.nif_error(:nif_not_loaded)

  def stamp(_document, _placements), do: :erlang.nif_error(:nif_not_loaded)
end
