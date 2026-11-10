defmodule PDFium.LowLevelTest do
  use ExUnit.Case

  alias PDFium.LowLevel
  alias PDFium.Test.Document

  import PDFium.Test.Helpers

  @plain Path.expand("../fixtures/test.pdf", __DIR__)
  @encrypted_r5 Path.expand("../fixtures/encrypted-r5.pdf", __DIR__)
  @encrypted_user Path.expand("../fixtures/encrypted-user.pdf", __DIR__)

  defp load!(path) do
    {:ok, document} = LowLevel.fpdf_load_mem_document64(File.read!(path), nil)
    on_exit(fn -> LowLevel.fpdf_close_document(document) end)
    document
  end

  describe "documents" do
    test "load from contents, with a password when they need one" do
      contents = File.read!(@encrypted_user)

      assert {:error, :format} = LowLevel.fpdf_load_mem_document64("not a pdf", nil)
      assert {:error, :password} = LowLevel.fpdf_load_mem_document64(contents, nil)
      assert {:ok, document} = LowLevel.fpdf_load_mem_document64(contents, "secret")
      assert {:ok, 2} = LowLevel.fpdf_get_page_count(document)
    end

    test "are created empty" do
      assert {:ok, document} = LowLevel.fpdf_create_new_document()
      assert {:ok, 0} = LowLevel.fpdf_get_page_count(document)
    end

    test "answer document_closed to everything once closed, closing included" do
      document = load!(@plain)

      assert :ok = LowLevel.fpdf_close_document(document)
      assert :ok = LowLevel.fpdf_close_document(document)
      assert {:error, :document_closed} = LowLevel.fpdf_get_page_count(document)
      assert {:error, :document_closed} = LowLevel.fpdf_get_meta_text(document, "Title")
      assert {:error, :document_closed} = LowLevel.fpdf_save_as_copy(document, 0)

      {:ok, dest} = LowLevel.fpdf_create_new_document()

      assert {:error, :document_closed} =
               LowLevel.fpdf_import_pages_by_index(dest, document, nil, 0)
    end

    test "report the security handler revision as pdfium does, -1 for none" do
      assert {:ok, -1} = LowLevel.fpdf_get_security_handler_revision(load!(@plain))
      assert {:ok, 5} = LowLevel.fpdf_get_security_handler_revision(load!(@encrypted_r5))
    end

    test "read meta text as UTF-16LE" do
      document = tmp_path() |> Document.write!([[]], Title: "Bars") |> load!()

      assert {:ok, <<"B", 0, "a", 0, "r", 0, "s", 0>>} =
               LowLevel.fpdf_get_meta_text(document, "Title")

      assert {:ok, ""} = LowLevel.fpdf_get_meta_text(document, "Author")
    end

    test "save with the flags given" do
      document = load!(@encrypted_r5)

      assert {:ok, kept} = LowLevel.fpdf_save_as_copy(document, 0)
      assert {:ok, removed} = LowLevel.fpdf_save_as_copy(document, 4)

      assert {:ok, kept} = LowLevel.fpdf_load_mem_document64(kept, nil)
      assert {:ok, removed} = LowLevel.fpdf_load_mem_document64(removed, nil)
      assert {:ok, 5} = LowLevel.fpdf_get_security_handler_revision(kept)
      assert {:ok, -1} = LowLevel.fpdf_get_security_handler_revision(removed)
    end

    test "import every page for nil, and refuse an empty list" do
      source = tmp_path() |> Document.write!([[], [], []]) |> load!()
      {:ok, dest} = LowLevel.fpdf_create_new_document()

      assert :ok = LowLevel.fpdf_import_pages_by_index(dest, source, nil, 0)
      assert :ok = LowLevel.fpdf_import_pages_by_index(dest, source, [1], 3)
      assert {:ok, 4} = LowLevel.fpdf_get_page_count(dest)
      assert {:error, :import_failed} = LowLevel.fpdf_import_pages_by_index(dest, source, [], 0)
    end
  end
end
