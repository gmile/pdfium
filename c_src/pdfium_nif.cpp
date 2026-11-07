#include <cpp/fpdf_scopers.h>
#include <fine.hpp>
#include <fine/sync.hpp>
#include <fpdf_annot.h>
#include <fpdf_doc.h>
#include <fpdf_edit.h>
#include <fpdf_flatten.h>
#include <fpdf_ppo.h>
#include <fpdf_save.h>
#include <fpdf_transformpage.h>
#include <fpdfview.h>
#include <map>
#include <mutex>
#include <string>
#include <tuple>
#include <variant>
#include <vector>

template <typename... T>
using Result = std::variant<fine::Ok<T...>, fine::Error<fine::Atom>>;

static fine::Atom load_errors[] = {fine::Atom("unknown"),  fine::Atom("unknown"), fine::Atom("file"),
                                   fine::Atom("format"),   fine::Atom("password"), fine::Atom("security"),
                                   fine::Atom("page")};
static fine::Atom document_closed("document_closed");
static fine::Atom page_load_failed("page_load_failed");
static fine::Atom bitmap_creation_failed("bitmap_creation_failed");
static fine::Atom flatten_failed("flatten_failed");
static fine::Atom save_failed("save_failed");
static fine::Atom import_failed("import_failed");
static fine::Atom xobject_failed("xobject_failed");

static std::unique_ptr<fine::Mutex> pdfium_mutex;
static std::mutex pending_close_mutex;
static std::vector<std::pair<FPDF_DOCUMENT, std::string>> pending_close;

static void close_pending_documents() {
    std::vector<std::pair<FPDF_DOCUMENT, std::string>> documents;
    {
        std::lock_guard guard(pending_close_mutex);
        documents.swap(pending_close);
    }
    for (auto &[document, _buffer] : documents) {
        FPDF_CloseDocument(document);
    }
}

static std::unique_lock<fine::Mutex> lock_pdfium() {
    std::unique_lock lock(*pdfium_mutex);
    close_pending_documents();
    return lock;
}

struct PDFDoc {
    FPDF_DOCUMENT document;
    std::string buffer;

    PDFDoc(FPDF_DOCUMENT doc, std::string data = {}) : document(doc), buffer(std::move(data)) {}

    void destructor(ErlNifEnv *) {
        if (document) {
            std::lock_guard guard(pending_close_mutex);
            pending_close.emplace_back(document, std::move(buffer));
        }
    }
};

FINE_RESOURCE(PDFDoc);

static auto load_reg = fine::Registration::register_load([](ErlNifEnv *, void **, fine::Term) {
    FPDF_InitLibrary();
    pdfium_mutex = std::make_unique<fine::Mutex>("pdfium", "global");
});

static auto unload_reg = fine::Registration::register_unload([](ErlNifEnv *, void *) noexcept {
    close_pending_documents();
    pdfium_mutex.reset();
    FPDF_DestroyLibrary();
});

template <typename F>
static auto with_document(const fine::ResourcePtr<PDFDoc> &doc, F f) -> decltype(f(doc->document)) {
    auto lock = lock_pdfium();
    if (!doc->document) {
        return fine::Error(document_closed);
    }
    return f(doc->document);
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

Result<fine::ResourcePtr<PDFDoc>> load_memory_document(ErlNifEnv *, std::string data, std::string password) {
    auto doc = fine::make_resource<PDFDoc>(nullptr, std::move(data));
    auto lock = lock_pdfium();
    doc->document = FPDF_LoadMemDocument64(doc->buffer.data(), doc->buffer.size(),
                                           password.empty() ? nullptr : password.c_str());
    if (!doc->document) {
        unsigned long error = FPDF_GetLastError();
        return fine::Error(load_errors[error < std::size(load_errors) ? error : 0]);
    }
    return fine::Ok(doc);
}

FINE_NIF(load_memory_document, ERL_NIF_DIRTY_JOB_CPU_BOUND);

fine::Ok<> close_document(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc) {
    auto lock = lock_pdfium();
    if (doc->document) {
        FPDF_CloseDocument(doc->document);
        doc->document = nullptr;
    }
    return fine::Ok<>();
}

FINE_NIF(close_document, ERL_NIF_DIRTY_JOB_CPU_BOUND);

fine::Ok<fine::ResourcePtr<PDFDoc>> create_document(ErlNifEnv *) {
    auto lock = lock_pdfium();
    return fine::Ok(fine::make_resource<PDFDoc>(FPDF_CreateNewDocument()));
}

FINE_NIF(create_document, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<int64_t> get_page_count(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc) {
    return with_document(doc, [](FPDF_DOCUMENT document) -> Result<int64_t> {
        return fine::Ok<int64_t>(FPDF_GetPageCount(document));
    });
}

FINE_NIF(get_page_count, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<int64_t> get_security_handler_revision(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc) {
    return with_document(doc, [](FPDF_DOCUMENT document) -> Result<int64_t> {
        return fine::Ok<int64_t>(FPDF_GetSecurityHandlerRevision(document));
    });
}

FINE_NIF(get_security_handler_revision, ERL_NIF_DIRTY_JOB_CPU_BOUND);

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

Result<std::string> get_meta_text(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc, std::string key) {
    return with_document(doc, [&](FPDF_DOCUMENT document) -> Result<std::string> {
        std::string utf16(FPDF_GetMetaText(document, key.c_str(), nullptr, 0), '\0');
        FPDF_GetMetaText(document, key.c_str(), utf16.data(), utf16.size());
        utf16.resize(utf16.size() >= 2 ? utf16.size() - 2 : 0);
        return fine::Ok(std::move(utf16));
    });
}

FINE_NIF(get_meta_text, ERL_NIF_DIRTY_JOB_CPU_BOUND);

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

Result<std::string> save_to_binary(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc, bool remove_security) {
    return with_document(doc, [&](FPDF_DOCUMENT document) -> Result<std::string> {
        struct Writer : FPDF_FILEWRITE {
            std::string out;
        } writer;
        writer.version = 1;
        writer.WriteBlock = [](FPDF_FILEWRITE *self, const void *data, unsigned long size) {
            static_cast<Writer *>(self)->out.append(static_cast<const char *>(data), size);
            return 1;
        };
        if (!FPDF_SaveAsCopy(document, &writer, remove_security ? FPDF_REMOVE_SECURITY : 0)) {
            return fine::Error(save_failed);
        }
        return fine::Ok(std::move(writer.out));
    });
}

FINE_NIF(save_to_binary, ERL_NIF_DIRTY_JOB_CPU_BOUND);

// An empty list of pages is pdfium's way of asking for all of them.
Result<> import_pages(ErlNifEnv *, fine::ResourcePtr<PDFDoc> dest, fine::ResourcePtr<PDFDoc> src,
                      std::vector<int64_t> pages, int64_t at) {
    return with_document(dest, [&](FPDF_DOCUMENT document) -> Result<> {
        if (!src->document) {
            return fine::Error(document_closed);
        }
        std::vector<int> indices(pages.begin(), pages.end());
        if (!FPDF_ImportPagesByIndex(document, src->document, indices.empty() ? nullptr : indices.data(),
                                     indices.size(), at)) {
            return fine::Error(import_failed);
        }
        return fine::Ok<>();
    });
}

FINE_NIF(import_pages, ERL_NIF_DIRTY_JOB_CPU_BOUND);

// The matrix taking the page as a reader shows it, origin at its bottom left,
// to the coordinates its content is written in.
static FS_MATRIX display_to_page(FPDF_PAGE page) {
    FS_RECTF box;
    FPDF_GetPageBoundingBox(page, &box);
    switch (FPDFPage_GetRotation(page)) {
    case 1:
        return {0, 1, -1, 0, box.right, box.bottom};
    case 2:
        return {-1, 0, 0, -1, box.right, box.top};
    case 3:
        return {0, -1, 1, 0, box.left, box.top};
    default:
        return {1, 0, 0, 1, box.left, box.bottom};
    }
}

struct XObjectCloser {
    void operator()(FPDF_XOBJECT xobject) { FPDF_CloseXObject(xobject); }
};

using Matrix = std::tuple<double, double, double, double, double, double>;
using Placement = std::tuple<fine::ResourcePtr<PDFDoc>, int64_t, int64_t, Matrix>;

// Pages are written only once every placement is in, so a placement that
// fails leaves the document as it was.
Result<> stamp(ErlNifEnv *, fine::ResourcePtr<PDFDoc> doc, std::vector<Placement> placements) {
    return with_document(doc, [&](FPDF_DOCUMENT document) -> Result<> {
        std::map<std::pair<FPDF_DOCUMENT, int>, std::unique_ptr<fpdf_xobject_t__, XObjectCloser>> templates;
        std::map<int, ScopedFPDFPage> pages;
        for (const auto &[overlay, overlay_page, index, matrix] : placements) {
            if (!overlay->document) {
                return fine::Error(document_closed);
            }
            auto &page = pages[index];
            if (!page) {
                page.reset(FPDF_LoadPage(document, index));
            }
            if (!page) {
                return fine::Error(page_load_failed);
            }
            auto &xobject = templates[{overlay->document, overlay_page}];
            if (!xobject) {
                xobject.reset(FPDF_NewXObjectFromPage(document, overlay->document, overlay_page));
            }
            if (!xobject) {
                return fine::Error(xobject_failed);
            }
            FPDF_PAGEOBJECT form = FPDF_NewFormObjectFromXObject(xobject.get());
            const auto &[a, b, c, d, e, f] = matrix;
            FS_MATRIX to_page = display_to_page(page.get());
            FPDFPageObj_Transform(form, a, b, c, d, e, f);
            FPDFPageObj_Transform(form, to_page.a, to_page.b, to_page.c, to_page.d, to_page.e, to_page.f);
            FPDFPage_InsertObject(page.get(), form);
        }
        for (auto &[_index, page] : pages) {
            FPDFPage_GenerateContent(page.get());
        }
        return fine::Ok<>();
    });
}

FINE_NIF(stamp, ERL_NIF_DIRTY_JOB_CPU_BOUND);

FINE_INIT("Elixir.PDFium.NIF");
