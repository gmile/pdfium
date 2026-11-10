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

struct PDFDoc {
    FPDF_DOCUMENT document;
    std::string buffer;

    PDFDoc(FPDF_DOCUMENT doc, std::string data = {}) : document(doc), buffer(std::move(data)) {}

    void destructor(ErlNifEnv *);
};

std::unique_lock<fine::Mutex> lock_pdfium();
void release_later(std::function<void()> release);

template <typename F>
auto with_document(const fine::ResourcePtr<PDFDoc> &doc, F f) -> decltype(f(doc->document)) {
    auto lock = lock_pdfium();
    if (!doc->document) {
        return fine::Error(document_closed);
    }
    return f(doc->document);
}
