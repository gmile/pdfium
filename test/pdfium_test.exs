defmodule PDFiumTest do
  use ExUnit.Case

  alias PDFium.Test.Document

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
