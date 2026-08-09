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

  defdelegate flatten(document, output_path), to: PDFium.NIF
end
