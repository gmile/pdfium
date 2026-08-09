defmodule PDFiumTest do
  use ExUnit.Case

  @annotated Path.expand("fixtures/annotated.pdf", __DIR__)
  @plain Path.expand("../custom/test.pdf", __DIR__)

  setup do
    output = Path.join(System.tmp_dir!(), "pdfium-test-#{System.unique_integer([:positive])}.pdf")
    on_exit(fn -> File.rm(output) end)

    {:ok, output: output}
  end

  defp tmp_path do
    path = Path.join(System.tmp_dir!(), "pdfium-test-#{System.unique_integer([:positive])}.pdf")
    on_exit(fn -> File.rm(path) end)

    path
  end

  defp open!(path) do
    {:ok, document} = PDFium.load_document(path)
    on_exit(fn -> PDFium.close_document(document) end)

    document
  end

  describe "load_document/1" do
    test "opens a document" do
      assert {:ok, _document} = PDFium.load_document(@plain)
    end

    test "names the reason a file is not one it can read" do
      path = tmp_path()
      File.write!(path, "not a pdf at all")

      assert {:error, :format} = PDFium.load_document(path)
    end

    test "names the reason a file is not there" do
      assert {:error, :file} = PDFium.load_document("/nonexistent-directory/absent.pdf")
    end
  end

  describe "get_page_bitmap/3" do
    defp ink(path) do
      document = open!(path)
      {:ok, bitmap, _width, _height} = PDFium.get_page_bitmap(document, 0, 100)

      for <<r::8, g::8, b::8, _a::8 <- bitmap>>, div(r + g + b, 3) < 200, reduce: 0 do
        count -> count + 1
      end
    end

    test "draws the annotations on the page" do
      # The annotation on this page paints over what is under it, so drawing it
      # covers ink rather than adding any. Flattening draws the same appearance
      # into the page content, so the two have to come out identical.
      flattened = tmp_path()
      document = open!(@annotated)
      assert {:ok, :flattened} = PDFium.flatten(document, flattened)

      assert ink(@annotated) == ink(flattened)
    end
  end

  describe "flatten/2" do
    test "renders annotations into the page and writes the result", %{output: output} do
      {:ok, document} = PDFium.load_document(@annotated)

      assert {:ok, :flattened} = PDFium.flatten(document, output)
      assert File.exists?(output)

      PDFium.close_document(document)

      {:ok, flattened} = PDFium.load_document(output)
      assert {:ok, 1} = PDFium.get_page_count(flattened)
      PDFium.close_document(flattened)
    end

    test "leaves the output alone when there is nothing to flatten", %{output: output} do
      {:ok, document} = PDFium.load_document(@plain)

      assert {:ok, :nothing_to_do} = PDFium.flatten(document, output)
      refute File.exists?(output)

      PDFium.close_document(document)
    end

    test "is idempotent", %{output: output} do
      {:ok, document} = PDFium.load_document(@annotated)
      assert {:ok, :flattened} = PDFium.flatten(document, output)
      PDFium.close_document(document)

      {:ok, flattened} = PDFium.load_document(output)
      second = output <> ".2"
      on_exit(fn -> File.rm(second) end)

      assert {:ok, :nothing_to_do} = PDFium.flatten(flattened, second)
      PDFium.close_document(flattened)
    end

    test "reports a closed document", %{output: output} do
      {:ok, document} = PDFium.load_document(@annotated)
      PDFium.close_document(document)

      assert {:error, :document_closed} = PDFium.flatten(document, output)
    end

    test "reports an unwritable output path" do
      {:ok, document} = PDFium.load_document(@annotated)

      assert {:error, :output_open_failed} =
               PDFium.flatten(document, "/nonexistent-directory/out.pdf")

      PDFium.close_document(document)
    end
  end
end
