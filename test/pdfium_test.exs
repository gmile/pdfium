defmodule PDFiumTest do
  use ExUnit.Case

  alias PDFium.Test.Document
  alias PDFium.Toolbox

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

  defp colour_at(path, across, up, page \\ 0) do
    document = open!(path)
    {:ok, bitmap, width, height} = PDFium.get_page_bitmap(document, page, 72)

    x = trunc(across * width)
    y = height - trunc(up * height) - 1
    offset = (y * width + x) * 4

    <<_::binary-size(^offset), red::8, green::8, blue::8, _alpha::8, _rest::binary>> = bitmap

    {red, green, blue}
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

  describe "get_page_boxes/1" do
    test "reports the box of every page, in order" do
      pages = [
        [box: {0, 0, 200, 300}],
        [box: {0, 0, 400, 500}]
      ]

      document = tmp_path() |> Document.write!(pages) |> open!()

      assert {:ok, [first, second]} = PDFium.get_page_boxes(document)

      assert %{left: +0.0, bottom: +0.0, right: 200.0, top: 300.0, rotation: 0} = first
      assert %{left: +0.0, bottom: +0.0, right: 400.0, top: 500.0, rotation: 0} = second
    end

    test "reports a box that does not start at the origin" do
      document = tmp_path() |> Document.write!([[box: {-10, -20, 590, 772}]]) |> open!()

      assert {:ok, [box]} = PDFium.get_page_boxes(document)
      assert %{left: -10.0, bottom: -20.0, right: 590.0, top: 772.0} = box
    end

    test "sorts the corners it was given" do
      document = tmp_path() |> Document.write!([[box: {590, 772, -10, -20}]]) |> open!()

      assert {:ok, [box]} = PDFium.get_page_boxes(document)
      assert %{left: -10.0, bottom: -20.0, right: 590.0, top: 772.0} = box
    end

    test "reports rotation in degrees" do
      pages = Enum.map([0, 90, 180, 270], &[rotation: &1])
      document = tmp_path() |> Document.write!(pages) |> open!()

      assert {:ok, boxes} = PDFium.get_page_boxes(document)
      assert Enum.map(boxes, & &1.rotation) == [0, 90, 180, 270]
    end

    test "reports the box the page is turned from, not the one it displays as" do
      document = tmp_path() |> Document.write!([[box: {0, 0, 612, 792}, rotation: 90]]) |> open!()

      assert {:ok, [box]} = PDFium.get_page_boxes(document)
      assert %{right: 612.0, top: 792.0, rotation: 90} = box
    end

    test "reports nothing for a document with no pages" do
      document = tmp_path() |> Document.write!([]) |> open!()

      assert {:ok, []} = PDFium.get_page_boxes(document)
    end

    test "reports a closed document" do
      document = open!(@plain)
      PDFium.close_document(document)

      assert {:error, :document_closed} = PDFium.get_page_boxes(document)
    end
  end

  describe "get_annotation_counts/1" do
    test "counts the annotations on each page, in order" do
      {:ok, document} = PDFium.load_document(@annotated)
      on_exit(fn -> PDFium.close_document(document) end)

      assert {:ok, [1]} = PDFium.get_annotation_counts(document)
    end

    test "counts a page with no annotations as none" do
      document = tmp_path() |> Document.write!([[], []]) |> open!()

      assert {:ok, [0, 0]} = PDFium.get_annotation_counts(document)
    end

    test "counts nothing for a document with no pages" do
      document = tmp_path() |> Document.write!([]) |> open!()

      assert {:ok, []} = PDFium.get_annotation_counts(document)
    end

    test "reports a closed document" do
      document = open!(@plain)
      PDFium.close_document(document)

      assert {:error, :document_closed} = PDFium.get_annotation_counts(document)
    end
  end

  describe "get_meta_text/2" do
    test "reads an entry the specification names" do
      document =
        tmp_path() |> Document.write!([[]], Title: "A contract", Author: "Someone") |> open!()

      assert {:ok, "A contract"} = PDFium.get_meta_text(document, "Title")
      assert {:ok, "Someone"} = PDFium.get_meta_text(document, "Author")
    end

    test "reads an entry the specification does not name" do
      document =
        tmp_path() |> Document.write!([[]], SignedBy: ~s([{"name":"Someone"}])) |> open!()

      assert {:ok, ~s([{"name":"Someone"}])} = PDFium.get_meta_text(document, "SignedBy")
    end

    test "reads a value stored as text rather than as bytes" do
      document = tmp_path() |> Document.write!([[]], Author: "Stanisław Lem") |> open!()

      assert {:ok, "Stanisław Lem"} = PDFium.get_meta_text(document, "Author")
    end

    test "reads an entry that is not there as nothing" do
      document = tmp_path() |> Document.write!([[]], Title: "A contract") |> open!()

      assert {:ok, ""} = PDFium.get_meta_text(document, "Author")
    end

    test "reads a document with no entries at all as nothing" do
      document = tmp_path() |> Document.write!([[]]) |> open!()

      assert {:ok, ""} = PDFium.get_meta_text(document, "Title")
    end

    test "reports a closed document" do
      document = open!(@plain)
      PDFium.close_document(document)

      assert {:error, :document_closed} = PDFium.get_meta_text(document, "Title")
    end
  end

  describe "documents" do
    test "a new one has no pages", %{output: output} do
      assert {:ok, document} = PDFium.create_document()
      assert {:ok, 0} = PDFium.get_page_count(document)

      assert {:ok, :saved} = PDFium.save(document, output)
      assert {:ok, 0} = PDFium.get_page_count(open!(output))
    end

    test "importing named pages, in the order named", %{output: output} do
      pages = Enum.map([200, 300, 400], &[box: {0, 0, &1, &1}])
      source = tmp_path() |> Document.write!(pages) |> open!()

      PDFium.with_new_document(fn document ->
        assert {:ok, :imported} = PDFium.import_pages(document, source, [2, 0], 0)
        assert {:ok, :saved} = PDFium.save(document, output)
      end)

      assert {:ok, boxes} = PDFium.get_page_boxes(open!(output))
      assert Enum.map(boxes, & &1.right) == [400.0, 200.0]
    end

    test "importing every page of one into another", %{output: output} do
      source = tmp_path() |> Document.write!([[box: {0, 0, 100, 100}], []]) |> open!()

      PDFium.with_new_document(fn document ->
        assert {:ok, :imported} = PDFium.import_pages(document, source, :all, 0)
        assert {:ok, :saved} = PDFium.save(document, output)
      end)

      assert {:ok, 2} = PDFium.get_page_count(open!(output))
    end

    test "importing where the caller asked", %{output: output} do
      first = tmp_path() |> Document.write!([[box: {0, 0, 100, 100}]]) |> open!()
      second = tmp_path() |> Document.write!([[box: {0, 0, 200, 200}]]) |> open!()

      PDFium.with_new_document(fn document ->
        assert {:ok, :imported} = PDFium.import_pages(document, first, :all, 0)
        assert {:ok, :imported} = PDFium.import_pages(document, second, :all, 0)
        assert {:ok, :saved} = PDFium.save(document, output)
      end)

      assert {:ok, boxes} = PDFium.get_page_boxes(open!(output))
      assert Enum.map(boxes, & &1.right) == [200.0, 100.0]
    end

    test "refusing to import no pages at all" do
      source = tmp_path() |> Document.write!([[]]) |> open!()

      PDFium.with_new_document(fn document ->
        assert {:error, :no_pages} = PDFium.import_pages(document, source, [], 0)
      end)
    end

    test "reporting a page that is not there" do
      source = tmp_path() |> Document.write!([[]]) |> open!()

      PDFium.with_new_document(fn document ->
        assert {:error, :import_failed} = PDFium.import_pages(document, source, [9], 0)
      end)
    end

    test "reporting a closed document", %{output: output} do
      document = open!(@plain)
      PDFium.close_document(document)

      assert {:error, :document_closed} = PDFium.save(document, output)
    end

    test "reporting an unwritable path" do
      PDFium.with_new_document(fn document ->
        assert {:error, :output_open_failed} =
                 PDFium.save(document, "/nonexistent-directory/out.pdf")
      end)
    end
  end

  describe "extract_pages/3" do
    setup do
      pages = Enum.map([200, 300, 400, 500], &[box: {0, 0, &1, &1}])

      {:ok, source: tmp_path() |> Document.write!(pages) |> open!()}
    end

    test "writes the pages it was given", %{source: source, output: output} do
      assert {:ok, :extracted} = Toolbox.extract_pages(source, [1, 2], output)

      assert {:ok, boxes} = PDFium.get_page_boxes(open!(output))
      assert Enum.map(boxes, & &1.right) == [300.0, 400.0]
    end

    test "writes them in the order it was given", %{source: source, output: output} do
      assert {:ok, :extracted} = Toolbox.extract_pages(source, [3, 0], output)

      assert {:ok, boxes} = PDFium.get_page_boxes(open!(output))
      assert Enum.map(boxes, & &1.right) == [500.0, 200.0]
    end

    test "writes a page named twice twice", %{source: source, output: output} do
      assert {:ok, :extracted} = Toolbox.extract_pages(source, [0, 0], output)

      assert {:ok, boxes} = PDFium.get_page_boxes(open!(output))
      assert Enum.map(boxes, & &1.right) == [200.0, 200.0]
    end

    test "keeps what is drawn on the page it took", %{output: output} do
      source = tmp_path() |> Document.filled({1, 0, 0}, box: {0, 0, 100, 100}) |> open!()

      assert {:ok, :extracted} = Toolbox.extract_pages(source, [0], output)

      assert colour_at(output, 0.5, 0.5) == {255, 0, 0}
    end

    test "refuses to extract no pages at all", %{source: source, output: output} do
      assert {:error, :no_pages} = Toolbox.extract_pages(source, [], output)
      refute File.exists?(output)
    end

    test "reports a page that is not there", %{source: source, output: output} do
      assert {:error, :import_failed} = Toolbox.extract_pages(source, [9], output)
    end

    test "reports a closed document", %{source: source, output: output} do
      PDFium.close_document(source)

      assert {:error, :document_closed} = Toolbox.extract_pages(source, [0], output)
    end

    test "reports an unwritable output path", %{source: source} do
      assert {:error, :output_open_failed} =
               Toolbox.extract_pages(source, [0], "/nonexistent-directory/out.pdf")
    end
  end

  describe "merge/2" do
    defp document!(pages), do: tmp_path() |> Document.write!(pages) |> open!()

    test "writes the documents as one, in order", %{output: output} do
      first = document!([[box: {0, 0, 100, 100}], [box: {0, 0, 200, 200}]])
      second = document!([[box: {0, 0, 300, 300}]])

      assert {:ok, :merged} = Toolbox.merge([first, second], output)

      assert {:ok, boxes} = PDFium.get_page_boxes(open!(output))
      assert Enum.map(boxes, & &1.right) == [100.0, 200.0, 300.0]
    end

    test "writes a document given twice twice", %{output: output} do
      document = document!([[box: {0, 0, 100, 100}]])

      assert {:ok, :merged} = Toolbox.merge([document, document], output)

      assert {:ok, boxes} = PDFium.get_page_boxes(open!(output))
      assert length(boxes) == 2
    end

    test "keeps what is drawn on each page", %{output: output} do
      red = tmp_path() |> Document.filled({1, 0, 0}, box: {0, 0, 100, 100}) |> open!()
      blue = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 100, 100}) |> open!()

      assert {:ok, :merged} = Toolbox.merge([red, blue], output)

      assert colour_at(output, 0.5, 0.5, 0) == {255, 0, 0}
      assert colour_at(output, 0.5, 0.5, 1) == {0, 0, 255}
    end

    test "carries a document with no pages without complaint", %{output: output} do
      empty = document!([])
      page = document!([[box: {0, 0, 100, 100}]])

      assert {:ok, :merged} = Toolbox.merge([empty, page, empty], output)

      assert {:ok, boxes} = PDFium.get_page_boxes(open!(output))
      assert Enum.map(boxes, & &1.right) == [100.0]
    end

    test "refuses to merge nothing at all", %{output: output} do
      assert {:error, :no_documents} = Toolbox.merge([], output)
      refute File.exists?(output)
    end

    test "reports a closed document", %{output: output} do
      first = document!([[box: {0, 0, 100, 100}]])
      second = document!([[box: {0, 0, 100, 100}]])
      PDFium.close_document(second)

      assert {:error, :document_closed} = Toolbox.merge([first, second], output)
      refute File.exists?(output)
    end

    test "reports an unwritable output path" do
      document = document!([[box: {0, 0, 100, 100}]])

      assert {:error, :output_open_failed} =
               Toolbox.merge([document], "/nonexistent-directory/out.pdf")
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
