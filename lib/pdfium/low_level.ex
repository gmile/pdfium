defmodule PDFium.LowLevel do
  @moduledoc """
  pdfium's own functions, one for one, each named after the C function it
  calls: `FPDF_GetPageCount` is `fpdf_get_page_count/1`. `PDFium` and
  `PDFium.Toolbox` are built from these.

  They hold no hands. Arguments mean what pdfium's headers say they mean,
  flags are the integers pdfium takes, and the caller closes what it opens in
  the order pdfium asks for. A mistake gives a wrong answer or a broken
  document, so read pdfium's documentation before reaching for them.

  What they do keep is the VM safe. Every call waits its turn on the one lock
  pdfium needs and runs on a dirty scheduler. A handle the garbage collector
  drops is closed on the next call, and a handle that was closed answers
  `{:error, :document_closed}` instead of crashing.
  """

  @typedoc "A document, `FPDF_DOCUMENT`."
  @type document :: reference()

  @typedoc """
  Why pdfium would not open a document, from `FPDF_GetLastError`: unreadable
  `:file`, broken `:format`, a missing or wrong `:password`, an unsupported
  `:security` scheme, an unreadable `:page`, or `:unknown`.
  """
  @type load_error :: :unknown | :file | :format | :password | :security | :page

  @doc """
  `FPDF_LoadMemDocument64`: opens a document from its contents, and keeps them
  for as long as the document is open.

      {:ok, document} = PDFium.LowLevel.fpdf_load_mem_document64(contents, nil)
  """
  @spec fpdf_load_mem_document64(binary(), binary() | nil) ::
          {:ok, document()} | {:error, load_error()}
  defdelegate fpdf_load_mem_document64(contents, password), to: PDFium.NIF

  @doc """
  `FPDF_CreateNewDocument`: makes an empty document.

      {:ok, document} = PDFium.LowLevel.fpdf_create_new_document()
  """
  @spec fpdf_create_new_document() :: {:ok, document()}
  defdelegate fpdf_create_new_document(), to: PDFium.NIF

  @doc """
  `FPDF_CloseDocument`: closes a document. Closing it again does nothing.

      :ok = PDFium.LowLevel.fpdf_close_document(document)
  """
  @spec fpdf_close_document(document()) :: :ok
  defdelegate fpdf_close_document(document), to: PDFium.NIF

  @doc """
  `FPDF_GetPageCount`: how many pages the document has.

      {:ok, 3} = PDFium.LowLevel.fpdf_get_page_count(document)
  """
  @spec fpdf_get_page_count(document()) :: {:ok, non_neg_integer()} | {:error, atom()}
  defdelegate fpdf_get_page_count(document), to: PDFium.NIF

  @doc """
  `FPDF_GetSecurityHandlerRevision`: the revision of the standard security
  handler, or `-1` when the document is not encrypted.

      {:ok, 6} = PDFium.LowLevel.fpdf_get_security_handler_revision(document)
  """
  @spec fpdf_get_security_handler_revision(document()) :: {:ok, integer()} | {:error, atom()}
  defdelegate fpdf_get_security_handler_revision(document), to: PDFium.NIF

  @doc """
  `FPDF_GetMetaText`: an entry of the Info dictionary in UTF-16LE, without the
  terminating zeros, or `""` when there is none.

      {:ok, <<"T", 0, "i", 0, "t", 0>>} = PDFium.LowLevel.fpdf_get_meta_text(document, "Title")
  """
  @spec fpdf_get_meta_text(document(), binary()) :: {:ok, binary()} | {:error, atom()}
  defdelegate fpdf_get_meta_text(document, tag), to: PDFium.NIF

  @doc """
  `FPDF_SaveAsCopy`: the document as it would be written with `flags`, such as
  `FPDF_REMOVE_SECURITY`, `4`.

      {:ok, <<"%PDF-", _::binary>>} = PDFium.LowLevel.fpdf_save_as_copy(document, 0)
  """
  @spec fpdf_save_as_copy(document(), non_neg_integer()) :: {:ok, binary()} | {:error, atom()}
  defdelegate fpdf_save_as_copy(document, flags), to: PDFium.NIF

  @doc """
  `FPDF_ImportPagesByIndex`: copies pages of `src` into `dest` before page
  `index`. `nil` copies every page.

      :ok = PDFium.LowLevel.fpdf_import_pages_by_index(dest, src, [2, 0], 0)
  """
  @spec fpdf_import_pages_by_index(
          document(),
          document(),
          [non_neg_integer()] | nil,
          non_neg_integer()
        ) :: :ok | {:error, atom()}
  defdelegate fpdf_import_pages_by_index(dest, src, page_indices, index), to: PDFium.NIF
end
