#pragma once

#include <fine.hpp>
#include <fine/sync.hpp>
#include <fpdfview.h>
#include <functional>
#include <mutex>
#include <string>
#include <variant>

template <typename... T>
using Result = std::variant<fine::Ok<T...>, fine::Error<fine::Atom>>;

inline fine::Atom document_closed("document_closed");
inline fine::Atom page_load_failed("page_load_failed");

// A document closed while pages of it are still open stays open in pdfium,
// answering only as closed, until the last of them is closed too.
struct PDFDoc {
    FPDF_DOCUMENT document;
    std::string buffer;
    bool closed = false;
    int64_t open_pages = 0;

    PDFDoc(FPDF_DOCUMENT doc, std::string data = {}) : document(doc), buffer(std::move(data)) {}

    void destructor(ErlNifEnv *);
};

struct PDFPage {
    fine::ResourcePtr<PDFDoc> doc;
    FPDF_PAGE page;

    PDFPage(fine::ResourcePtr<PDFDoc> doc, FPDF_PAGE page) : doc(std::move(doc)), page(page) {}

    void destructor(ErlNifEnv *);
};

struct PDFBitmap {
    FPDF_BITMAP bitmap;

    PDFBitmap(FPDF_BITMAP bitmap) : bitmap(bitmap) {}

    void destructor(ErlNifEnv *);
};

std::unique_lock<fine::Mutex> lock_pdfium();
void release_later(std::function<void()> release);

template <typename F>
auto with_document(const fine::ResourcePtr<PDFDoc> &doc, F f) -> decltype(f(doc->document)) {
    auto lock = lock_pdfium();
    if (doc->closed) {
        return fine::Error(document_closed);
    }
    return f(doc->document);
}
