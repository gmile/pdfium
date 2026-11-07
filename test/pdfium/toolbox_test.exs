defmodule PDFium.ToolboxTest do
  use ExUnit.Case

  alias PDFium.Test.Document
  alias PDFium.Toolbox

  import PDFium.Test.Helpers

  @annotated Path.expand("../fixtures/annotated.pdf", __DIR__)
  @plain Path.expand("../fixtures/test.pdf", __DIR__)
  @encrypted_r5 Path.expand("../fixtures/encrypted-r5.pdf", __DIR__)

  describe "writing with security removed" do
    test "Toolbox.flatten/4 writes a document with nothing to draw" do
      output = tmp_path()
      assert :ok = write(Toolbox.flatten(@encrypted_r5, :display, :remove), output)
      assert revision_of(output) == nil
    end

    test "Toolbox.stamp/4 writes the document without its encryption" do
      output = tmp_path()
      overlay = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 200, 200})

      assert :ok = write(Toolbox.stamp(@encrypted_r5, [{overlay, 0}], :remove), output)
      assert revision_of(output) == nil
    end
  end

  describe "extract_pages/3" do
    setup do
      pages = Enum.map([200, 300, 400, 500], &[box: {0, 0, &1, &1}])

      {:ok, source: tmp_path() |> Document.write!(pages)}
    end

    test "writes the pages it was given", %{source: source} do
      output = tmp_path()
      assert :ok = write(Toolbox.extract_pages(source, [1, 2]), output)

      assert {:ok, pages} = PDFium.get_page_sizes(open!(output))
      assert Enum.map(pages, & &1.width) == [300.0, 400.0]
    end

    test "writes them in the order it was given", %{source: source} do
      output = tmp_path()
      assert :ok = write(Toolbox.extract_pages(source, [3, 0]), output)

      assert {:ok, pages} = PDFium.get_page_sizes(open!(output))
      assert Enum.map(pages, & &1.width) == [500.0, 200.0]
    end

    test "writes a page named twice twice", %{source: source} do
      output = tmp_path()
      assert :ok = write(Toolbox.extract_pages(source, [0, 0]), output)

      assert {:ok, pages} = PDFium.get_page_sizes(open!(output))
      assert Enum.map(pages, & &1.width) == [200.0, 200.0]
    end

    test "keeps what is drawn on the page it took" do
      output = tmp_path()
      source = tmp_path() |> Document.filled({1, 0, 0}, box: {0, 0, 100, 100})

      assert :ok = write(Toolbox.extract_pages(source, [0]), output)

      assert colour_at(output, 0.5, 0.5) == {255, 0, 0}
    end

    test "refuses to extract no pages at all", %{source: source} do
      assert {:error, :no_pages} = Toolbox.extract_pages(source, [])
    end

    test "reports a page that is not there", %{source: source} do
      assert {:error, :import_failed} = Toolbox.extract_pages(source, [9])
    end

    test "reports a document it cannot open" do
      assert {:error, :file} =
               Toolbox.extract_pages("/nonexistent-directory/absent.pdf", [0])
    end
  end

  describe "merge/2" do
    test "writes the documents as one, in order" do
      output = tmp_path()
      first = document!([[box: {0, 0, 100, 100}], [box: {0, 0, 200, 200}]])
      second = document!([[box: {0, 0, 300, 300}]])

      assert :ok = write(Toolbox.merge([first, second]), output)

      assert {:ok, pages} = PDFium.get_page_sizes(open!(output))
      assert Enum.map(pages, & &1.width) == [100.0, 200.0, 300.0]
    end

    test "writes a document given twice twice" do
      output = tmp_path()
      document = document!([[box: {0, 0, 100, 100}]])

      assert :ok = write(Toolbox.merge([document, document]), output)

      assert {:ok, pages} = PDFium.get_page_sizes(open!(output))
      assert length(pages) == 2
    end

    test "keeps what is drawn on each page" do
      output = tmp_path()
      red = tmp_path() |> Document.filled({1, 0, 0}, box: {0, 0, 100, 100})
      blue = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 100, 100})

      assert :ok = write(Toolbox.merge([red, blue]), output)

      assert colour_at(output, 0.5, 0.5, 0) == {255, 0, 0}
      assert colour_at(output, 0.5, 0.5, 1) == {0, 0, 255}
    end

    test "carries a document with no pages without complaint" do
      output = tmp_path()
      empty = document!([])
      page = document!([[box: {0, 0, 100, 100}]])

      assert :ok = write(Toolbox.merge([empty, page, empty]), output)

      assert {:ok, pages} = PDFium.get_page_sizes(open!(output))
      assert Enum.map(pages, & &1.width) == [100.0]
    end

    test "refuses to merge nothing at all" do
      assert {:error, :no_documents} = Toolbox.merge([])
    end

    test "reports a document it cannot open" do
      first = document!([[box: {0, 0, 100, 100}]])

      assert {:error, :file} = Toolbox.merge([first, "/nonexistent-directory/absent.pdf"])
    end
  end

  describe "Toolbox.stamp/3, fitted and centred" do
    test "measures a many-paged overlay by its first page" do
      output = tmp_path()
      # The header and footer of a contract is drawn as one page per page of the
      # contract, and only the first of them is ever drawn over anything here.
      overlay =
        tmp_path()
        |> Document.write!([
          [box: {0, 0, 400, 400}, content: "0 0 1 rg 0 0 400 400 re f"],
          [box: {0, 0, 400, 400}]
        ])

      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]])

      assert :ok = write(Toolbox.stamp(document, [{overlay, 0}]), output)
      assert blue?(colour_at(output, 0.5, 0.5))
    end

    defp corner_overlay(box) do
      {left, bottom, right, top} = box
      width = (right - left) / 2
      height = (top - bottom) / 2

      content = "0 0 1 rg #{left} #{bottom} #{width} #{height} re f"

      tmp_path() |> Document.write!([[box: box, content: content]])
    end

    test "draws the overlay where it was drawn" do
      output = tmp_path()
      box = {0, 0, 400, 400}
      document = tmp_path() |> Document.write!([[box: box]])

      assert :ok = write(Toolbox.stamp(document, [{corner_overlay(box), 0}]), output)

      assert blue?(colour_at(output, 0.25, 0.25)), "the corner it was drawn in"
      refute blue?(colour_at(output, 0.75, 0.75)), "the corner across from it"
    end

    test "keeps the content the page already had" do
      output = tmp_path()
      box = {0, 0, 400, 400}
      document = tmp_path() |> Document.filled({1, 0, 0}, box: box)

      assert :ok = write(Toolbox.stamp(document, [{corner_overlay(box), 0}]), output)

      assert blue?(colour_at(output, 0.25, 0.25))
      assert colour_at(output, 0.75, 0.75) == {255, 0, 0}
    end

    test "draws over the page it was paired with and no other" do
      output = tmp_path()
      box = {0, 0, 400, 400}
      pages = [[box: box], [box: box], [box: box]]
      document = tmp_path() |> Document.write!(pages)

      assert :ok = write(Toolbox.stamp(document, [{corner_overlay(box), 1}]), output)

      refute blue?(colour_at(output, 0.25, 0.25, 0))
      assert blue?(colour_at(output, 0.25, 0.25, 1))
      refute blue?(colour_at(output, 0.25, 0.25, 2))
    end

    test "draws one overlay over as many pages as it is given" do
      output = tmp_path()
      box = {0, 0, 400, 400}
      document = tmp_path() |> Document.write!([[box: box], [box: box]])
      overlay = corner_overlay(box)

      assert :ok = write(Toolbox.stamp(document, [{overlay, 0}, {overlay, 1}]), output)

      assert blue?(colour_at(output, 0.25, 0.25, 0))
      assert blue?(colour_at(output, 0.25, 0.25, 1))
    end

    test "stacks overlays on one page in the order given" do
      output = tmp_path()
      box = {0, 0, 400, 400}
      document = tmp_path() |> Document.write!([[box: box]])

      under = tmp_path() |> Document.filled({0, 1, 0}, box: box)
      over = tmp_path() |> Document.filled({1, 0, 0}, box: box)

      assert :ok = write(Toolbox.stamp(document, [{under, 0}, {over, 0}]), output)

      assert colour_at(output, 0.5, 0.5) == {255, 0, 0}
    end

    test "places against a box that does not start at the origin" do
      output = tmp_path()
      box = {-100, -100, 300, 300}
      document = tmp_path() |> Document.write!([[box: box]])
      overlay = corner_overlay({0, 0, 400, 400})

      assert :ok = write(Toolbox.stamp(document, [{overlay, 0}]), output)

      assert blue?(colour_at(output, 0.25, 0.25))
      refute blue?(colour_at(output, 0.75, 0.75))
    end

    test "turns the overlay with the page it goes over" do
      output = tmp_path()
      box = {0, 0, 400, 600}
      document = tmp_path() |> Document.write!([[box: box, rotation: 90]])

      overlay = corner_overlay({0, 0, 600, 400})

      assert :ok = write(Toolbox.stamp(document, [{overlay, 0}]), output)

      assert blue?(colour_at(output, 0.25, 0.25))
      refute blue?(colour_at(output, 0.75, 0.75))
    end

    test "turns the overlay with a page turned half or three quarters" do
      for rotation <- [180, 270] do
        output = tmp_path()
        {width, height} = if rotation == 180, do: {400, 600}, else: {600, 400}

        document =
          tmp_path() |> Document.write!([[box: {0, 0, width, height}, rotation: rotation]])

        overlay = corner_overlay({0, 0, 400, 600})

        assert :ok = write(Toolbox.stamp(document, [{overlay, 0}]), output)
        assert blue?(colour_at(output, 0.25, 0.25)), "rotation #{rotation}"
        refute blue?(colour_at(output, 0.75, 0.75)), "rotation #{rotation}"
      end
    end

    test "places against the crop box when the page has one" do
      output = tmp_path()
      page = [box: {0, 0, 400, 400}, crop: {100, 100, 300, 300}]
      document = tmp_path() |> Document.write!([page])
      overlay = corner_overlay({0, 0, 200, 200})

      assert {:ok, [%{width: 200.0, height: 200.0}]} =
               PDFium.with_document(document, &PDFium.get_page_sizes/1)

      assert :ok = write(Toolbox.stamp(document, [{overlay, 0}]), output)
      assert blue?(colour_at(output, 0.25, 0.25))
      refute blue?(colour_at(output, 0.75, 0.75))
    end

    test "scales an overlay of a different shape to fit, centred" do
      output = tmp_path()
      box = {0, 0, 400, 400}
      document = tmp_path() |> Document.write!([[box: box]])
      overlay = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 400, 800})

      assert :ok = write(Toolbox.stamp(document, [{overlay, 0}]), output)

      assert blue?(colour_at(output, 0.5, 0.5)), "the middle it was centred on"
      refute blue?(colour_at(output, 0.1, 0.5)), "the strip left bare beside it"
      refute blue?(colour_at(output, 0.9, 0.5)), "and the one on the other side"
    end

    test "reports a page that is not there" do
      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]])

      assert {:error, :page_load_failed} =
               Toolbox.stamp(document, [{corner_overlay({0, 0, 400, 400}), 9}])
    end

    test "reports an overlay with no pages" do
      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]])
      overlay = tmp_path() |> Document.write!([])

      assert {:error, :page_load_failed} = Toolbox.stamp(document, [{overlay, 0}])
    end

    test "reports an overlay it cannot open" do
      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]])
      absent = "/nonexistent-directory/absent.pdf"

      assert {:error, :file} = Toolbox.stamp(document, [{absent, 0}])
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

      assert :ok = write(Toolbox.overlay(document, overlay), output)

      assert colour_at(output, 0.5, 0.5, 0) == {255, 0, 0}, "page one takes overlay page one"
      assert colour_at(output, 0.5, 0.5, 1) == {0, 0, 255}, "page two takes overlay page two"
    end

    test "refuses an overlay rendered for a document of another length" do
      document = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}], [box: {0, 0, 400, 400}]])
      overlay = tmp_path() |> Document.write!([[box: {0, 0, 400, 400}]])

      assert {:error, :page_count_mismatch} = Toolbox.overlay(document, overlay)
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
      assert :ok = write(Toolbox.overlay(document, overlay), from_file)

      assert {:ok, stamped} =
               Toolbox.overlay(document, {:bytes, File.read!(overlay)})

      from_contents = tmp_path()
      File.write!(from_contents, stamped)

      assert colour_at(from_contents, 0.5, 0.5, 0) == colour_at(from_file, 0.5, 0.5, 0)
      assert colour_at(from_contents, 0.5, 0.5, 1) == colour_at(from_file, 0.5, 0.5, 1)
    end

    test "answers with a document rather than writing one" do
      overlay = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 400, 400})
      document = tmp_path() |> Document.filled({1, 0, 0}, box: {0, 0, 400, 400})

      assert {:ok, stamped} = Toolbox.overlay({:bytes, File.read!(document)}, overlay)
      assert String.starts_with?(stamped, "%PDF-")
      assert {:ok, 1} = PDFium.with_document({:bytes, stamped}, &PDFium.get_page_count/1)
    end

    test "refuses contents that are not a document" do
      document = tmp_path() |> Document.filled({1, 0, 0}, box: {0, 0, 400, 400})

      assert {:error, :format} = Toolbox.overlay(document, {:bytes, "not a pdf"})
    end

    test "draws nothing when given nothing" do
      output = tmp_path()
      document = tmp_path() |> Document.filled({1, 0, 0}, box: {0, 0, 400, 400})

      assert :ok = write(Toolbox.stamp(document, []), output)

      assert colour_at(output, 0.5, 0.5) == {255, 0, 0}
    end
  end

  describe "render_pages!/2" do
    test "renders each page as it is taken" do
      pages = [
        [box: {0, 0, 10, 10}, content: "1 0 0 rg 0 0 10 10 re f"],
        [box: {0, 0, 10, 10}, content: "0 0 1 rg 0 0 10 10 re f"]
      ]

      assert [{red, 10, 10}, {blue, 10, 10}] =
               Enum.to_list(Toolbox.render_pages!(document!(pages), 72))

      assert <<255, 0, 0, _::binary>> = red
      assert <<0, 0, 255, _::binary>> = blue
    end

    test "stops when the reader does" do
      pages = [[box: {0, 0, 10, 10}], [box: {0, 0, 10, 10}]]

      assert [{_pixels, 10, 10}] = Enum.take(Toolbox.render_pages!(document!(pages), 72), 1)
    end
  end

  describe "flatten/2" do
    test "renders annotations into the page and writes the result" do
      output = tmp_path()
      assert :ok = write(Toolbox.flatten(@annotated), output)

      assert {:ok, 1} = PDFium.get_page_count(open!(output))
    end

    test "answers with the document when there is nothing to flatten" do
      {:ok, pages} = PDFium.with_document(@plain, &PDFium.get_page_count/1)

      assert {:ok, flattened} = Toolbox.flatten(@plain)
      assert {:ok, ^pages} = PDFium.with_document({:bytes, flattened}, &PDFium.get_page_count/1)
    end

    test "is idempotent" do
      assert {:ok, once} = Toolbox.flatten(@annotated)
      assert {:ok, twice} = Toolbox.flatten({:bytes, once})
      assert {:ok, [0]} = PDFium.with_document({:bytes, twice}, &PDFium.get_annotation_counts/1)
    end

    test "reports a document it cannot open" do
      assert {:error, :file} = Toolbox.flatten("/nonexistent-directory/absent.pdf")
    end
  end

  describe "jobs given documents as contents" do
    test "flattens contents to a file as it would a path" do
      output = tmp_path()
      assert :ok = write(Toolbox.flatten({:bytes, File.read!(@annotated)}), output)
      assert {:ok, 1} = PDFium.get_page_count(open!(output))
    end

    test "flattens, answering with the document" do
      assert {:ok, flattened} = Toolbox.flatten({:bytes, File.read!(@annotated)})
      assert String.starts_with?(flattened, "%PDF-")
      assert {:ok, 1} = PDFium.with_document({:bytes, flattened}, &PDFium.get_page_count/1)
    end

    test "merges contents alongside paths, answering with the document" do
      first = document!([[box: {0, 0, 100, 100}], [box: {0, 0, 200, 200}]])
      second = document!([[box: {0, 0, 300, 300}]])

      assert {:ok, merged} = Toolbox.merge([{:bytes, File.read!(first)}, second])

      assert {:ok, pages} = PDFium.with_document({:bytes, merged}, &PDFium.get_page_sizes/1)
      assert Enum.map(pages, & &1.width) == [100.0, 200.0, 300.0]
    end

    test "refuses to merge nothing" do
      assert {:error, :no_documents} = Toolbox.merge([])
    end

    test "extracts pages, answering with the document" do
      source = document!(Enum.map([200, 300, 400, 500], &[box: {0, 0, &1, &1}]))

      assert {:ok, extracted} =
               Toolbox.extract_pages({:bytes, File.read!(source)}, [1, 2])

      assert {:ok, pages} = PDFium.with_document({:bytes, extracted}, &PDFium.get_page_sizes/1)
      assert Enum.map(pages, & &1.width) == [300.0, 400.0]
    end

    test "stamps from contents, drawing what it would have from files" do
      output = tmp_path()
      document = tmp_path() |> Document.filled({1, 0, 0}, box: {0, 0, 400, 400})
      overlay = tmp_path() |> Document.filled({0, 0, 1}, box: {0, 0, 200, 200})

      assert :ok = write(Toolbox.stamp(document, [{overlay, 0}]), output)

      assert {:ok, stamped} =
               Toolbox.stamp({:bytes, File.read!(document)}, [
                 {{:bytes, File.read!(overlay)}, 0}
               ])

      from_contents = tmp_path()
      File.write!(from_contents, stamped)

      assert colour_at(from_contents, 0.5, 0.5) == colour_at(output, 0.5, 0.5)
    end
  end
end
