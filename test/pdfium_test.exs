defmodule PDFiumTest do
  use ExUnit.Case

  alias PDFium.Test.Document
  alias PDFium.Toolbox

  import PDFium.Test.Helpers

  @annotated Path.expand("fixtures/annotated.pdf", __DIR__)
  @plain Path.expand("fixtures/test.pdf", __DIR__)
  @encrypted_r5 Path.expand("fixtures/encrypted-r5.pdf", __DIR__)
  @encrypted_r6 Path.expand("fixtures/encrypted-r6.pdf", __DIR__)

  describe "open_document/1" do
    test "opens a document" do
      assert {:ok, _document} = PDFium.open_document(@plain)
    end

    test "names the reason a file is not one it can read" do
      path = tmp_path()
      File.write!(path, "not a pdf at all")

      assert {:error, :format} = PDFium.open_document(path)
    end

    test "names the reason a file is not there" do
      assert {:error, :file} = PDFium.open_document("/nonexistent-directory/absent.pdf")
    end
  end

  describe "open_document/1 from contents" do
    test "opens a document from its contents" do
      {:ok, from_path} = PDFium.open_document(@plain)
      {:ok, pages} = PDFium.get_page_count(from_path)

      assert {:ok, document} = PDFium.open_document({:bytes, File.read!(@plain)})
      assert {:ok, ^pages} = PDFium.get_page_count(document)
    end

    test "keeps the contents for as long as the document is open" do
      assert {:ok, document} = PDFium.open_document({:bytes, File.read!(@plain)})

      :erlang.garbage_collect()

      assert {:ok, pages} = PDFium.get_page_count(document)
      assert pages > 0
    end

    test "names the reason contents are not a document it can read" do
      assert {:error, :format} = PDFium.open_document({:bytes, "not a pdf at all"})
    end
  end

  describe "with_document/2 from contents" do
    test "runs the function with the document it opened" do
      assert {:ok, pages} =
               PDFium.with_document({:bytes, File.read!(@plain)}, &PDFium.get_page_count/1)

      assert pages > 0
    end

    test "closes the document even when the function raises" do
      assert_raise RuntimeError, fn ->
        PDFium.with_document({:bytes, File.read!(@plain)}, fn _document -> raise "boom" end)
      end
    end
  end

  describe "save_to_binary/1" do
    test "answers with the document as it would have been written" do
      {:ok, document} = PDFium.open_document(@plain)

      assert {:ok, saved} = PDFium.save_to_binary(document)
      assert String.starts_with?(saved, "%PDF-")
    end

    test "answers with a document that can be opened again" do
      {:ok, document} = PDFium.open_document({:bytes, File.read!(@annotated)})
      {:ok, pages} = PDFium.get_page_count(document)

      assert {:ok, saved} = PDFium.save_to_binary(document)
      assert {:ok, reopened} = PDFium.open_document({:bytes, saved})
      assert {:ok, ^pages} = PDFium.get_page_count(reopened)
    end

    test "refuses a document that has been closed" do
      {:ok, document} = PDFium.open_document(@plain)
      :ok = PDFium.close_document(document)

      assert {:error, :document_closed} = PDFium.save_to_binary(document)
    end
  end

  describe "get_security_handler_revision/1" do
    test "names the revision of the standard security handler" do
      assert {:ok, 5} = PDFium.get_security_handler_revision(open!(@encrypted_r5))
      assert {:ok, 6} = PDFium.get_security_handler_revision(open!(@encrypted_r6))
    end

    test "answers nil for a document that is not encrypted" do
      assert {:ok, nil} = PDFium.get_security_handler_revision(open!(@plain))
    end

    test "reports a closed document" do
      document = open!(@plain)
      PDFium.close_document(document)

      assert {:error, :document_closed} = PDFium.get_security_handler_revision(document)
    end
  end

  describe "writing with security removed" do
    test "save/3 keeps the encryption unless told otherwise" do
      output = tmp_path()
      assert :ok = PDFium.save(open!(@encrypted_r5), output)
      assert revision_of(output) == 5
    end

    test "save/3 writes the document without its encryption" do
      output = tmp_path()
      assert :ok = PDFium.save(open!(@encrypted_r5), output, :remove)
      assert revision_of(output) == nil
      assert {:ok, 1} = PDFium.get_page_count(open!(output))
    end

    test "save_to_binary/2 answers with the document without its encryption" do
      assert {:ok, saved} = PDFium.save_to_binary(open!(@encrypted_r6), :remove)
      assert {:ok, reopened} = PDFium.open_document({:bytes, saved})
      assert {:ok, nil} = PDFium.get_security_handler_revision(reopened)
    end

    test "stamp/4 writes the document without its encryption" do
      output = tmp_path()
      overlay = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 200, 200}) |> open!()
      placement = {1.0, 0.0, 0.0, 1.0, 0.0, 0.0}

      document = open!(@encrypted_r5)
      assert :ok = PDFium.stamp(document, [{overlay, 0, 0, placement}])
      assert :ok = PDFium.save(document, output, :remove)

      assert revision_of(output) == nil
      assert blue?(colour_at(output, 0.5, 0.5))
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
      {:ok, {bitmap, _width, _height}} = PDFium.get_page_bitmap(document, 0, 100)

      for <<r::8, g::8, b::8, _a::8 <- bitmap>>, div(r + g + b, 3) < 200, reduce: 0 do
        count -> count + 1
      end
    end

    test "draws the annotations on the page" do
      # The annotation on this page paints over what is under it, so drawing it
      # covers ink rather than adding any. Flattening draws the same appearance
      # into the page content, so the two have to come out identical.
      flattened = tmp_path()
      assert :ok = write(Toolbox.flatten(@annotated), flattened)

      assert ink(@annotated) == ink(flattened)
    end
  end

  describe "get_page_boxes/1" do
    test "reports the sorted box and rotation of every page, in order" do
      pages = [[box: {0, 0, 200, 300}], [box: {590, 772, -10, -20}, rotation: 90]]
      document = tmp_path() |> Document.write!(pages) |> open!()

      assert {:ok, [first, second]} = PDFium.get_page_boxes(document)
      assert %{left: +0.0, bottom: +0.0, right: 200.0, top: 300.0, rotation: 0} = first
      assert %{left: -10.0, bottom: -20.0, right: 590.0, top: 772.0, rotation: 90} = second
    end

    test "reports a closed document" do
      document = open!(@plain)
      PDFium.close_document(document)

      assert {:error, :document_closed} = PDFium.get_page_boxes(document)
    end
  end

  describe "get_page_sizes/1" do
    test "reports every page as displayed, turned pages included" do
      pages = [[box: {0, 0, 400, 600}, rotation: 90], [box: {0, 0, 200, 300}]]
      document = tmp_path() |> Document.write!(pages) |> open!()

      assert {:ok, [turned, upright]} = PDFium.get_page_sizes(document)
      assert %{width: 600.0, height: 400.0} = turned
      assert %{width: 200.0, height: 300.0} = upright
    end

    test "reports nothing for a document with no pages" do
      document = tmp_path() |> Document.write!([]) |> open!()

      assert {:ok, []} = PDFium.get_page_sizes(document)
    end

    test "reports a closed document" do
      document = open!(@plain)
      PDFium.close_document(document)

      assert {:error, :document_closed} = PDFium.get_page_sizes(document)
    end
  end

  describe "get_annotation_counts/1" do
    test "counts the annotations on each page, in order" do
      {:ok, document} = PDFium.open_document(@annotated)
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
    test "a new one has no pages" do
      output = tmp_path()
      assert {:ok, document} = PDFium.create_document()
      assert {:ok, 0} = PDFium.get_page_count(document)

      assert :ok = PDFium.save(document, output)
      assert {:ok, 0} = PDFium.get_page_count(open!(output))
    end

    test "importing named pages, in the order named" do
      output = tmp_path()
      pages = Enum.map([200, 300, 400], &[box: {0, 0, &1, &1}])
      source = tmp_path() |> Document.write!(pages) |> open!()

      PDFium.with_new_document(fn document ->
        assert :ok = PDFium.import_pages(document, source, [2, 0], 0)
        assert :ok = PDFium.save(document, output)
      end)

      assert {:ok, pages} = PDFium.get_page_sizes(open!(output))
      assert Enum.map(pages, & &1.width) == [400.0, 200.0]
    end

    test "importing every page of one into another" do
      output = tmp_path()
      source = tmp_path() |> Document.write!([[box: {0, 0, 100, 100}], []]) |> open!()

      PDFium.with_new_document(fn document ->
        assert :ok = PDFium.import_pages(document, source, :all, 0)
        assert :ok = PDFium.save(document, output)
      end)

      assert {:ok, 2} = PDFium.get_page_count(open!(output))
    end

    test "importing where the caller asked" do
      output = tmp_path()
      first = tmp_path() |> Document.write!([[box: {0, 0, 100, 100}]]) |> open!()
      second = tmp_path() |> Document.write!([[box: {0, 0, 200, 200}]]) |> open!()

      PDFium.with_new_document(fn document ->
        assert :ok = PDFium.import_pages(document, first, :all, 0)
        assert :ok = PDFium.import_pages(document, second, :all, 0)
        assert :ok = PDFium.save(document, output)
      end)

      assert {:ok, pages} = PDFium.get_page_sizes(open!(output))
      assert Enum.map(pages, & &1.width) == [200.0, 100.0]
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

    test "reporting a closed document" do
      output = tmp_path()
      document = open!(@plain)
      PDFium.close_document(document)

      assert {:error, :document_closed} = PDFium.save(document, output)
    end

    test "reporting an unwritable path" do
      PDFium.with_new_document(fn document ->
        assert {:error, :enoent} =
                 PDFium.save(document, "/nonexistent-directory/out.pdf")
      end)
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

    test "leaves the pages it was not asked about" do
      output = tmp_path()
      assert :ok = write(Toolbox.merge([@annotated, @annotated]), output)
      document = open!(output)

      assert {:ok, :flattened} = PDFium.flatten_page(document, 0)
      assert {:ok, [0, 1]} = PDFium.get_annotation_counts(document)
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
    test "puts the overlay where the matrix says" do
      output = tmp_path()
      # A quarter page of blue in its own bottom left corner, placed into the
      # top right quarter of a page four times its size.
      overlay =
        tmp_path()
        |> Document.write!([[box: {0, 0, 200, 200}, content: "0 0 1 rg 0 0 100 100 re f"]])
        |> open!()

      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]]) |> open!()

      placement = {1.0, 0.0, 0.0, 1.0, 200.0, 200.0}

      assert :ok = PDFium.stamp(document, [{overlay, 0, 0, placement}])
      assert :ok = PDFium.save(document, output)

      assert blue?(colour_at(output, 0.625, 0.625)), "moved into the top right quarter"
      refute blue?(colour_at(output, 0.125, 0.125)), "not left in the bottom left"
    end

    test "scales by the matrix it was given" do
      output = tmp_path()
      overlay = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 400, 400}) |> open!()
      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]]) |> open!()

      assert :ok = PDFium.stamp(document, [{overlay, 0, 0, {0.5, 0.0, 0.0, 0.5, 0.0, 0.0}}])
      assert :ok = PDFium.save(document, output)

      assert blue?(colour_at(output, 0.25, 0.25)), "the quarter it was scaled into"
      refute blue?(colour_at(output, 0.75, 0.75)), "and nothing beyond it"
    end

    test "reads the matrix in the page as displayed, not as written" do
      output = tmp_path()
      # The page is turned a quarter, so the bottom left of the page a reader
      # sees is not the origin the page's own content is written from.
      overlay = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 300, 300}) |> open!()

      document =
        tmp_path() |> Document.write!([[box: {0, 0, 400, 600}, rotation: 90]]) |> open!()

      assert :ok = PDFium.stamp(document, [{overlay, 0, 0, {1.0, 0.0, 0.0, 1.0, 0.0, 0.0}}])
      assert :ok = PDFium.save(document, output)

      assert blue?(colour_at(output, 0.1, 0.1)), "the corner a reader calls bottom left"
    end
  end
end
