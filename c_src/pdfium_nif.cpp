#include <fine.hpp>
#include <fine/sync.hpp>
#include <fpdf_flatten.h>
#include <fpdf_save.h>
#include <fpdfview.h>
#include <cstdio>
#include <mutex>
#include <string>
#include <variant>

static std::unique_ptr<fine::Mutex> pdfium_mutex;

static fine::Atom document_closed("document_closed");
static fine::Atom page_load_failed("page_load_failed");
static fine::Atom bitmap_creation_failed("bitmap_creation_failed");
static fine::Atom flattened("flattened");
static fine::Atom nothing_to_do("nothing_to_do");
static fine::Atom flatten_failed("flatten_failed");
static fine::Atom output_open_failed("output_open_failed");
static fine::Atom save_failed("save_failed");

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

FINE_NIF(load_document, ERL_NIF_DIRTY_JOB_CPU_BOUND);

fine::Ok<> close_document(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc) {
    std::unique_lock lock(*pdfium_mutex);
    if (doc->document) {
        FPDF_CloseDocument(doc->document);
        doc->document = nullptr;
    }
    return fine::Ok<>();
}

FINE_NIF(close_document, ERL_NIF_DIRTY_JOB_CPU_BOUND);

using CountResult = std::variant<fine::Ok<int64_t>, fine::Error<fine::Atom>>;

CountResult get_page_count(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc) {
    std::unique_lock lock(*pdfium_mutex);
    if (!doc->document) {
        return fine::Error(document_closed);
    }
    return fine::Ok(static_cast<int64_t>(FPDF_GetPageCount(doc->document)));
}

FINE_NIF(get_page_count, ERL_NIF_DIRTY_JOB_CPU_BOUND);

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

FINE_NIF(get_page_bitmap, ERL_NIF_DIRTY_JOB_CPU_BOUND);

namespace {

struct FileWriter : FPDF_FILEWRITE {
    std::FILE *file;
};

int write_block(FPDF_FILEWRITE *self, const void *data, unsigned long size) {
    auto *writer = static_cast<FileWriter *>(self);
    return std::fwrite(data, 1, size, writer->file) == size ? 1 : 0;
}

} // namespace

using FlattenResult = std::variant<fine::Ok<fine::Atom>, fine::Error<fine::Atom>>;

FlattenResult flatten(ErlNifEnv *env, fine::ResourcePtr<PDFDoc> doc,
                      std::string output_path) {
    std::unique_lock lock(*pdfium_mutex);

    if (!doc->document) {
        return fine::Error(document_closed);
    }

    int page_count = FPDF_GetPageCount(doc->document);
    bool changed = false;

    for (int index = 0; index < page_count; index++) {
        FPDF_PAGE page = FPDF_LoadPage(doc->document, index);
        if (!page) {
            return fine::Error(page_load_failed);
        }

        int result = FPDFPage_Flatten(page, FLAT_NORMALDISPLAY);
        FPDF_ClosePage(page);

        if (result == FLATTEN_FAIL) {
            return fine::Error(flatten_failed);
        }

        if (result == FLATTEN_SUCCESS) {
            changed = true;
        }
    }

    if (!changed) {
        return fine::Ok(nothing_to_do);
    }

    FileWriter writer{};
    writer.version = 1;
    writer.WriteBlock = write_block;
    writer.file = std::fopen(output_path.c_str(), "wb");

    if (!writer.file) {
        return fine::Error(output_open_failed);
    }

    FPDF_BOOL saved = FPDF_SaveAsCopy(doc->document, &writer, 0);
    std::fclose(writer.file);

    if (!saved) {
        return fine::Error(save_failed);
    }

    return fine::Ok(flattened);
}

FINE_NIF(flatten, ERL_NIF_DIRTY_JOB_CPU_BOUND);

FINE_INIT("Elixir.PDFium.NIF");
