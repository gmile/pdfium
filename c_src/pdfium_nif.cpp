#include <fine.hpp>
#include <fine/sync.hpp>
#include <fpdfview.h>
#include <mutex>
#include <string>
#include <variant>

static std::unique_ptr<fine::Mutex> pdfium_mutex;

static fine::Atom document_closed("document_closed");
static fine::Atom page_load_failed("page_load_failed");
static fine::Atom bitmap_creation_failed("bitmap_creation_failed");

struct PDFDoc {
    FPDF_DOCUMENT document;

    PDFDoc(FPDF_DOCUMENT doc) : document(doc) {}

    void destructor(ErlNifEnv *env) {
        std::unique_lock lock(*pdfium_mutex);
        if (document) {
            FPDF_CloseDocument(document);
            document = nullptr;
        }
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
        pdfium_mutex.reset();
        FPDF_DestroyLibrary();
    });

using DocResult = std::variant<fine::Ok<fine::ResourcePtr<PDFDoc>>, fine::Error<uint64_t>>;

DocResult load_document(ErlNifEnv *env, std::string filename) {
    std::unique_lock lock(*pdfium_mutex);
    FPDF_DOCUMENT document = FPDF_LoadDocument(filename.c_str(), nullptr);
    unsigned long error = document ? 0 : FPDF_GetLastError();
    lock.unlock();

    if (!document) {
        return fine::Error(static_cast<uint64_t>(error));
    }

    return fine::Ok(fine::make_resource<PDFDoc>(document));
}

FINE_NIF(load_document, 0);

fine::Ok<> close_document(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc) {
    std::unique_lock lock(*pdfium_mutex);
    if (doc->document) {
        FPDF_CloseDocument(doc->document);
        doc->document = nullptr;
    }
    return fine::Ok<>();
}

FINE_NIF(close_document, 0);

using CountResult = std::variant<fine::Ok<int64_t>, fine::Error<fine::Atom>>;

CountResult get_page_count(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc) {
    std::unique_lock lock(*pdfium_mutex);
    if (!doc->document) {
        return fine::Error(document_closed);
    }
    return fine::Ok(static_cast<int64_t>(FPDF_GetPageCount(doc->document)));
}

FINE_NIF(get_page_count, 0);

using BitmapResult = std::variant<fine::Ok<std::string, int64_t, int64_t>, fine::Error<fine::Atom>>;

BitmapResult get_page_bitmap(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc,
                             int64_t page_index, int64_t dpi) {
    std::unique_lock lock(*pdfium_mutex);

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
    FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, 0);

    auto *buffer = static_cast<unsigned char *>(FPDFBitmap_GetBuffer(bitmap));
    int stride = FPDFBitmap_GetStride(bitmap);

    // Convert BGRA to RGBA
    std::string rgba(width * height * 4, '\0');
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            unsigned char *bgra = buffer + y * stride + x * 4;
            char *out = &rgba[(y * width + x) * 4];
            out[0] = bgra[2];
            out[1] = bgra[1];
            out[2] = bgra[0];
            out[3] = bgra[3];
        }
    }

    FPDFBitmap_Destroy(bitmap);
    FPDF_ClosePage(page);

    return fine::Ok(std::move(rgba),
                    static_cast<int64_t>(width),
                    static_cast<int64_t>(height));
}

FINE_NIF(get_page_bitmap, 0);

FINE_INIT("Elixir.PDFium.NIF");
