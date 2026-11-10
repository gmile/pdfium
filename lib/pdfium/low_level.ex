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
  drops is closed on the next call. A handle that was closed answers
  `{:error, :document_closed}`, `{:error, :page_closed}` or
  `{:error, :bitmap_destroyed}` instead of crashing, and so does a page of a
  closed document.
  """

  @typedoc "A document, `FPDF_DOCUMENT`."
  @type document :: reference()

  @typedoc "A page loaded from a document, `FPDF_PAGE`. It keeps its document alive."
  @type page :: reference()

  @typedoc "A bitmap, `FPDF_BITMAP`."
  @type bitmap :: reference()

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

  @doc """
  `FPDF_LoadPage`: loads a page, counted from zero.

      {:ok, page} = PDFium.LowLevel.fpdf_load_page(document, 0)
  """
  @spec fpdf_load_page(document(), non_neg_integer()) :: {:ok, page()} | {:error, atom()}
  defdelegate fpdf_load_page(document, index), to: PDFium.NIF

  @doc """
  `FPDF_ClosePage`: closes a page. Closing it again does nothing.

      :ok = PDFium.LowLevel.fpdf_close_page(page)
  """
  @spec fpdf_close_page(page()) :: :ok
  defdelegate fpdf_close_page(page), to: PDFium.NIF

  @doc """
  `FPDF_GetPageWidthF`: the width of the page as a reader shows it, in points.

      {:ok, 612.0} = PDFium.LowLevel.fpdf_get_page_width_f(page)
  """
  @spec fpdf_get_page_width_f(page()) :: {:ok, float()} | {:error, atom()}
  defdelegate fpdf_get_page_width_f(page), to: PDFium.NIF

  @doc """
  `FPDF_GetPageHeightF`: the height of the page as a reader shows it, in points.

      {:ok, 792.0} = PDFium.LowLevel.fpdf_get_page_height_f(page)
  """
  @spec fpdf_get_page_height_f(page()) :: {:ok, float()} | {:error, atom()}
  defdelegate fpdf_get_page_height_f(page), to: PDFium.NIF

  @doc """
  `FPDF_GetPageBoundingBox`: the MediaBox clipped by the CropBox, as the fields
  of `FS_RECTF` in order, `{left, top, right, bottom}`.

      {:ok, {0.0, 792.0, 612.0, 0.0}} = PDFium.LowLevel.fpdf_get_page_bounding_box(page)
  """
  @spec fpdf_get_page_bounding_box(page()) ::
          {:ok, {float(), float(), float(), float()}} | {:error, atom()}
  defdelegate fpdf_get_page_bounding_box(page), to: PDFium.NIF

  @doc """
  `FPDFPage_GetRotation`: how far the page is turned clockwise, in quarter turns.

      {:ok, 1} = PDFium.LowLevel.fpdfpage_get_rotation(page)
  """
  @spec fpdfpage_get_rotation(page()) :: {:ok, 0..3} | {:error, atom()}
  defdelegate fpdfpage_get_rotation(page), to: PDFium.NIF

  @doc """
  `FPDFPage_GetAnnotCount`: how many annotations the page carries.

      {:ok, 2} = PDFium.LowLevel.fpdfpage_get_annot_count(page)
  """
  @spec fpdfpage_get_annot_count(page()) :: {:ok, non_neg_integer()} | {:error, atom()}
  defdelegate fpdfpage_get_annot_count(page), to: PDFium.NIF

  @doc """
  `FPDFPage_Flatten`: draws the page's annotations into its content, by the
  appearance `flag` names, `FLAT_NORMALDISPLAY` `0` or `FLAT_PRINT` `1`.
  Answers `FLATTEN_FAIL` `0`, `FLATTEN_SUCCESS` `1` or `FLATTEN_NOTHINGTODO` `2`.

      {:ok, 1} = PDFium.LowLevel.fpdfpage_flatten(page, 0)
  """
  @spec fpdfpage_flatten(page(), non_neg_integer()) :: {:ok, 0..2} | {:error, atom()}
  defdelegate fpdfpage_flatten(page, flag), to: PDFium.NIF

  @doc """
  `FPDF_RenderPageBitmap`: draws the page into `size_x` by `size_y` pixels of
  the bitmap from `start_x`, `start_y`, turned `rotate` quarter turns, with
  `flags` such as `FPDF_ANNOT` `0x01` and `FPDF_REVERSE_BYTE_ORDER` `0x10`.

      :ok = PDFium.LowLevel.fpdf_render_page_bitmap(bitmap, page, 0, 0, 612, 792, 0, 0x11)
  """
  @spec fpdf_render_page_bitmap(
          bitmap(),
          page(),
          integer(),
          integer(),
          integer(),
          integer(),
          0..3,
          non_neg_integer()
        ) :: :ok | {:error, atom()}
  defdelegate fpdf_render_page_bitmap(
                bitmap,
                page,
                start_x,
                start_y,
                size_x,
                size_y,
                rotate,
                flags
              ),
              to: PDFium.NIF

  @doc """
  `FPDFBitmap_Create`: a bitmap of 32 bits a pixel, BGRx, or BGRA when `alpha`
  is not `0`. Its contents are undefined until filled.

      {:ok, bitmap} = PDFium.LowLevel.fpdfbitmap_create(612, 792, 0)
  """
  @spec fpdfbitmap_create(integer(), integer(), integer()) ::
          {:ok, bitmap()} | {:error, atom()}
  defdelegate fpdfbitmap_create(width, height, alpha), to: PDFium.NIF

  @doc """
  `FPDFBitmap_FillRect`: fills a rectangle of the bitmap with an ARGB `color`.

      :ok = PDFium.LowLevel.fpdfbitmap_fill_rect(bitmap, 0, 0, 612, 792, 0xFFFFFFFF)
  """
  @spec fpdfbitmap_fill_rect(
          bitmap(),
          integer(),
          integer(),
          integer(),
          integer(),
          non_neg_integer()
        ) :: :ok | {:error, atom()}
  defdelegate fpdfbitmap_fill_rect(bitmap, left, top, width, height, color), to: PDFium.NIF

  @doc """
  `FPDFBitmap_GetBuffer`: a copy of the bitmap's pixels, four bytes each, row
  after row.

      {:ok, pixels} = PDFium.LowLevel.fpdfbitmap_get_buffer(bitmap)
  """
  @spec fpdfbitmap_get_buffer(bitmap()) :: {:ok, binary()} | {:error, atom()}
  defdelegate fpdfbitmap_get_buffer(bitmap), to: PDFium.NIF

  @doc """
  `FPDFBitmap_Destroy`: frees a bitmap. Destroying it again does nothing.

      :ok = PDFium.LowLevel.fpdfbitmap_destroy(bitmap)
  """
  @spec fpdfbitmap_destroy(bitmap()) :: :ok
  defdelegate fpdfbitmap_destroy(bitmap), to: PDFium.NIF
end
