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
#include <algorithm>
#include <map>
#include <mutex>
#include <tuple>
#include <optional>
#include <string>
#include <variant>
#include <vector>

static std::unique_ptr<fine::Mutex> pdfium_mutex;

template <typename... T>
using Result = std::variant<fine::Ok<T...>, fine::Error<fine::Atom>>;

static fine::Atom error_unknown("unknown");
static fine::Atom error_file("file");
static fine::Atom error_format("format");
static fine::Atom error_password("password");
static fine::Atom error_security("security");
static fine::Atom error_page("page");
static fine::Atom error_xfa_load("xfa_load");
static fine::Atom error_xfa_layout("xfa_layout");
static fine::Atom document_creation_failed("document_creation_failed");
static fine::Atom import_failed("import_failed");
static fine::Atom imported_atom("imported");
static fine::Atom generate_content_failed("generate_content_failed");
static fine::Atom xobject_failed("xobject_failed");
static fine::Atom form_object_failed("form_object_failed");
static fine::Atom stamped("stamped");
static fine::Atom document_closed("document_closed");
static fine::Atom page_load_failed("page_load_failed");
static fine::Atom bitmap_creation_failed("bitmap_creation_failed");
static fine::Atom flattened("flattened");
static fine::Atom nothing_to_do("nothing_to_do");
static fine::Atom flatten_failed("flatten_failed");
static fine::Atom save_failed("save_failed");

struct PendingClose {
    FPDF_DOCUMENT document;
    std::string buffer;
};

static std::mutex pending_close_mutex;
static std::vector<PendingClose> pending_close;

static void close_pending_documents() {
    std::vector<PendingClose> documents;
    {
        std::lock_guard guard(pending_close_mutex);
        documents.swap(pending_close);
    }
    for (auto &pending : documents) {
        FPDF_CloseDocument(pending.document);
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

    PDFDoc(FPDF_DOCUMENT doc) : document(doc) {}
    PDFDoc(FPDF_DOCUMENT doc, std::string data) : document(doc), buffer(std::move(data)) {}

    void destructor(ErlNifEnv *env) {
        if (!document) {
            return;
        }
        std::lock_guard guard(pending_close_mutex);
        pending_close.push_back({document, std::move(buffer)});
        document = nullptr;
    }
};

FINE_RESOURCE(PDFDoc);

static auto load_reg = fine::Registration::register_load(
    [](ErlNifEnv *, void **, fine::Term) {
        FPDF_InitLibrary();
        pdfium_mutex = std::make_unique<fine::Mutex>("pdfium", "global");
    });

static auto unload_reg = fine::Registration::register_unload(
    [](ErlNifEnv *, void *) noexcept {
        close_pending_documents();
        pdfium_mutex.reset();
        FPDF_DestroyLibrary();
    });

namespace {

fine::Atom last_error_name(unsigned long error) {
    switch (error) {
    case FPDF_ERR_FILE:
        return error_file;
    case FPDF_ERR_FORMAT:
        return error_format;
    case FPDF_ERR_PASSWORD:
        return error_password;
    case FPDF_ERR_SECURITY:
        return error_security;
    case FPDF_ERR_PAGE:
        return error_page;
#ifdef PDF_ENABLE_XFA
    case FPDF_ERR_XFALOAD:
        return error_xfa_load;
    case FPDF_ERR_XFALAYOUT:
        return error_xfa_layout;
#endif
    default:
        return error_unknown;
    }
}

} // namespace

Result<fine::ResourcePtr<PDFDoc>> load_memory_document(ErlNifEnv *env, std::string data) {
    auto doc = fine::make_resource<PDFDoc>(nullptr, std::move(data));

    auto lock = lock_pdfium();
    FPDF_DOCUMENT document =
        FPDF_LoadMemDocument64(doc->buffer.data(), doc->buffer.size(), nullptr);
    unsigned long error = document ? 0 : FPDF_GetLastError();
    lock.unlock();

    if (!document) {
        return fine::Error(last_error_name(error));
    }

    doc->document = document;

    return fine::Ok(doc);
}

FINE_NIF(load_memory_document, ERL_NIF_DIRTY_JOB_CPU_BOUND);

fine::Ok<> close_document(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc) {
    auto lock = lock_pdfium();
    if (doc->document) {
        FPDF_CloseDocument(doc->document);
        doc->document = nullptr;
    }
    return fine::Ok<>();
}

FINE_NIF(close_document, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<int64_t> get_page_count(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc) {
    auto lock = lock_pdfium();
    if (!doc->document) {
        return fine::Error(document_closed);
    }
    return fine::Ok(static_cast<int64_t>(FPDF_GetPageCount(doc->document)));
}

FINE_NIF(get_page_count, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<int64_t> get_security_handler_revision(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc) {
    auto lock = lock_pdfium();
    if (!doc->document) {
        return fine::Error(document_closed);
    }
    return fine::Ok(static_cast<int64_t>(FPDF_GetSecurityHandlerRevision(doc->document)));
}

FINE_NIF(get_security_handler_revision, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<std::string, int64_t, int64_t> get_page_bitmap(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc,
                             int64_t page_index, int64_t dpi) {
    auto lock = lock_pdfium();

    if (!doc->document) {
        return fine::Error(document_closed);
    }

    FPDF_PAGE page = FPDF_LoadPage(doc->document, static_cast<int>(page_index));
    if (!page) {
        return fine::Error(page_load_failed);
    }

    double page_width = FPDF_GetPageWidth(page);
    double page_height = FPDF_GetPageHeight(page);

    int width = static_cast<int>((page_width * dpi) / 72.0);
    int height = static_cast<int>((page_height * dpi) / 72.0);

    FPDF_BITMAP bitmap = FPDFBitmap_Create(width, height, 0);
    if (!bitmap) {
        FPDF_ClosePage(page);
        return fine::Error(bitmap_creation_failed);
    }

    FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF);
    FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, FPDF_ANNOT | FPDF_REVERSE_BYTE_ORDER);

    auto *buffer = static_cast<const char *>(FPDFBitmap_GetBuffer(bitmap));
    size_t row = static_cast<size_t>(width) * 4;
    std::string rgba;
    rgba.reserve(row * height);
    for (int y = 0; y < height; y++) {
        rgba.append(buffer + y * FPDFBitmap_GetStride(bitmap), row);
    }

    FPDFBitmap_Destroy(bitmap);
    FPDF_ClosePage(page);

    return fine::Ok(std::move(rgba),
                    static_cast<int64_t>(width),
                    static_cast<int64_t>(height));
}

FINE_NIF(get_page_bitmap, ERL_NIF_DIRTY_JOB_CPU_BOUND);

using PageBox = std::tuple<double, double, double, double, int64_t>;

Result<std::vector<PageBox>> get_page_boxes(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc) {
    auto lock = lock_pdfium();

    if (!doc->document) {
        return fine::Error(document_closed);
    }

    int page_count = FPDF_GetPageCount(doc->document);

    std::vector<PageBox> boxes;
    boxes.reserve(static_cast<size_t>(page_count));

    for (int index = 0; index < page_count; index++) {
        FPDF_PAGE page = FPDF_LoadPage(doc->document, index);
        if (!page) {
            return fine::Error(page_load_failed);
        }

        int rotation = FPDFPage_GetRotation(page);

        float left, bottom, right, top;

        if (!FPDFPage_GetMediaBox(page, &left, &bottom, &right, &top)) {
            float width = FPDF_GetPageWidthF(page);
            float height = FPDF_GetPageHeightF(page);

            if (rotation % 2 != 0) {
                std::swap(width, height);
            }

            left = 0.0f;
            bottom = 0.0f;
            right = width;
            top = height;
        }

        FPDF_ClosePage(page);

        boxes.emplace_back(std::min(left, right), std::min(bottom, top), std::max(left, right),
                           std::max(bottom, top), static_cast<int64_t>(rotation) * 90);
    }

    return fine::Ok(std::move(boxes));
}

FINE_NIF(get_page_boxes, ERL_NIF_DIRTY_JOB_CPU_BOUND);

using PageSize = std::tuple<double, double>;

// Every document in one call, because placing anything wants the sizes of the
// page it goes on and of the overlay going there, and each call over this
// boundary waits its turn on the same lock.
Result<std::vector<std::vector<PageSize>>> get_page_sizes(ErlNifEnv *env, std::vector<fine::ResourcePtr<PDFDoc>> docs) {
    auto lock = lock_pdfium();

    std::vector<std::vector<PageSize>> documents;
    documents.reserve(docs.size());

    for (const auto &doc : docs) {
        if (!doc->document) {
            return fine::Error(document_closed);
        }

        int page_count = FPDF_GetPageCount(doc->document);

        std::vector<PageSize> sizes;
        sizes.reserve(static_cast<size_t>(page_count));

        for (int index = 0; index < page_count; index++) {
            FS_SIZEF size;

            if (!FPDF_GetPageSizeByIndexF(doc->document, index, &size)) {
                return fine::Error(page_load_failed);
            }

            sizes.emplace_back(size.width, size.height);
        }

        documents.push_back(std::move(sizes));
    }

    return fine::Ok(std::move(documents));
}

FINE_NIF(get_page_sizes, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<std::vector<int64_t>> get_annotation_counts(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc) {
    auto lock = lock_pdfium();

    if (!doc->document) {
        return fine::Error(document_closed);
    }

    int page_count = FPDF_GetPageCount(doc->document);

    std::vector<int64_t> counts;
    counts.reserve(static_cast<size_t>(page_count));

    for (int index = 0; index < page_count; index++) {
        FPDF_PAGE page = FPDF_LoadPage(doc->document, index);

        if (!page) {
            return fine::Error(page_load_failed);
        }

        counts.push_back(static_cast<int64_t>(FPDFPage_GetAnnotCount(page)));
        FPDF_ClosePage(page);
    }

    return fine::Ok(std::move(counts));
}

FINE_NIF(get_annotation_counts, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<std::string> get_meta_text(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc, std::string key) {
    auto lock = lock_pdfium();

    if (!doc->document) {
        return fine::Error(document_closed);
    }

    unsigned long length = FPDF_GetMetaText(doc->document, key.c_str(), nullptr, 0);
    std::string utf16(length, '\0');
    FPDF_GetMetaText(doc->document, key.c_str(), utf16.data(), length);
    utf16.resize(length >= 2 ? length - 2 : 0);

    return fine::Ok(std::move(utf16));
}

FINE_NIF(get_meta_text, ERL_NIF_DIRTY_JOB_CPU_BOUND);

namespace {

struct BufferWriter : FPDF_FILEWRITE {
    std::string *buffer;
};

int append_block(FPDF_FILEWRITE *self, const void *data, unsigned long size) {
    auto *writer = static_cast<BufferWriter *>(self);
    writer->buffer->append(static_cast<const char *>(data), size);
    return 1;
}

FPDF_DWORD save_flags(bool remove_security) { return remove_security ? FPDF_REMOVE_SECURITY : 0; }

} // namespace

// `usage` is one of pdfium's FLAT_ values: 0 to flatten for display, 1 for
// print.
Result<fine::Atom> flatten_page(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc, int64_t page_index,
                           int64_t usage) {
    auto lock = lock_pdfium();

    if (!doc->document) {
        return fine::Error(document_closed);
    }

    FPDF_PAGE page = FPDF_LoadPage(doc->document, static_cast<int>(page_index));

    if (!page) {
        return fine::Error(page_load_failed);
    }

    int result = FPDFPage_Flatten(page, static_cast<int>(usage));
    FPDF_ClosePage(page);

    switch (result) {
    case FLATTEN_SUCCESS:
        return fine::Ok(flattened);
    case FLATTEN_NOTHINGTODO:
        return fine::Ok(nothing_to_do);
    default:
        return fine::Error(flatten_failed);
    }
}

FINE_NIF(flatten_page, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<fine::ResourcePtr<PDFDoc>> create_document(ErlNifEnv *env) {
    auto lock = lock_pdfium();

    FPDF_DOCUMENT document = FPDF_CreateNewDocument();

    if (!document) {
        return fine::Error(document_creation_failed);
    }

    return fine::Ok(fine::make_resource<PDFDoc>(document));
}

FINE_NIF(create_document, ERL_NIF_DIRTY_JOB_CPU_BOUND);

Result<std::string> save_to_binary(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc,
                                  bool remove_security) {
    auto lock = lock_pdfium();

    if (!doc->document) {
        return fine::Error(document_closed);
    }

    std::string out;
    BufferWriter writer{};
    writer.version = 1;
    writer.WriteBlock = append_block;
    writer.buffer = &out;

    if (!FPDF_SaveAsCopy(doc->document, &writer, save_flags(remove_security))) {
        return fine::Error(save_failed);
    }

    return fine::Ok(std::move(out));
}

FINE_NIF(save_to_binary, ERL_NIF_DIRTY_JOB_CPU_BOUND);

// An empty list of pages is pdfium's way of asking for all of them.
Result<fine::Atom> import_pages(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> dest,
                         fine::ResourcePtr<PDFDoc> src, std::vector<int64_t> page_indices,
                         int64_t at) {
    auto lock = lock_pdfium();

    if (!dest->document || !src->document) {
        return fine::Error(document_closed);
    }

    std::vector<int> indices;
    indices.reserve(page_indices.size());

    for (int64_t index : page_indices) {
        indices.push_back(static_cast<int>(index));
    }

    FPDF_BOOL imported =
        FPDF_ImportPagesByIndex(dest->document, src->document,
                                indices.empty() ? nullptr : indices.data(),
                                static_cast<unsigned long>(indices.size()), static_cast<int>(at));

    if (!imported) {
        return fine::Error(import_failed);
    }

    return fine::Ok(imported_atom);
}

FINE_NIF(import_pages, ERL_NIF_DIRTY_JOB_CPU_BOUND);

namespace {

struct Box {
    double left, bottom, right, top;
};

struct Matrix {
    double a, b, c, d, e, f;
};

bool is_empty(const Box &box) { return box.right <= box.left || box.top <= box.bottom; }

Box sorted(float left, float bottom, float right, float top) {
    return {std::min(left, right), std::min(bottom, top), std::max(left, right),
            std::max(bottom, top)};
}

Box effective_box(FPDF_PAGE page) {
    float left, bottom, right, top;

    Box media = {0.0, 0.0, 612.0, 792.0};

    if (FPDFPage_GetMediaBox(page, &left, &bottom, &right, &top)) {
        Box box = sorted(left, bottom, right, top);

        if (!is_empty(box)) {
            media = box;
        }
    }

    if (FPDFPage_GetCropBox(page, &left, &bottom, &right, &top)) {
        Box crop = sorted(left, bottom, right, top);

        if (!is_empty(crop)) {
            return {std::max(media.left, crop.left), std::max(media.bottom, crop.bottom),
                    std::min(media.right, crop.right), std::min(media.top, crop.top)};
        }
    }

    return media;
}

Matrix display_to_page(const Box &box, int rotation) {
    switch (rotation) {
    case 1:
        return {0.0, 1.0, -1.0, 0.0, box.right, box.bottom};
    case 2:
        return {-1.0, 0.0, 0.0, -1.0, box.right, box.top};
    case 3:
        return {0.0, -1.0, 1.0, 0.0, box.left, box.top};
    default:
        return {1.0, 0.0, 0.0, 1.0, box.left, box.bottom};
    }
}

} // namespace

// Each placement says where its overlay goes on the page as displayed: origin
// at the bottom left of the page the way a reader shows it, whatever the page's
// own box and rotation happen to be. Turning that into the coordinates the page
// is written in is this side's job, because it is pdfium's own layout that
// decides it.
using Matrix6 = std::tuple<double, double, double, double, double, double>;

using Placement = std::tuple<fine::ResourcePtr<PDFDoc>, int64_t, int64_t, Matrix6>;

std::optional<fine::Atom> apply_stamps(fine::ResourcePtr<PDFDoc> doc,
                                       const std::vector<Placement> &placements) {
    if (!doc->document) {
        return document_closed;
    }

    for (const auto &placement : placements) {
        if (!std::get<0>(placement)->document) {
            return document_closed;
        }
    }

    std::map<int, std::vector<size_t>> by_page;

    for (size_t index = 0; index < placements.size(); index++) {
        by_page[static_cast<int>(std::get<2>(placements[index]))].push_back(index);
    }

    std::map<std::pair<FPDF_DOCUMENT, int>, FPDF_XOBJECT> templates;
    std::optional<fine::Atom> failure;

    for (const auto &entry : by_page) {
        FPDF_PAGE page = FPDF_LoadPage(doc->document, entry.first);

        if (!page) {
            failure = page_load_failed;
            break;
        }

        Matrix inverse = display_to_page(effective_box(page), FPDFPage_GetRotation(page));

        for (size_t index : entry.second) {
            FPDF_DOCUMENT overlay = std::get<0>(placements[index])->document;
            int overlay_page = static_cast<int>(std::get<1>(placements[index]));
            auto key = std::make_pair(overlay, overlay_page);

            if (templates.find(key) == templates.end()) {
                FPDF_XOBJECT xobject =
                    FPDF_NewXObjectFromPage(doc->document, overlay, overlay_page);

                if (!xobject) {
                    failure = xobject_failed;
                    break;
                }

                templates[key] = xobject;
            }

            FPDF_PAGEOBJECT form = FPDF_NewFormObjectFromXObject(templates[key]);

            if (!form) {
                failure = form_object_failed;
                break;
            }

            const auto &[a, b, c, d, e, f] = std::get<3>(placements[index]);

            FPDFPageObj_Transform(form, a * inverse.a + b * inverse.c, a * inverse.b + b * inverse.d,
                                  c * inverse.a + d * inverse.c, c * inverse.b + d * inverse.d,
                                  e * inverse.a + f * inverse.c + inverse.e,
                                  e * inverse.b + f * inverse.d + inverse.f);

            FPDFPage_InsertObject(page, form);
        }

        if (!failure && !FPDFPage_GenerateContent(page)) {
            failure = generate_content_failed;
        }

        FPDF_ClosePage(page);

        if (failure) {
            break;
        }
    }

    for (const auto &entry : templates) {
        FPDF_CloseXObject(entry.second);
    }

    return failure;
}

Result<fine::Atom> stamp_in_place(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc,
                           std::vector<Placement> placements) {
    auto lock = lock_pdfium();

    if (auto failure = apply_stamps(doc, placements)) {
        return fine::Error(*failure);
    }

    return fine::Ok(stamped);
}

FINE_NIF(stamp_in_place, ERL_NIF_DIRTY_JOB_CPU_BOUND);

FINE_INIT("Elixir.PDFium.NIF");
