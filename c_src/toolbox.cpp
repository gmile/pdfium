#include "pdfium_nif.hpp"

#include <cpp/fpdf_scopers.h>
#include <fpdf_edit.h>
#include <fpdf_ppo.h>
#include <map>
#include <tuple>
#include <vector>

static fine::Atom xobject_failed("xobject_failed");

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
