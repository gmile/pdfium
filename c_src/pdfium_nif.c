#include <erl_nif.h>
#include <string.h>
#include "fpdfview.h"

static ErlNifResourceType* PDF_DOCUMENT_RESOURCE;

typedef struct {
    FPDF_DOCUMENT document;
} PDFDocResource;

static void pdf_document_destructor(ErlNifEnv* env, void* obj) {
    PDFDocResource* doc_res = (PDFDocResource*)obj;
    if (doc_res->document) {
        FPDF_CloseDocument(doc_res->document);
        doc_res->document = NULL;
    }
}

static int load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info) {
    FPDF_InitLibrary();
    
    PDF_DOCUMENT_RESOURCE = enif_open_resource_type(
        env,
        NULL,
        "pdf_document_resource",
        pdf_document_destructor,
        ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER,
        NULL
    );

    if (!PDF_DOCUMENT_RESOURCE) {
        return -1;
    }

    return 0;
}

static void unload(ErlNifEnv* env, void* priv_data) {
    FPDF_DestroyLibrary();
}

static ERL_NIF_TERM load_pdf_document(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) return enif_make_badarg(env);

    ErlNifBinary bin;
    if (!enif_inspect_iolist_as_binary(env, argv[0], &bin)) {
        return enif_make_badarg(env);
    }

    char* filename = (char*)malloc(bin.size + 1);
    if (!filename) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
            enif_make_atom(env, "out_of_memory"));
    }

    memcpy(filename, bin.data, bin.size);
    filename[bin.size] = '\0';

    FPDF_DOCUMENT document = FPDF_LoadDocument(filename, NULL);
    free(filename);

    if (!document) {
        unsigned long error = FPDF_GetLastError();
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
            enif_make_ulong(env, error));
    }

    PDFDocResource* doc_res = enif_alloc_resource(PDF_DOCUMENT_RESOURCE, sizeof(PDFDocResource));
    if (!doc_res) {
        FPDF_CloseDocument(document);
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
            enif_make_atom(env, "out_of_memory"));
    }

    doc_res->document = document;
    ERL_NIF_TERM resource_term = enif_make_resource(env, doc_res);
    enif_release_resource(doc_res);

    return enif_make_tuple2(env, enif_make_atom(env, "ok"), resource_term);
}

static ERL_NIF_TERM get_page_count(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 1) return enif_make_badarg(env);

    PDFDocResource* doc_res;
    if (!enif_get_resource(env, argv[0], PDF_DOCUMENT_RESOURCE, (void**)&doc_res)) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
            enif_make_atom(env, "invalid_resource"));
    }

    if (!doc_res->document) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
            enif_make_atom(env, "document_closed"));
    }

    int page_count = FPDF_GetPageCount(doc_res->document);
    return enif_make_tuple2(env, enif_make_atom(env, "ok"),
        enif_make_int(env, page_count));
}

static ERL_NIF_TERM get_page_bitmap(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 3) return enif_make_badarg(env);

    PDFDocResource* doc_res;
    int page_index;
    int dpi;

    if (!enif_get_resource(env, argv[0], PDF_DOCUMENT_RESOURCE, (void**)&doc_res) ||
        !enif_get_int(env, argv[1], &page_index) ||
        !enif_get_int(env, argv[2], &dpi)) {
        return enif_make_badarg(env);
    }

    if (!doc_res->document) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
            enif_make_atom(env, "document_closed"));
    }

    FPDF_PAGE page = FPDF_LoadPage(doc_res->document, page_index);
    if (!page) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
            enif_make_atom(env, "page_load_failed"));
    }

    double page_width = FPDF_GetPageWidth(page);
    double page_height = FPDF_GetPageHeight(page);

    int width = (int)((page_width * dpi) / 72.0);
    int height = (int)((page_height * dpi) / 72.0);

    FPDF_BITMAP bitmap = FPDFBitmap_Create(width, height, 0);
    if (!bitmap) {
        FPDF_ClosePage(page);
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
            enif_make_atom(env, "bitmap_creation_failed"));
    }

    FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF);
    FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, 0);

    unsigned char* buffer = FPDFBitmap_GetBuffer(bitmap);
    int stride = FPDFBitmap_GetStride(bitmap);

    ErlNifBinary result_binary;
    if (!enif_alloc_binary(width * height * 4, &result_binary)) {
        FPDFBitmap_Destroy(bitmap);
        FPDF_ClosePage(page);
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
            enif_make_atom(env, "memory_allocation_failed"));
    }

    // Convert BGRA to RGBA
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            unsigned char* bgra = buffer + y * stride + x * 4;
            unsigned char* rgba = result_binary.data + (y * width + x) * 4;
            rgba[0] = bgra[2]; // R
            rgba[1] = bgra[1]; // G
            rgba[2] = bgra[0]; // B
            rgba[3] = bgra[3]; // A
        }
    }

    FPDFBitmap_Destroy(bitmap);
    FPDF_ClosePage(page);

    return enif_make_tuple4(env,
        enif_make_atom(env, "ok"),
        enif_make_binary(env, &result_binary),
        enif_make_int(env, width),
        enif_make_int(env, height));
}

static ErlNifFunc nif_funcs[] = {
    {"load_document", 1, load_pdf_document, 0},
    {"get_page_count", 1, get_page_count, 0},
    {"get_page_bitmap", 3, get_page_bitmap, 0}
};

ERL_NIF_INIT(Elixir.PDFium, nif_funcs, load, NULL, NULL, unload)
