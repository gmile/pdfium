defmodule PDFium do
  @moduledoc """
  Bindings to pdfium: open, inspect, render, flatten, stamp and write PDF
  documents. `PDFium.Toolbox` does whole jobs on top of these.

  Every call on a document waits its turn on one lock, since pdfium is not
  thread safe, and runs on a dirty scheduler.
  """

  alias PDFium.LowLevel

  @fpdf_remove_security 4
  @flat %{display: 0, print: 1}
  @flatten_fail 0
  @fpdf_annot 0x01
  @fpdf_reverse_byte_order 0x10

  @typedoc "A document to open: a path, or its contents."
  @type source :: Path.t() | {:bytes, binary()}

  @typedoc """
  Why pdfium would not open a document: unreadable `:file`, broken `:format`,
  a missing or wrong `:password`, an unsupported `:security` scheme, an
  unreadable `:page`, or `:unknown`.
  """
  @type load_error :: LowLevel.load_error()

  @doc """
  Opens a document from a path or from `{:bytes, contents}`.

      {:ok, document} = PDFium.open_document("contract.pdf")
      {:ok, document} = PDFium.open_document({:bytes, contents}, password: "secret")

  The document keeps the contents for as long as it is open.
  """
  @spec open_document(source(), password: binary()) ::
          {:ok, reference()} | {:error, load_error()}
  def open_document(source, options \\ [])

  def open_document({:bytes, contents}, options),
    do: LowLevel.fpdf_load_mem_document64(contents, Keyword.get(options, :password))

  def open_document(path, options) do
    case File.read(path) do
      {:ok, contents} -> open_document({:bytes, contents}, options)
      {:error, _reason} -> {:error, :file}
    end
  end

  @doc """
  Closes a document and frees what it held. A closed document answers
  `{:error, :document_closed}` to everything.
  """
  @spec close_document(reference()) :: :ok
  defdelegate close_document(document), to: LowLevel, as: :fpdf_close_document

  @doc """
  Opens `source`, runs `function` with the document, and closes it again, even
  if the work raises.

      {:ok, 3} = PDFium.with_document("contract.pdf", &PDFium.get_page_count/1)
  """
  @spec with_document(source(), (reference() -> result), password: binary()) ::
          result | {:error, load_error()}
        when result: term()
  def with_document(source, function, options \\ []) do
    with {:ok, document} <- open_document(source, options) do
      try do
        function.(document)
      after
        close_document(document)
      end
    end
  end

  @doc """
  How many pages the document has.

      {:ok, 3} = PDFium.get_page_count(document)
  """
  @spec get_page_count(reference()) :: {:ok, non_neg_integer()} | {:error, atom()}
  defdelegate get_page_count(document), to: LowLevel, as: :fpdf_get_page_count

  @doc """
  Renders a page to RGBA pixels at `dpi`, annotations included.

      {:ok, {pixels, width, height}} = PDFium.get_page_bitmap(document, 0, 150)
  """
  @spec get_page_bitmap(reference(), non_neg_integer(), pos_integer()) ::
          {:ok, {binary(), non_neg_integer(), non_neg_integer()}} | {:error, atom()}
  def get_page_bitmap(document, page_number, dpi) do
    with_page(document, page_number, fn page ->
      with {:ok, width} <- LowLevel.fpdf_get_page_width_f(page),
           {:ok, height} <- LowLevel.fpdf_get_page_height_f(page) do
        render(page, pixels(width, dpi), pixels(height, dpi))
      end
    end)
  end

  @typedoc """
  The box a page is drawn in, its MediaBox clipped by its CropBox, in points
  with corners sorted, and its rotation in degrees. Neither corner has to sit
  at the origin.
  """
  @type page_box :: %{
          left: float(),
          bottom: float(),
          right: float(),
          top: float(),
          rotation: 0 | 90 | 180 | 270
        }

  @doc """
  The box and rotation of every page, in order: what placing content in a
  page's own coordinates needs.

      {:ok, [%{left: 0.0, bottom: 0.0, right: 612.0, top: 792.0, rotation: 0}]} =
        PDFium.get_page_boxes(document)
  """
  @spec get_page_boxes(reference()) :: {:ok, [page_box()]} | {:error, atom()}
  def get_page_boxes(document) do
    each_page(document, fn page ->
      with {:ok, {left, top, right, bottom}} <- LowLevel.fpdf_get_page_bounding_box(page),
           {:ok, rotation} <- LowLevel.fpdfpage_get_rotation(page) do
        {:ok, %{left: left, bottom: bottom, right: right, top: top, rotation: rotation * 90}}
      end
    end)
  end

  @typedoc "The size of a page as a reader shows it, in points."
  @type page_size :: %{width: float(), height: float()}

  @doc """
  The size of every page as a reader shows it, in points, in order.

      {:ok, [%{width: 612.0, height: 792.0}]} = PDFium.get_page_sizes(document)
  """
  @spec get_page_sizes(reference()) :: {:ok, [page_size()]} | {:error, atom()}
  def get_page_sizes(document) do
    each_index(document, fn index ->
      with {:ok, {width, height}} <- LowLevel.fpdf_get_page_size_by_index_f(document, index),
           do: {:ok, %{width: width, height: height}}
    end)
  end

  @doc """
  An entry of the document's Info dictionary, or `""` when it has none.

      {:ok, "A contract"} = PDFium.get_meta_text(document, "Title")
  """
  @spec get_meta_text(reference(), binary()) :: {:ok, binary()} | {:error, atom()}
  def get_meta_text(document, key) do
    with {:ok, utf16} <- LowLevel.fpdf_get_meta_text(document, key) do
      {:ok, :unicode.characters_to_binary(utf16, {:utf16, :little})}
    end
  end

  @doc """
  How many annotations each page carries, in order.

      {:ok, [2, 0]} = PDFium.get_annotation_counts(document)
  """
  @spec get_annotation_counts(reference()) :: {:ok, [non_neg_integer()]} | {:error, atom()}
  def get_annotation_counts(document),
    do: each_page(document, &LowLevel.fpdfpage_get_annot_count/1)

  @doc """
  The revision of the standard security handler the document is encrypted
  with, or `nil` when it is not encrypted.

      {:ok, 6} = PDFium.get_security_handler_revision(document)
  """
  @spec get_security_handler_revision(reference()) ::
          {:ok, pos_integer() | nil} | {:error, atom()}
  def get_security_handler_revision(document) do
    with {:ok, revision} <- LowLevel.fpdf_get_security_handler_revision(document) do
      {:ok, if(revision < 0, do: nil, else: revision)}
    end
  end

  @typedoc "Whether a written document keeps its encryption or is written in the clear."
  @type security :: :keep | :remove

  @doc """
  Draws a page's annotations into its content and drops them, in place.

      :ok = PDFium.flatten_page(document, 0)
      :ok = PDFium.flatten_page(document, 1, :print)

  `usage` picks the appearance drawn: `:display` is what a reader shows,
  `:print` what it would print.
  """
  @spec flatten_page(reference(), non_neg_integer(), :display | :print) :: :ok | {:error, atom()}
  def flatten_page(document, page_index, usage \\ :display) do
    with_page(document, page_index, fn page ->
      case LowLevel.fpdfpage_flatten(page, Map.fetch!(@flat, usage)) do
        {:ok, @flatten_fail} -> {:error, :flatten_failed}
        {:ok, _flattened} -> :ok
        error -> error
      end
    end)
  end

  @doc """
  Makes an empty document.

      {:ok, document} = PDFium.create_document()
  """
  @spec create_document() :: {:ok, reference()}
  defdelegate create_document(), to: LowLevel, as: :fpdf_create_new_document

  @doc """
  Writes the document to `output_path`.

      :ok = PDFium.save(document, "out.pdf")
      :ok = PDFium.save(document, "out.pdf", :remove)
  """
  @spec save(reference(), Path.t(), security()) :: :ok | {:error, atom()}
  def save(document, output_path, security \\ :keep) do
    with {:ok, binary} <- save_to_binary(document, security), do: File.write(output_path, binary)
  end

  @doc """
  The document as it would be written.

      {:ok, <<"%PDF-", _::binary>>} = PDFium.save_to_binary(document)
  """
  @spec save_to_binary(reference(), security()) :: {:ok, binary()} | {:error, atom()}
  def save_to_binary(document, security \\ :keep)

  def save_to_binary(document, :remove),
    do: LowLevel.fpdf_save_as_copy(document, @fpdf_remove_security)

  def save_to_binary(document, :keep), do: LowLevel.fpdf_save_as_copy(document, 0)

  @doc """
  Copies pages of `source` into `destination` at position `at`. `pages` is
  `:all` or page indexes counted from zero, in the order they should arrive.

      :ok = PDFium.import_pages(destination, source, :all)
      :ok = PDFium.import_pages(destination, source, [2, 0], 1)
  """
  @spec import_pages(reference(), reference(), :all | [non_neg_integer()], non_neg_integer()) ::
          :ok | {:error, atom()}
  def import_pages(destination, source, pages, at \\ 0)

  def import_pages(destination, source, :all, at),
    do: LowLevel.fpdf_import_pages_by_index(destination, source, nil, at)

  def import_pages(_destination, _source, [], _at), do: {:error, :no_pages}

  def import_pages(destination, source, pages, at) when is_list(pages),
    do: LowLevel.fpdf_import_pages_by_index(destination, source, pages, at)

  @doc """
  Runs `function` with an empty document and closes it again.

      {:ok, binary} =
        PDFium.with_new_document(fn output ->
          with :ok <- PDFium.import_pages(output, source, [0]), do: PDFium.save_to_binary(output)
        end)
  """
  @spec with_new_document((reference() -> result)) :: result | {:error, atom()}
        when result: term()
  def with_new_document(function) do
    with {:ok, document} <- create_document() do
      try do
        function.(document)
      after
        close_document(document)
      end
    end
  end

  @typedoc """
  Where an overlay goes, as the matrix `{a, b, c, d, e, f}` in the page as a
  reader shows it, origin at its bottom left. `{1, 0, 0, 1, 0, 0}` leaves the
  overlay where and how large it was drawn.
  """
  @type placement :: {number(), number(), number(), number(), number(), number()}

  @doc """
  Draws overlays over pages of `document`, in place.

      :ok = PDFium.stamp(document, [{overlay, 0, 0, {1, 0, 0, 1, 0, 0}}])

  A placement is `{overlay, overlay_page, page_index, matrix}`, pages counted
  from zero. Placements on one page stack in the order given. A placement that
  fails leaves the document as it was.
  """
  @spec stamp(reference(), [{reference(), non_neg_integer(), non_neg_integer(), placement()}]) ::
          :ok | {:error, atom()}
  def stamp(document, placements), do: PDFium.NIF.stamp(document, as_floats(placements))

  @spec as_floats([{reference(), non_neg_integer(), non_neg_integer(), placement()}]) :: [
          {reference(), non_neg_integer(), non_neg_integer(), placement()}
        ]
  defp as_floats(placements) do
    Enum.map(placements, fn {overlay, overlay_page, page_index, {a, b, c, d, e, f}} ->
      {overlay, overlay_page, page_index, {a / 1, b / 1, c / 1, d / 1, e / 1, f / 1}}
    end)
  end

  defp render(page, width, height) do
    with {:ok, bitmap} <- LowLevel.fpdfbitmap_create(width, height, 0) do
      try do
        flags = Bitwise.bor(@fpdf_annot, @fpdf_reverse_byte_order)

        with :ok <- LowLevel.fpdfbitmap_fill_rect(bitmap, 0, 0, width, height, 0xFFFFFFFF),
             :ok <- LowLevel.fpdf_render_page_bitmap(bitmap, page, 0, 0, width, height, 0, flags),
             {:ok, pixels} <- LowLevel.fpdfbitmap_get_buffer(bitmap),
             do: {:ok, {pixels, width, height}}
      after
        LowLevel.fpdfbitmap_destroy(bitmap)
      end
    end
  end

  # pdfium measures pages in single precision, so the pixels are counted in it
  # too, or a page could come out a pixel narrower than it always has.
  defp pixels(points, dpi), do: trunc(single(single(points * dpi) / 72))

  defp single(value) do
    <<single::float-32>> = <<value::float-32>>
    single
  end

  defp each_page(document, function),
    do: each_index(document, &with_page(document, &1, function))

  defp each_index(document, function) do
    with {:ok, count} <- LowLevel.fpdf_get_page_count(document) do
      0..(count - 1)//1
      |> Enum.reduce_while({:ok, []}, fn index, {:ok, results} ->
        case function.(index) do
          {:ok, result} -> {:cont, {:ok, [result | results]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, results} -> {:ok, Enum.reverse(results)}
        error -> error
      end
    end
  end

  defp with_page(document, index, function) do
    with {:ok, page} <- LowLevel.fpdf_load_page(document, index) do
      try do
        function.(page)
      after
        LowLevel.fpdf_close_page(page)
      end
    end
  end
end
