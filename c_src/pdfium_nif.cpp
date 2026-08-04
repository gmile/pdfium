#include <fine.hpp>
#include <fine/sync.hpp>
#include <fpdf_edit.h>
#include <fpdf_flatten.h>
#include <fpdf_save.h>
#include <fpdf_text.h>
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
static fine::Atom font_load_failed("font_load_failed");
static fine::Atom font_closed("font_closed");
static fine::Atom placement_mismatch("placement_mismatch");
static fine::Atom page_creation_failed("page_creation_failed");
static fine::Atom text_object_failed("text_object_failed");
static fine::Atom generate_content_failed("generate_content_failed");
static fine::Atom drawn("drawn");

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

namespace {

// PDFium takes UTF-16, Elixir hands over UTF-8, and pulling in a conversion
// library for one call is not worth it.
std::vector<unsigned short> to_utf16(const std::string &utf8) {
    std::vector<unsigned short> out;
    size_t index = 0;

    while (index < utf8.size()) {
        auto lead = static_cast<unsigned char>(utf8[index]);
        uint32_t point;
        size_t length;

        if (lead < 0x80) {
            point = lead;
            length = 1;
        } else if ((lead >> 5) == 0x6) {
            point = lead & 0x1Fu;
            length = 2;
        } else if ((lead >> 4) == 0xE) {
            point = lead & 0x0Fu;
            length = 3;
        } else {
            point = lead & 0x07u;
            length = 4;
        }

        if (index + length > utf8.size()) {
            break;
        }

        for (size_t offset = 1; offset < length; offset++) {
            point = (point << 6) | (static_cast<unsigned char>(utf8[index + offset]) & 0x3Fu);
        }

        index += length;

        if (point > 0xFFFF) {
            point -= 0x10000;
            out.push_back(static_cast<unsigned short>(0xD800 + (point >> 10)));
            out.push_back(static_cast<unsigned short>(0xDC00 + (point & 0x3FF)));
        } else {
            out.push_back(static_cast<unsigned short>(point));
        }
    }

    out.push_back(0);
    return out;
}

} // namespace

// A font belongs to the document it was loaded into, so the resource owns both.
// Callers hold one of these and measure against it as often as they like, which
// is the point: parsing a typeface for every word measured is most of the work.
struct PDFFont {
    FPDF_DOCUMENT document;
    FPDF_FONT font;

    PDFFont(FPDF_DOCUMENT doc, FPDF_FONT f) : document(doc), font(f) {}

    void destructor(ErlNifEnv *env) {
        std::unique_lock lock(*pdfium_mutex);
        if (font) {
            FPDFFont_Close(font);
            font = nullptr;
        }
        if (document) {
            FPDF_CloseDocument(document);
            document = nullptr;
        }
    }
};

FINE_RESOURCE(PDFFont);

using FontResult = std::variant<fine::Ok<fine::ResourcePtr<PDFFont>>, fine::Error<fine::Atom>>;

// Loaded as a CID keyed font. A simple font is single byte encoded, so every
// character outside latin-1 collapses onto one fallback glyph and measures the
// same width as every other, which is wrong and quietly so.
FontResult load_font(ErlNifEnv *env, std::string data) {
    std::unique_lock lock(*pdfium_mutex);

    FPDF_DOCUMENT document = FPDF_CreateNewDocument();
    FPDF_FONT font =
        FPDFText_LoadFont(document, reinterpret_cast<const unsigned char *>(data.data()),
                          static_cast<uint32_t>(data.size()), FPDF_FONT_TRUETYPE,
                          /* cid = */ true);

    if (!font) {
        FPDF_CloseDocument(document);
        return fine::Error(font_load_failed);
    }

    return fine::Ok(fine::make_resource<PDFFont>(document, font));
}

FINE_NIF(load_font, ERL_NIF_DIRTY_JOB_CPU_BOUND);

fine::Ok<> close_font(ErlNifEnv *env, fine::ResourcePtr<PDFFont> font) {
    std::unique_lock lock(*pdfium_mutex);

    if (font->font) {
        FPDFFont_Close(font->font);
        font->font = nullptr;
    }

    if (font->document) {
        FPDF_CloseDocument(font->document);
        font->document = nullptr;
    }

    return fine::Ok<>();
}

FINE_NIF(close_font, ERL_NIF_DIRTY_JOB_CPU_BOUND);

using MeasureResult = std::variant<fine::Ok<std::vector<double>>, fine::Error<fine::Atom>>;

// Advance width of each string, in points, as the font itself measures it. The
// loose box of a glyph is its whole cell rather than the marks inside it, so
// summing those gives the advance rather than the inked extent.
MeasureResult measure_text(ErlNifEnv *env, fine::ResourcePtr<PDFFont> font, double size,
                           std::vector<std::string> texts) {
    std::unique_lock lock(*pdfium_mutex);

    if (!font->font) {
        return fine::Error(font_closed);
    }

    std::vector<double> widths;
    widths.reserve(texts.size());

    for (const auto &text : texts) {
        FPDF_PAGE page = FPDFPage_New(font->document, 0, 1000, 1000);
        FPDF_PAGEOBJECT object =
            FPDFPageObj_CreateTextObj(font->document, font->font, static_cast<float>(size));

        // A character's box is derived from its glyph outline, so a blank glyph
        // ending a run measures as nothing and " " comes back as zero. Appending
        // a sentinel and taking the distance the pen travelled measures
        // advances rather than ink, which is what a width is. The sentinel's own
        // advance never enters the result, so it does not matter whether the
        // font even has that character.
        auto utf16 = to_utf16(text + "A");
        FPDFText_SetText(object, utf16.data());
        FPDFPage_InsertObject(page, object);
        FPDFPage_GenerateContent(page);

        FPDF_TEXTPAGE text_page = FPDFText_LoadPage(page);
        double width = 0.0;

        int count = FPDFText_CountChars(text_page);
        double start_x, start_y, end_x, end_y;

        if (count > 1 && FPDFText_GetCharOrigin(text_page, 0, &start_x, &start_y) &&
            FPDFText_GetCharOrigin(text_page, count - 1, &end_x, &end_y)) {
            width = end_x - start_x;
        }

        FPDFText_ClosePage(text_page);
        FPDF_ClosePage(page);

        // The scratch page has served its purpose. Leaving it would grow the
        // document by a page for every string ever measured.
        FPDFPage_Delete(font->document, 0);

        widths.push_back(width);
    }

    return fine::Ok(widths);
}

FINE_NIF(measure_text, ERL_NIF_DIRTY_JOB_CPU_BOUND);

using DrawResult = std::variant<fine::Ok<fine::Atom>, fine::Error<fine::Atom>>;

// Draws every string on one page of its own document and writes it out, for
// compositing onto the page it belongs over.
//
// The page is built inside the document the font was loaded into, because a page
// object belongs to the document that made it and the font cannot be borrowed
// across one. It is removed again afterwards, so the document a caller holds is
// no larger for having drawn.
//
// Positions are the pen, so y is the baseline rather than the bottom of the
// glyphs, which is what a text placement means everywhere else.
DrawResult draw_text(ErlNifEnv *env, fine::ResourcePtr<PDFFont> font, double size, double width,
                     double height, std::vector<std::string> texts, std::vector<double> xs,
                     std::vector<double> ys, std::string output_path) {
    std::unique_lock lock(*pdfium_mutex);

    if (!font->font) {
        return fine::Error(font_closed);
    }

    if (texts.size() != xs.size() || texts.size() != ys.size()) {
        return fine::Error(placement_mismatch);
    }

    FPDF_PAGE page = FPDFPage_New(font->document, 0, width, height);

    if (!page) {
        return fine::Error(page_creation_failed);
    }

    for (size_t index = 0; index < texts.size(); index++) {
        FPDF_PAGEOBJECT object =
            FPDFPageObj_CreateTextObj(font->document, font->font, static_cast<float>(size));

        if (!object) {
            FPDF_ClosePage(page);
            FPDFPage_Delete(font->document, 0);
            return fine::Error(text_object_failed);
        }

        auto utf16 = to_utf16(texts[index]);
        FPDFText_SetText(object, utf16.data());
        FPDFPageObj_SetFillColor(object, 0, 0, 0, 255);
        FPDFPageObj_Transform(object, 1, 0, 0, 1, xs[index], ys[index]);
        FPDFPage_InsertObject(page, object);
    }

    FPDF_BOOL generated = FPDFPage_GenerateContent(page);
    FPDF_ClosePage(page);

    if (!generated) {
        FPDFPage_Delete(font->document, 0);
        return fine::Error(generate_content_failed);
    }

    FileWriter writer{};
    writer.version = 1;
    writer.WriteBlock = write_block;
    writer.file = std::fopen(output_path.c_str(), "wb");

    if (!writer.file) {
        FPDFPage_Delete(font->document, 0);
        return fine::Error(output_open_failed);
    }

    FPDF_BOOL saved = FPDF_SaveAsCopy(font->document, &writer, 0);
    std::fclose(writer.file);

    FPDFPage_Delete(font->document, 0);

    if (!saved) {
        return fine::Error(save_failed);
    }

    return fine::Ok(drawn);
}

FINE_NIF(draw_text, ERL_NIF_DIRTY_JOB_CPU_BOUND);

FINE_INIT("Elixir.PDFium.NIF");
