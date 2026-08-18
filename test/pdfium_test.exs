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

  describe "load_memory_document/1" do
    test "opens a document from its contents" do
      {:ok, from_path} = PDFium.load_document(@plain)
      {:ok, pages} = PDFium.get_page_count(from_path)

      assert {:ok, document} = PDFium.load_memory_document(File.read!(@plain))
      assert {:ok, ^pages} = PDFium.get_page_count(document)
    end

    test "keeps the contents for as long as the document is open" do
      assert {:ok, document} = PDFium.load_memory_document(File.read!(@plain))

      :erlang.garbage_collect()

      assert {:ok, pages} = PDFium.get_page_count(document)
      assert pages > 0
    end

    test "names the reason contents are not a document it can read" do
      assert {:error, :format} = PDFium.load_memory_document("not a pdf at all")
    end
  end

  describe "with_memory_document/2" do
    test "runs the function with the document it opened" do
      assert {:ok, pages} =
               PDFium.with_memory_document(File.read!(@plain), &PDFium.get_page_count/1)

      assert pages > 0
    end

    test "closes the document even when the function raises" do
      assert_raise RuntimeError, fn ->
        PDFium.with_memory_document(File.read!(@plain), fn _document -> raise "boom" end)
      end
    end
  end

  describe "save_to_binary/1" do
    test "answers with the document as it would have been written" do
      {:ok, document} = PDFium.load_document(@plain)

      assert {:ok, saved} = PDFium.save_to_binary(document)
      assert String.starts_with?(saved, "%PDF-")
    end

    test "answers with a document that can be opened again" do
      {:ok, document} = PDFium.load_memory_document(File.read!(@annotated))
      {:ok, pages} = PDFium.get_page_count(document)

      assert {:ok, saved} = PDFium.save_to_binary(document)
      assert {:ok, reopened} = PDFium.load_memory_document(saved)
      assert {:ok, ^pages} = PDFium.get_page_count(reopened)
    end

    test "refuses a document that has been closed" do
      {:ok, document} = PDFium.load_document(@plain)
      :ok = PDFium.close_document(document)

      assert {:error, :document_closed} = PDFium.save_to_binary(document)
    end
  end

  describe "with_document/2" do
    test "runs the function with the document it opened" do
      path = tmp_path() |> Document.write!([[box: {0, 0, 100, 100}], []])

      assert {:ok, 2} = PDFium.with_document(path, &PDFium.get_page_count/1)
    end

    test "closes the document afterwards" do
      document = PDFium.with_document(@plain, & &1)

      assert {:error, :document_closed} = PDFium.get_page_count(document)
    end

    test "closes the document even when the work raises" do
      test = self()

      assert_raise RuntimeError, "the work failed", fn ->
        PDFium.with_document(@plain, fn document ->
          send(test, {:document, document})
          raise "the work failed"
        end)
      end

      assert_received {:document, document}
      assert {:error, :document_closed} = PDFium.get_page_count(document)
    end

    test "answers the reason it could not open the document, and does not run" do
      assert {:error, :file} =
               PDFium.with_document("/nonexistent-directory/absent.pdf", fn _document ->
                 flunk("ran against a document that was never opened")
               end)
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
      assert {:ok, :flattened} = Toolbox.flatten(@annotated, flattened)

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

      {:ok, source: tmp_path() |> Document.write!(pages)}
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
      source = tmp_path() |> Document.filled({1, 0, 0}, box: {0, 0, 100, 100})

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

    test "reports a document it cannot open", %{output: output} do
      assert {:error, :file} =
               Toolbox.extract_pages("/nonexistent-directory/absent.pdf", [0], output)
    end

    test "reports an unwritable output path", %{source: source} do
      assert {:error, :output_open_failed} =
               Toolbox.extract_pages(source, [0], "/nonexistent-directory/out.pdf")
    end
  end

  describe "merge/2" do
    defp document!(pages), do: tmp_path() |> Document.write!(pages)

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
      red = tmp_path() |> Document.filled({1, 0, 0}, box: {0, 0, 100, 100})
      blue = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 100, 100})

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

    test "reports a document it cannot open", %{output: output} do
      first = document!([[box: {0, 0, 100, 100}]])

      assert {:error, :file} = Toolbox.merge([first, "/nonexistent-directory/absent.pdf"], output)
      refute File.exists?(output)
    end

    test "reports an unwritable output path" do
      document = document!([[box: {0, 0, 100, 100}]])

      assert {:error, :output_open_failed} =
               Toolbox.merge([document], "/nonexistent-directory/out.pdf")
    end
  end

  describe "flatten_page/3" do
    test "draws the annotations on the page it names" do
      document = open!(@annotated)

      assert {:ok, :flattened} = PDFium.flatten_page(document, 0)
      assert {:ok, [0]} = PDFium.get_annotation_counts(document)
    end

    test "says when a page had nothing to draw" do
      document = tmp_path() |> Document.write!([[]]) |> open!()

      assert {:ok, :nothing_to_do} = PDFium.flatten_page(document, 0)
    end

    test "leaves the pages it was not asked about", %{output: output} do
      pages = tmp_path() |> Document.write!([[], []]) |> open!()
      assert {:ok, :saved} = PDFium.save(pages, output)

      document = open!(@annotated)
      assert {:ok, [1]} = PDFium.get_annotation_counts(document)
    end

    test "reports a page that is not there" do
      document = open!(@annotated)

      assert {:error, :page_load_failed} = PDFium.flatten_page(document, 9)
    end

    test "reports a closed document" do
      document = open!(@plain)
      PDFium.close_document(document)

      assert {:error, :document_closed} = PDFium.flatten_page(document, 0)
    end
  end

  describe "stamp/3, placed by matrix" do
    test "puts the overlay where the matrix says", %{output: output} do
      # A quarter page of blue in its own bottom left corner, placed into the
      # top right quarter of a page four times its size.
      overlay =
        tmp_path()
        |> Document.write!([[box: {0, 0, 200, 200}, content: "0 0 1 rg 0 0 100 100 re f"]])
        |> open!()

      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]]) |> open!()

      placement = {1.0, 0.0, 0.0, 1.0, 200.0, 200.0}

      assert {:ok, :stamped} = PDFium.stamp(document, [{overlay, 0, 0, placement}], output)

      assert blue?(colour_at(output, 0.625, 0.625)), "moved into the top right quarter"
      refute blue?(colour_at(output, 0.125, 0.125)), "not left in the bottom left"
    end

    test "scales by the matrix it was given", %{output: output} do
      overlay = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 400, 400}) |> open!()
      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]]) |> open!()

      assert {:ok, :stamped} =
               PDFium.stamp(document, [{overlay, 0, 0, {0.5, 0.0, 0.0, 0.5, 0.0, 0.0}}], output)

      assert blue?(colour_at(output, 0.25, 0.25)), "the quarter it was scaled into"
      refute blue?(colour_at(output, 0.75, 0.75)), "and nothing beyond it"
    end

    test "reads the matrix in the page as displayed, not as written", %{output: output} do
      # The page is turned a quarter, so the bottom left of the page a reader
      # sees is not the origin the page's own content is written from.
      overlay = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 300, 300}) |> open!()

      document =
        tmp_path() |> Document.write!([[box: {0, 0, 400, 600}, rotation: 90]]) |> open!()

      assert {:ok, :stamped} =
               PDFium.stamp(document, [{overlay, 0, 0, {1.0, 0.0, 0.0, 1.0, 0.0, 0.0}}], output)

      assert blue?(colour_at(output, 0.1, 0.1)), "the corner a reader calls bottom left"
    end
  end

  describe "Toolbox.stamp/3, fitted and centred" do
    test "measures a many-paged overlay by its first page", %{output: output} do
      # The header and footer of a contract is drawn as one page per page of the
      # contract, and only the first of them is ever drawn over anything here.
      overlay =
        tmp_path()
        |> Document.write!([
          [box: {0, 0, 400, 400}, content: "0 0 1 rg 0 0 400 400 re f"],
          [box: {0, 0, 400, 400}]
        ])

      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]])

      assert {:ok, :stamped} = Toolbox.stamp(document, [{overlay, 0}], output)
      assert blue?(colour_at(output, 0.5, 0.5))
    end

    defp corner_overlay(box) do
      {left, bottom, right, top} = box
      width = (right - left) / 2
      height = (top - bottom) / 2

      content = "0 0 1 rg #{left} #{bottom} #{width} #{height} re f"

      tmp_path() |> Document.write!([[box: box, content: content]])
    end

    defp blue?({red, green, blue}), do: blue > 200 and red < 100 and green < 100

    test "draws the overlay where it was drawn", %{output: output} do
      box = {0, 0, 400, 400}
      document = tmp_path() |> Document.write!([[box: box]])

      assert {:ok, :stamped} = Toolbox.stamp(document, [{corner_overlay(box), 0}], output)

      assert blue?(colour_at(output, 0.25, 0.25)), "the corner it was drawn in"
      refute blue?(colour_at(output, 0.75, 0.75)), "the corner across from it"
    end

    test "keeps the content the page already had", %{output: output} do
      box = {0, 0, 400, 400}
      document = tmp_path() |> Document.filled({1, 0, 0}, box: box)

      assert {:ok, :stamped} = Toolbox.stamp(document, [{corner_overlay(box), 0}], output)

      assert blue?(colour_at(output, 0.25, 0.25))
      assert colour_at(output, 0.75, 0.75) == {255, 0, 0}
    end

    test "draws over the page it was paired with and no other", %{output: output} do
      box = {0, 0, 400, 400}
      pages = [[box: box], [box: box], [box: box]]
      document = tmp_path() |> Document.write!(pages)

      assert {:ok, :stamped} = Toolbox.stamp(document, [{corner_overlay(box), 1}], output)

      refute blue?(colour_at(output, 0.25, 0.25, 0))
      assert blue?(colour_at(output, 0.25, 0.25, 1))
      refute blue?(colour_at(output, 0.25, 0.25, 2))
    end

    test "draws one overlay over as many pages as it is given", %{output: output} do
      box = {0, 0, 400, 400}
      document = tmp_path() |> Document.write!([[box: box], [box: box]])
      overlay = corner_overlay(box)

      assert {:ok, :stamped} =
               Toolbox.stamp(document, [{overlay, 0}, {overlay, 1}], output)

      assert blue?(colour_at(output, 0.25, 0.25, 0))
      assert blue?(colour_at(output, 0.25, 0.25, 1))
    end

    test "stacks overlays on one page in the order given", %{output: output} do
      box = {0, 0, 400, 400}
      document = tmp_path() |> Document.write!([[box: box]])

      under = tmp_path() |> Document.filled({0, 1, 0}, box: box)
      over = tmp_path() |> Document.filled({1, 0, 0}, box: box)

      assert {:ok, :stamped} = Toolbox.stamp(document, [{under, 0}, {over, 0}], output)

      assert colour_at(output, 0.5, 0.5) == {255, 0, 0}
    end

    test "places against a box that does not start at the origin", %{output: output} do
      box = {-100, -100, 300, 300}
      document = tmp_path() |> Document.write!([[box: box]])
      overlay = corner_overlay({0, 0, 400, 400})

      assert {:ok, :stamped} = Toolbox.stamp(document, [{overlay, 0}], output)

      assert blue?(colour_at(output, 0.25, 0.25))
      refute blue?(colour_at(output, 0.75, 0.75))
    end

    test "turns the overlay with the page it goes over", %{output: output} do
      box = {0, 0, 400, 600}
      document = tmp_path() |> Document.write!([[box: box, rotation: 90]])

      overlay = corner_overlay({0, 0, 600, 400})

      assert {:ok, :stamped} = Toolbox.stamp(document, [{overlay, 0}], output)

      assert blue?(colour_at(output, 0.25, 0.25))
      refute blue?(colour_at(output, 0.75, 0.75))
    end

    test "scales an overlay of a different shape to fit, centred", %{output: output} do
      box = {0, 0, 400, 400}
      document = tmp_path() |> Document.write!([[box: box]])
      overlay = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 400, 800})

      assert {:ok, :stamped} = Toolbox.stamp(document, [{overlay, 0}], output)

      assert blue?(colour_at(output, 0.5, 0.5)), "the middle it was centred on"
      refute blue?(colour_at(output, 0.1, 0.5)), "the strip left bare beside it"
      refute blue?(colour_at(output, 0.9, 0.5)), "and the one on the other side"
    end

    test "reports a page that is not there", %{output: output} do
      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]])

      assert {:error, :page_load_failed} =
               Toolbox.stamp(document, [{corner_overlay({0, 0, 400, 400}), 9}], output)
    end

    test "reports an overlay with no pages", %{output: output} do
      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]])
      overlay = tmp_path() |> Document.write!([])

      assert {:error, :page_load_failed} = Toolbox.stamp(document, [{overlay, 0}], output)
    end

    test "reports an overlay it cannot open", %{output: output} do
      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]])
      absent = "/nonexistent-directory/absent.pdf"

      assert {:error, :file} = Toolbox.stamp(document, [{absent, 0}], output)
    end

    test "draws each page of the overlay over the page in the same place" do
      # A header and footer is drawn as one overlay page per page of the
      # document, each carrying that page's own number.
      overlay =
        tmp_path()
        |> Document.write!([
          [box: {0, 0, 400, 400}, content: "1 0 0 rg 0 0 400 400 re f"],
          [box: {0, 0, 400, 400}, content: "0 0 1 rg 0 0 400 400 re f"]
        ])

      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}], [box: {0, 0, 400, 400}]])
      output = tmp_path()

      assert {:ok, :stamped} = Toolbox.overlay(document, overlay, output)

      assert colour_at(output, 0.5, 0.5, 0) == {255, 0, 0}, "page one takes overlay page one"
      assert colour_at(output, 0.5, 0.5, 1) == {0, 0, 255}, "page two takes overlay page two"
    end

    test "refuses an overlay rendered for a document of another length" do
      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}], [box: {0, 0, 400, 400}]])
      overlay = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]])

      assert {:error, :page_count_mismatch} = Toolbox.overlay(document, overlay, tmp_path())
    end

    test "takes an overlay as contents, drawing what it would have from a file" do
      overlay =
        tmp_path()
        |> Document.write!([
          [box: {0, 0, 400, 400}, content: "1 0 0 rg 0 0 400 400 re f"],
          [box: {0, 0, 400, 400}, content: "0 0 1 rg 0 0 400 400 re f"]
        ])

      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}], [box: {0, 0, 400, 400}]])

      from_file = tmp_path()
      assert {:ok, :stamped} = Toolbox.overlay(document, overlay, from_file)

      assert {:ok, stamped} =
               Toolbox.overlay_to_binary(document, {:bytes, File.read!(overlay)})

      from_contents = tmp_path()
      File.write!(from_contents, stamped)

      assert colour_at(from_contents, 0.5, 0.5, 0) == colour_at(from_file, 0.5, 0.5, 0)
      assert colour_at(from_contents, 0.5, 0.5, 1) == colour_at(from_file, 0.5, 0.5, 1)
    end

    test "answers with a document rather than writing one" do
      overlay = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 400, 400})
      document = tmp_path() |> Document.filled({1, 0, 0}, box: {0, 0, 400, 400})

      assert {:ok, stamped} = Toolbox.overlay_to_binary({:bytes, File.read!(document)}, overlay)
      assert String.starts_with?(stamped, "%PDF-")
      assert {:ok, 1} = PDFium.with_memory_document(stamped, &PDFium.get_page_count/1)
    end

    test "refuses contents that are not a document" do
      document = tmp_path() |> Document.filled({1, 0, 0}, box: {0, 0, 400, 400})

      assert {:error, :format} = Toolbox.overlay_to_binary(document, {:bytes, "not a pdf"})
    end

    test "draws nothing when given nothing", %{output: output} do
      document = tmp_path() |> Document.filled({1, 0, 0}, box: {0, 0, 400, 400})

      assert {:ok, :stamped} = Toolbox.stamp(document, [], output)

      assert colour_at(output, 0.5, 0.5) == {255, 0, 0}
    end
  end

  describe "flatten/2" do
    test "renders annotations into the page and writes the result", %{output: output} do
      assert {:ok, :flattened} = Toolbox.flatten(@annotated, output)
      assert File.exists?(output)

      assert {:ok, 1} = PDFium.get_page_count(open!(output))
    end

    test "leaves the output alone when there is nothing to flatten", %{output: output} do
      assert {:ok, :nothing_to_do} = Toolbox.flatten(@plain, output)
      refute File.exists?(output)
    end

    test "is idempotent", %{output: output} do
      assert {:ok, :flattened} = Toolbox.flatten(@annotated, output)

      second = output <> ".2"
      on_exit(fn -> File.rm(second) end)

      assert {:ok, :nothing_to_do} = Toolbox.flatten(output, second)
    end

    test "reports a document it cannot open", %{output: output} do
      assert {:error, :file} = Toolbox.flatten("/nonexistent-directory/absent.pdf", output)
    end

    test "reports an unwritable output path" do
      assert {:error, :output_open_failed} =
               Toolbox.flatten(@annotated, "/nonexistent-directory/out.pdf")
    end
  end
end
