defmodule PDFium.LowLevelTest do
  use ExUnit.Case

  alias PDFium.LowLevel
  alias PDFium.Test.Document

  import PDFium.Test.Helpers

  @annotated Path.expand("../fixtures/annotated.pdf", __DIR__)
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

  describe "pages" do
    test "are measured as pdfium measures them" do
      page = [box: {10, 20, 410, 620}, crop: {10, 20, 210, 320}, rotation: 90]
      {:ok, page} = tmp_path() |> Document.write!([page]) |> load!() |> LowLevel.fpdf_load_page(0)

      assert {:ok, 300.0} = LowLevel.fpdf_get_page_width_f(page)
      assert {:ok, 200.0} = LowLevel.fpdf_get_page_height_f(page)
      assert {:ok, {10.0, 320.0, 210.0, 20.0}} = LowLevel.fpdf_get_page_bounding_box(page)
      assert {:ok, 1} = LowLevel.fpdfpage_get_rotation(page)
    end

    test "are flattened, answering as pdfium does" do
      document = load!(@annotated)
      {:ok, page} = LowLevel.fpdf_load_page(document, 0)

      assert {:ok, 1} = LowLevel.fpdfpage_get_annot_count(page)
      assert {:ok, 1} = LowLevel.fpdfpage_flatten(page, 0)
      assert {:ok, 0} = LowLevel.fpdfpage_get_annot_count(page)
      assert {:ok, 2} = LowLevel.fpdfpage_flatten(page, 0)
    end

    test "that are not there do not load" do
      assert {:error, :page_load_failed} = LowLevel.fpdf_load_page(load!(@plain), 99)
    end

    test "answer page_closed once closed, closing included" do
      {:ok, page} = LowLevel.fpdf_load_page(load!(@plain), 0)

      assert :ok = LowLevel.fpdf_close_page(page)
      assert :ok = LowLevel.fpdf_close_page(page)
      assert {:error, :page_closed} = LowLevel.fpdf_get_page_width_f(page)
    end

    test "of a closed document answer document_closed, and still close" do
      document = load!(@plain)
      {:ok, page} = LowLevel.fpdf_load_page(document, 0)

      assert :ok = LowLevel.fpdf_close_document(document)
      assert {:error, :document_closed} = LowLevel.fpdf_get_page_count(document)
      assert {:error, :document_closed} = LowLevel.fpdf_get_page_width_f(page)
      assert :ok = LowLevel.fpdf_close_page(page)
      assert {:error, :page_closed} = LowLevel.fpdf_get_page_width_f(page)
    end

    test "dropped without closing are closed, and so are their documents" do
      task =
        Task.async(fn ->
          {:ok, document} = LowLevel.fpdf_load_mem_document64(File.read!(@plain), nil)
          for _ <- 1..50, do: LowLevel.fpdf_load_page(document, 0)
          :ok = LowLevel.fpdf_close_document(document)
        end)

      Task.await(task)
      :erlang.garbage_collect()

      assert {:ok, _count} = LowLevel.fpdf_get_page_count(load!(@plain))
    end
  end

  describe "bitmaps" do
    test "are filled, drawn into and read back" do
      {:ok, bitmap} = LowLevel.fpdfbitmap_create(2, 1, 0)

      assert :ok = LowLevel.fpdfbitmap_fill_rect(bitmap, 0, 0, 2, 1, 0xFFFF0000)
      assert {:ok, <<0, 0, 255, _, 0, 0, 255, _>>} = LowLevel.fpdfbitmap_get_buffer(bitmap)

      blue = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 2, 1}) |> load!()
      {:ok, page} = LowLevel.fpdf_load_page(blue, 0)

      assert :ok = LowLevel.fpdf_render_page_bitmap(bitmap, page, 0, 0, 2, 1, 0, 0x10)
      assert {:ok, <<0, 0, 255, _, 0, 0, 255, _>>} = LowLevel.fpdfbitmap_get_buffer(bitmap)
    end

    test "that cannot be made are refused" do
      assert {:error, :bitmap_creation_failed} = LowLevel.fpdfbitmap_create(0, 1, 0)
    end

    test "answer bitmap_destroyed once destroyed, destroying included" do
      {:ok, bitmap} = LowLevel.fpdfbitmap_create(2, 1, 0)
      {:ok, page} = LowLevel.fpdf_load_page(load!(@plain), 0)

      assert :ok = LowLevel.fpdfbitmap_destroy(bitmap)
      assert :ok = LowLevel.fpdfbitmap_destroy(bitmap)
      assert {:error, :bitmap_destroyed} = LowLevel.fpdfbitmap_get_buffer(bitmap)
      assert {:error, :bitmap_destroyed} = LowLevel.fpdfbitmap_fill_rect(bitmap, 0, 0, 1, 1, 0)

      assert {:error, :bitmap_destroyed} =
               LowLevel.fpdf_render_page_bitmap(bitmap, page, 0, 0, 2, 1, 0, 0)
    end
  end
end
