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

static ErlNifFunc nif_funcs[] = {
    {"load_document", 1, load_pdf_document, 0},  // Added 0 for flags
    {"get_page_count", 1, get_page_count, 0}     // Added 0 for flags
};

ERL_NIF_INIT(Elixir.PDFium, nif_funcs, load, NULL, NULL, unload)
