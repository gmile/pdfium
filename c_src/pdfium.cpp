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
static fine::Atom bitmap_creation_failed("bitmap_creation_failed");
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

FINE_RESOURCE(PDFDoc);

static auto load_reg = fine::Registration::register_load([](ErlNifEnv *, void **, fine::Term) {
    FPDF_InitLibrary();
    pdfium_mutex = std::make_unique<fine::Mutex>("pdfium", "global");
});

static auto unload_reg = fine::Registration::register_unload([](ErlNifEnv *, void *) noexcept {
    release_pending();
    pdfium_mutex.reset();
    FPDF_DestroyLibrary();
});

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
    if (doc->document) {
        FPDF_CloseDocument(doc->document);
        doc->document = nullptr;
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
        if (!src->document) {
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

FINE_INIT("Elixir.PDFium.NIF");
