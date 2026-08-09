defmodule PDFium do
  @typedoc """
  Why pdfium would not open a document, named as pdfium names it.

  `:file` is a file it could not read at all, `:format` one that is not a PDF or
  is damaged past reading, `:password` one that needs a password it was not
  given, `:security` one encrypted with a scheme it does not implement, and
  `:page` one whose pages it cannot read. `:xfa_load` and `:xfa_layout` only
  arise in a build with XFA compiled in. `:unknown` is pdfium declining to say,
  and covers any code a later pdfium adds.
  """
  @type load_error ::
          :unknown
          | :file
          | :format
          | :password
          | :security
          | :page
          | :xfa_load
          | :xfa_layout

  @doc """
  Opens a document.
  """
  @spec load_document(Path.t()) :: {:ok, reference()} | {:error, load_error()}
  defdelegate load_document(filename), to: PDFium.NIF

  defdelegate close_document(document), to: PDFium.NIF

  defdelegate get_page_count(document), to: PDFium.NIF

  @doc """
  Renders a page to RGBA pixels at the given resolution.

  Annotations are drawn, because a page is what a reader shows and every reader
  draws them. A page whose annotation paints over its content renders without
  that content, which is the point of the annotation.
  """
  @spec get_page_bitmap(reference(), non_neg_integer(), pos_integer()) ::
          {:ok, binary(), non_neg_integer(), non_neg_integer()} | {:error, atom()}
  defdelegate get_page_bitmap(document, page_number, dpi), to: PDFium.NIF

  @typedoc """
  The MediaBox of a page, in points, and how far the page is turned, in degrees.

  A box is written in the file as any two opposite corners; this one is sorted,
  so `left` never passes `right` nor `bottom` `top`. Neither corner is required
  to sit at the origin.
  """
  @type page_box :: %{
          left: float(),
          bottom: float(),
          right: float(),
          top: float(),
          rotation: 0 | 90 | 180 | 270
        }

  @doc """
  The MediaBox and rotation of every page, in order.
  """
  @spec get_page_boxes(reference()) :: {:ok, [page_box()]} | {:error, atom()}
  def get_page_boxes(document) do
    with {:ok, boxes} <- PDFium.NIF.get_page_boxes(document) do
      {:ok, Enum.map(boxes, &to_page_box/1)}
    end
  end

  defp to_page_box({left, bottom, right, top, rotation}) do
    %{left: left, bottom: bottom, right: right, top: top, rotation: rotation}
  end

  @typedoc """
  How large a page is as a reader shows it, in points.

  This is the box the page is laid out in rather than the one written down, so
  a page turned a quarter has already had the two swapped.
  """
  @type page_size :: %{width: float(), height: float()}

  @doc """
  The displayed size of every page of every document given, in order.

  Documents are asked about together because each call over this boundary waits
  its turn on the same lock, and placing anything on a page wants the size of
  that page and of what is going onto it.
  """
  @spec get_page_sizes([reference()]) :: {:ok, [[page_size()]]} | {:error, atom()}
  def get_page_sizes(documents) do
    with {:ok, sizes} <- PDFium.NIF.get_page_sizes(documents) do
      {:ok, Enum.map(sizes, fn pages -> Enum.map(pages, &to_page_size/1) end)}
    end
  end

  defp to_page_size({width, height}), do: %{width: width, height: height}

  @doc """
  An entry of the document's Info dictionary, as text.

  Any key may be asked for, not only the ones the specification names, and the
  answer is decoded whichever of the two encodings a PDF is allowed to store it
  in. A key the document does not carry reads as an empty string.
  """
  @spec get_meta_text(reference(), binary()) :: {:ok, binary()} | {:error, atom()}
  defdelegate get_meta_text(document, key), to: PDFium.NIF

  @doc """
  How many annotations each page carries, in order.
  """
  @spec get_annotation_counts(reference()) :: {:ok, [non_neg_integer()]} | {:error, atom()}
  defdelegate get_annotation_counts(document), to: PDFium.NIF

  @doc """
  Makes an empty document.
  """
  @spec create_document() :: {:ok, reference()} | {:error, atom()}
  defdelegate create_document(), to: PDFium.NIF

  @doc """
  Writes a document out.
  """
  @spec save(reference(), Path.t()) :: {:ok, :saved} | {:error, atom()}
  defdelegate save(document, output_path), to: PDFium.NIF

  @doc """
  Copies pages of `source` into `destination`, starting at page `at`.

  `pages` is `:all` or a list of page indexes counted from zero, in the order
  they should arrive.
  """
  @spec import_pages(reference(), reference(), :all | [non_neg_integer()], non_neg_integer()) ::
          {:ok, :imported} | {:error, atom()}
  def import_pages(destination, source, pages, at \\ 0)

  def import_pages(destination, source, :all, at),
    do: PDFium.NIF.import_pages(destination, source, [], at)

  def import_pages(_destination, _source, [], _at), do: {:error, :no_pages}

  def import_pages(destination, source, pages, at) when is_list(pages),
    do: PDFium.NIF.import_pages(destination, source, pages, at)

  @doc """
  Runs `function` with an empty document and closes it again.
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

  defdelegate flatten(document, output_path), to: PDFium.NIF
end
