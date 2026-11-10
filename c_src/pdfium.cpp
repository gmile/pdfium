#include "pdfium_nif.hpp"

#include <cpp/fpdf_scopers.h>
#include <fpdf_annot.h>
#include <fpdf_doc.h>
#include <fpdf_edit.h>
#include <fpdf_flatten.h>
#include <fpdf_ppo.h>
#include <fpdf_save.h>
#include <optional>
#include <tuple>
#include <vector>

static fine::Atom load_errors[] = {fine::Atom("unknown"),  fine::Atom("unknown"), fine::Atom("file"),
                                   fine::Atom("format"),   fine::Atom("password"), fine::Atom("security"),
                                   fine::Atom("page")};
static fine::Atom page_closed("page_closed");
static fine::Atom bitmap_destroyed("bitmap_destroyed");
static fine::Atom bitmap_creation_failed("bitmap_creation_failed");
static fine::Atom bounding_box_failed("bounding_box_failed");
static fine::Atom fill_rect_failed("fill_rect_failed");
static fine::Atom flatten_failed("flatten_failed");
static fine::Atom save_failed("save_failed");
static fine::Atom import_failed("import_failed");

static std::unique_ptr<fine::Mutex> pdfium_mutex;
static std::mutex pending_mutex;
static std::vector<std::function<void()>> pending;

void release_later(std::function<void()> release) {
    std::lock_guard guard(pending_mutex);
    pending.push_back(std::move(release));
}

static void release_pending() {
    for (;;) {
        std::vector<std::function<void()>> releases;
        {
            std::lock_guard guard(pending_mutex);
            releases.swap(pending);
        }
        if (releases.empty()) {
            return;
        }
        for (auto &release : releases) {
            release();
        }
    }
}

std::unique_lock<fine::Mutex> lock_pdfium() {
    std::unique_lock lock(*pdfium_mutex);
    release_pending();
    return lock;
}

void PDFDoc::destructor(ErlNifEnv *) {
    if (document) {
        release_later([document = document, buffer = std::move(buffer)] { FPDF_CloseDocument(document); });
    }
}

static void close_handle(PDFDoc &doc) {
    FPDF_CloseDocument(doc.document);
    doc.document = nullptr;
    std::string().swap(doc.buffer);
}

static void release_page(PDFDoc &doc) {
    if (--doc.open_pages == 0 && doc.closed) {
        close_handle(doc);
    }
}

void PDFPage::destructor(ErlNifEnv *) {
    if (page) {
        release_later([page = page, doc = doc] {
            FPDF_ClosePage(page);
            release_page(*doc);
        });
    }
}

void PDFBitmap::destructor(ErlNifEnv *) {
    if (bitmap) {
        release_later([bitmap = bitmap] { FPDFBitmap_Destroy(bitmap); });
    }
}

FINE_RESOURCE(PDFDoc);
FINE_RESOURCE(PDFPage);
FINE_RESOURCE(PDFBitmap);

static auto load_reg = fine::Registration::register_load([](ErlNifEnv *, void **, fine::Term) {
    FPDF_InitLibrary();
    pdfium_mutex = std::make_unique<fine::Mutex>("pdfium", "global");
});

static auto unload_reg = fine::Registration::register_unload([](ErlNifEnv *, void *) noexcept {
    release_pending();
    pdfium_mutex.reset();
    FPDF_DestroyLibrary();
});

template <typename F>
static auto with_page(const fine::ResourcePtr<PDFPage> &page, F f) -> decltype(f(page->page)) {
    auto lock = lock_pdfium();
    if (!page->page) {
        return fine::Error(page_closed);
    }
    if (page->doc->closed) {
        return fine::Error(document_closed);
    }
    return f(page->page);
}

template <typename F>
static auto with_bitmap(const fine::ResourcePtr<PDFBitmap> &bitmap, F f) -> decltype(f(bitmap->bitmap)) {
    auto lock = lock_pdfium();
    if (!bitmap->bitmap) {
        return fine::Error(bitmap_destroyed);
    }
    return f(bitmap->bitmap);
}

template <typename T, typename F>
static Result<std::vector<T>> each_page(const fine::ResourcePtr<PDFDoc> &doc, F f) {
    return with_document(doc, [&](FPDF_DOCUMENT document) -> Result<std::vector<T>> {
        std::vector<T> out;
        for (int index = 0, count = FPDF_GetPageCount(document); index < count; index++) {
            ScopedFPDFPage page(FPDF_LoadPage(document, index));
            if (!page) {
                return fine::Error(page_load_failed);
            }
            out.push_back(f(page.get()));
        }
        return fine::Ok(std::move(out));
    });
}

Result<fine::ResourcePtr<PDFDoc>> fpdf_load_mem_document64(ErlNifEnv *, std::string data,
                                                           std::optional<std::string> password) {
    auto doc = fine::make_resource<PDFDoc>(nullptr, std::move(data));
    auto lock = lock_pdfium();
    doc->document =
        FPDF_LoadMemDocument64(doc->buffer.data(), doc->buffer.size(), password ? password->c_str() : nullptr);
    if (!doc->document) {
        unsigned long error = FPDF_GetLastError();
        return fine::Error(load_errors[error < std::size(load_errors) ? error : 0]);
    }
    return fine::Ok(doc);
}

FINE_NIF(fpdf_load_mem_document64, ERL_NIF_DIRTY_JOB_CPU_BOUND);

fine::Ok<> fpdf_close_document(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc) {
    auto lock = lock_pdfium();
    if (!doc->closed) {
        doc->closed = true;
        if (doc->open_pages == 0) {
            close_handle(*doc);
        }
    }
    return fine::Ok<>();
}

FINE_NIF(fpdf_close_document, ERL_NIF_DIRTY_JOB_CPU_BOUND);

fine::Ok<fine::ResourcePtr<PDFDoc>> fpdf_create_new_document(ErlNifEnv *) {
    auto lock = lock_pdfium();
    return fine::Ok(fine::make_resource<PDFDoc>(FPDF_CreateNewDocument()));
}

FINE_NIF(fpdf_create_new_document, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<int64_t> fpdf_get_page_count(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc) {
    return with_document(doc, [](FPDF_DOCUMENT document) -> Result<int64_t> {
        return fine::Ok<int64_t>(FPDF_GetPageCount(document));
    });
}

FINE_NIF(fpdf_get_page_count, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<int64_t> fpdf_get_security_handler_revision(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc) {
    return with_document(doc, [](FPDF_DOCUMENT document) -> Result<int64_t> {
        return fine::Ok<int64_t>(FPDF_GetSecurityHandlerRevision(document));
    });
}

FINE_NIF(fpdf_get_security_handler_revision, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<std::tuple<std::string, int64_t, int64_t>> get_page_bitmap(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc,
                                                                  int64_t index, int64_t dpi) {
    return with_document(doc, [&](FPDF_DOCUMENT document) -> Result<std::tuple<std::string, int64_t, int64_t>> {
        ScopedFPDFPage page(FPDF_LoadPage(document, index));
        if (!page) {
            return fine::Error(page_load_failed);
        }
        int width = FPDF_GetPageWidthF(page.get()) * dpi / 72;
        int height = FPDF_GetPageHeightF(page.get()) * dpi / 72;
        ScopedFPDFBitmap bitmap(FPDFBitmap_Create(width, height, 0));
        if (!bitmap) {
            return fine::Error(bitmap_creation_failed);
        }
        FPDFBitmap_FillRect(bitmap.get(), 0, 0, width, height, 0xFFFFFFFF);
        FPDF_RenderPageBitmap(bitmap.get(), page.get(), 0, 0, width, height, 0, FPDF_ANNOT | FPDF_REVERSE_BYTE_ORDER);
        std::string rgba(static_cast<const char *>(FPDFBitmap_GetBuffer(bitmap.get())), size_t(width) * height * 4);
        return fine::Ok(std::make_tuple(std::move(rgba), int64_t(width), int64_t(height)));
    });
}

FINE_NIF(get_page_bitmap, ERL_NIF_DIRTY_JOB_CPU_BOUND);

using PageBox = std::tuple<double, double, double, double, int64_t>;

Result<std::vector<PageBox>> get_page_boxes(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc) {
    return each_page<PageBox>(doc, [](FPDF_PAGE page) {
        FS_RECTF box;
        FPDF_GetPageBoundingBox(page, &box);
        return PageBox(box.left, box.bottom, box.right, box.top, FPDFPage_GetRotation(page) * 90);
    });
}

FINE_NIF(get_page_boxes, ERL_NIF_DIRTY_JOB_CPU_BOUND);

using PageSize = std::tuple<double, double>;

Result<std::vector<PageSize>> get_page_sizes(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc) {
    return with_document(doc, [](FPDF_DOCUMENT document) -> Result<std::vector<PageSize>> {
        std::vector<PageSize> sizes;
        for (int index = 0, count = FPDF_GetPageCount(document); index < count; index++) {
            FS_SIZEF size;
            if (!FPDF_GetPageSizeByIndexF(document, index, &size)) {
                return fine::Error(page_load_failed);
            }
            sizes.emplace_back(size.width, size.height);
        }
        return fine::Ok(std::move(sizes));
    });
}

FINE_NIF(get_page_sizes, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<std::vector<int64_t>> get_annotation_counts(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc) {
    return each_page<int64_t>(doc, [](FPDF_PAGE page) { return int64_t(FPDFPage_GetAnnotCount(page)); });
}

FINE_NIF(get_annotation_counts, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<std::string> fpdf_get_meta_text(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc, std::string tag) {
    return with_document(doc, [&](FPDF_DOCUMENT document) -> Result<std::string> {
        std::string utf16(FPDF_GetMetaText(document, tag.c_str(), nullptr, 0), '\0');
        FPDF_GetMetaText(document, tag.c_str(), utf16.data(), utf16.size());
        utf16.resize(utf16.size() >= 2 ? utf16.size() - 2 : 0);
        return fine::Ok(std::move(utf16));
    });
}

FINE_NIF(fpdf_get_meta_text, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<> flatten_page(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc, int64_t index, int64_t usage) {
    return with_document(doc, [&](FPDF_DOCUMENT document) -> Result<> {
        ScopedFPDFPage page(FPDF_LoadPage(document, index));
        if (!page) {
            return fine::Error(page_load_failed);
        }
        if (FPDFPage_Flatten(page.get(), usage) == FLATTEN_FAIL) {
            return fine::Error(flatten_failed);
        }
        return fine::Ok<>();
    });
}

FINE_NIF(flatten_page, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<std::string> fpdf_save_as_copy(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc, int64_t flags) {
    return with_document(doc, [&](FPDF_DOCUMENT document) -> Result<std::string> {
        struct Writer : FPDF_FILEWRITE {
            std::string out;
        } writer;
        writer.version = 1;
        writer.WriteBlock = [](FPDF_FILEWRITE *self, const void *data, unsigned long size) {
            static_cast<Writer *>(self)->out.append(static_cast<const char *>(data), size);
            return 1;
        };
        if (!FPDF_SaveAsCopy(document, &writer, flags)) {
            return fine::Error(save_failed);
        }
        return fine::Ok(std::move(writer.out));
    });
}

FINE_NIF(fpdf_save_as_copy, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<> fpdf_import_pages_by_index(ErlNifEnv *, fine::ResourcePtr<PDFDoc> dest, fine::ResourcePtr<PDFDoc> src,
                                    std::optional<std::vector<int64_t>> page_indices, int64_t index) {
    return with_document(dest, [&](FPDF_DOCUMENT document) -> Result<> {
        if (src->closed) {
            return fine::Error(document_closed);
        }
        if (page_indices && page_indices->empty()) {
            return fine::Error(import_failed);
        }
        std::vector<int> indices;
        if (page_indices) {
            indices.assign(page_indices->begin(), page_indices->end());
        }
        if (!FPDF_ImportPagesByIndex(document, src->document, page_indices ? indices.data() : nullptr,
                                     indices.size(), index)) {
            return fine::Error(import_failed);
        }
        return fine::Ok<>();
    });
}

FINE_NIF(fpdf_import_pages_by_index, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<fine::ResourcePtr<PDFPage>> fpdf_load_page(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc, int64_t index) {
    auto page = fine::make_resource<PDFPage>(doc, nullptr);
    return with_document(doc, [&](FPDF_DOCUMENT document) -> Result<fine::ResourcePtr<PDFPage>> {
        page->page = FPDF_LoadPage(document, index);
        if (!page->page) {
            return fine::Error(page_load_failed);
        }
        doc->open_pages++;
        return fine::Ok(page);
    });
}

FINE_NIF(fpdf_load_page, ERL_NIF_DIRTY_JOB_CPU_BOUND);

fine::Ok<> fpdf_close_page(ErlNifEnv *, fine::ResourcePtr<PDFPage> page) {
    auto lock = lock_pdfium();
    if (page->page) {
        FPDF_ClosePage(page->page);
        page->page = nullptr;
        release_page(*page->doc);
    }
    return fine::Ok<>();
}

FINE_NIF(fpdf_close_page, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<double> fpdf_get_page_width_f(ErlNifEnv *, fine::ResourcePtr<PDFPage> page) {
    return with_page(page, [](FPDF_PAGE handle) -> Result<double> {
        return fine::Ok<double>(FPDF_GetPageWidthF(handle));
    });
}

FINE_NIF(fpdf_get_page_width_f, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<double> fpdf_get_page_height_f(ErlNifEnv *, fine::ResourcePtr<PDFPage> page) {
    return with_page(page, [](FPDF_PAGE handle) -> Result<double> {
        return fine::Ok<double>(FPDF_GetPageHeightF(handle));
    });
}

FINE_NIF(fpdf_get_page_height_f, ERL_NIF_DIRTY_JOB_CPU_BOUND);

using Rect = std::tuple<double, double, double, double>;

Result<Rect> fpdf_get_page_bounding_box(ErlNifEnv *, fine::ResourcePtr<PDFPage> page) {
    return with_page(page, [](FPDF_PAGE handle) -> Result<Rect> {
        FS_RECTF rect;
        if (!FPDF_GetPageBoundingBox(handle, &rect)) {
            return fine::Error(bounding_box_failed);
        }
        return fine::Ok(Rect(rect.left, rect.top, rect.right, rect.bottom));
    });
}

FINE_NIF(fpdf_get_page_bounding_box, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<int64_t> fpdfpage_get_rotation(ErlNifEnv *, fine::ResourcePtr<PDFPage> page) {
    return with_page(page, [](FPDF_PAGE handle) -> Result<int64_t> {
        return fine::Ok<int64_t>(FPDFPage_GetRotation(handle));
    });
}

FINE_NIF(fpdfpage_get_rotation, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<int64_t> fpdfpage_get_annot_count(ErlNifEnv *, fine::ResourcePtr<PDFPage> page) {
    return with_page(page, [](FPDF_PAGE handle) -> Result<int64_t> {
        return fine::Ok<int64_t>(FPDFPage_GetAnnotCount(handle));
    });
}

FINE_NIF(fpdfpage_get_annot_count, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<int64_t> fpdfpage_flatten(ErlNifEnv *, fine::ResourcePtr<PDFPage> page, int64_t flag) {
    return with_page(page, [&](FPDF_PAGE handle) -> Result<int64_t> {
        return fine::Ok<int64_t>(FPDFPage_Flatten(handle, flag));
    });
}

FINE_NIF(fpdfpage_flatten, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<> fpdf_render_page_bitmap(ErlNifEnv *, fine::ResourcePtr<PDFBitmap> bitmap, fine::ResourcePtr<PDFPage> page,
                                 int64_t start_x, int64_t start_y, int64_t size_x, int64_t size_y, int64_t rotate,
                                 int64_t flags) {
    return with_page(page, [&](FPDF_PAGE handle) -> Result<> {
        if (!bitmap->bitmap) {
            return fine::Error(bitmap_destroyed);
        }
        FPDF_RenderPageBitmap(bitmap->bitmap, handle, start_x, start_y, size_x, size_y, rotate, flags);
        return fine::Ok<>();
    });
}

FINE_NIF(fpdf_render_page_bitmap, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<fine::ResourcePtr<PDFBitmap>> fpdfbitmap_create(ErlNifEnv *, int64_t width, int64_t height, int64_t alpha) {
    auto bitmap = fine::make_resource<PDFBitmap>(nullptr);
    auto lock = lock_pdfium();
    bitmap->bitmap = FPDFBitmap_Create(width, height, alpha);
    if (!bitmap->bitmap) {
        return fine::Error(bitmap_creation_failed);
    }
    return fine::Ok(bitmap);
}

FINE_NIF(fpdfbitmap_create, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<> fpdfbitmap_fill_rect(ErlNifEnv *, fine::ResourcePtr<PDFBitmap> bitmap, int64_t left, int64_t top,
                              int64_t width, int64_t height, uint64_t color) {
    return with_bitmap(bitmap, [&](FPDF_BITMAP handle) -> Result<> {
        if (!FPDFBitmap_FillRect(handle, left, top, width, height, color)) {
            return fine::Error(fill_rect_failed);
        }
        return fine::Ok<>();
    });
}

FINE_NIF(fpdfbitmap_fill_rect, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<std::string> fpdfbitmap_get_buffer(ErlNifEnv *, fine::ResourcePtr<PDFBitmap> bitmap) {
    return with_bitmap(bitmap, [](FPDF_BITMAP handle) -> Result<std::string> {
        size_t size = size_t(FPDFBitmap_GetStride(handle)) * FPDFBitmap_GetHeight(handle);
        return fine::Ok(std::string(static_cast<const char *>(FPDFBitmap_GetBuffer(handle)), size));
    });
}

FINE_NIF(fpdfbitmap_get_buffer, ERL_NIF_DIRTY_JOB_CPU_BOUND);

fine::Ok<> fpdfbitmap_destroy(ErlNifEnv *, fine::ResourcePtr<PDFBitmap> bitmap) {
    auto lock = lock_pdfium();
    if (bitmap->bitmap) {
        FPDFBitmap_Destroy(bitmap->bitmap);
        bitmap->bitmap = nullptr;
    }
    return fine::Ok<>();
}

FINE_NIF(fpdfbitmap_destroy, ERL_NIF_DIRTY_JOB_CPU_BOUND);

FINE_INIT("Elixir.PDFium.NIF");
