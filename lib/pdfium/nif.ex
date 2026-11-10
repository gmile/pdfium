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

  def fpdf_get_page_size_by_index_f(_document, _index), do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_save_as_copy(_document, _flags), do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_import_pages_by_index(_dest, _src, _page_indices, _index),
    do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_load_page(_document, _index), do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_close_page(_page), do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_get_page_width_f(_page), do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_get_page_height_f(_page), do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_get_page_bounding_box(_page), do: :erlang.nif_error(:nif_not_loaded)

  def fpdfpage_get_rotation(_page), do: :erlang.nif_error(:nif_not_loaded)

  def fpdfpage_get_annot_count(_page), do: :erlang.nif_error(:nif_not_loaded)

  def fpdfpage_flatten(_page, _flag), do: :erlang.nif_error(:nif_not_loaded)

  def fpdf_render_page_bitmap(_bitmap, _page, _x, _y, _width, _height, _rotate, _flags),
    do: :erlang.nif_error(:nif_not_loaded)

  def fpdfbitmap_create(_width, _height, _alpha), do: :erlang.nif_error(:nif_not_loaded)

  def fpdfbitmap_fill_rect(_bitmap, _left, _top, _width, _height, _color),
    do: :erlang.nif_error(:nif_not_loaded)

  def fpdfbitmap_get_buffer(_bitmap), do: :erlang.nif_error(:nif_not_loaded)

  def fpdfbitmap_destroy(_bitmap), do: :erlang.nif_error(:nif_not_loaded)

  def get_page_bitmap(_document, _page_number, _dpi), do: :erlang.nif_error(:nif_not_loaded)

  def stamp(_document, _placements), do: :erlang.nif_error(:nif_not_loaded)
end
