defmodule PDFiumTest do
  use ExUnit.Case

  @annotated Path.expand("fixtures/annotated.pdf", __DIR__)
  @plain Path.expand("../custom/test.pdf", __DIR__)

  setup do
    output = Path.join(System.tmp_dir!(), "pdfium-test-#{System.unique_integer([:positive])}.pdf")
    on_exit(fn -> File.rm(output) end)

    {:ok, output: output}
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

  describe "fonts" do
    # measuring.ttf is built for these tests and contains no third party
    # outlines. Its em is 1000 units and its advances are round numbers, so the
    # widths below are stated rather than derived:
    #
    #   A 500   B 250   I 100   space 250   ę 600   .notdef 500
    #
    # At 12pt one unit is 0.012pt, so "AB" is 9.0 and nothing has to be
    # approximated.
    @font Path.expand("fixtures/measuring.ttf", __DIR__)

    setup do
      {:ok, font} = PDFium.load_font(File.read!(@font))
      on_exit(fn -> PDFium.close_font(font) end)

      {:ok, font: font}
    end

    # PDFium works in single precision, so the values come back a hair off.
    defp assert_widths(widths, expected) do
      assert length(widths) == length(expected)

      Enum.zip(widths, expected)
      |> Enum.each(fn {actual, want} -> assert_in_delta actual, want, 0.0001 end)
    end

    test "measures the advance of each string, in order", %{font: font} do
      assert {:ok, widths} = PDFium.measure_text(font, 12.0, ["A", "AB", "ABI"])

      assert_widths(widths, [6.0, 9.0, 10.2])
    end

    test "scales with the font size", %{font: font} do
      assert {:ok, at_12} = PDFium.measure_text(font, 12.0, ["A"])
      assert {:ok, at_24} = PDFium.measure_text(font, 24.0, ["A"])

      assert_widths(at_12, [6.0])
      assert_widths(at_24, [12.0])
    end

    test "measures the advance rather than the inked extent", %{font: font} do
      # A space draws nothing, so an ink measurement would leave it out.
      assert {:ok, widths} = PDFium.measure_text(font, 12.0, ["A "])

      assert_widths(widths, [9.0])
    end

    test "measures characters outside latin-1", %{font: font} do
      # ę is 600 units where .notdef is 500. A simple, single byte encoded font
      # would fall back to .notdef here and quietly answer 6.0.
      assert {:ok, widths} = PDFium.measure_text(font, 12.0, ["ę"])

      assert_widths(widths, [7.2])
    end

    test "gives the same answer however often it is asked", %{font: font} do
      # Each measurement builds a scratch page. Were those left behind the
      # document would grow by one for every string ever measured.
      widths =
        for _ <- 1..200 do
          assert {:ok, [width]} = PDFium.measure_text(font, 12.0, ["AB"])
          width
        end

      assert [single] = Enum.uniq(widths)
      assert_in_delta single, 9.0, 0.0001
    end

    test "returns nothing for no strings", %{font: font} do
      assert {:ok, []} = PDFium.measure_text(font, 12.0, [])
    end

    test "reports a closed font", %{font: font} do
      assert :ok = PDFium.close_font(font)

      assert {:error, :font_closed} = PDFium.measure_text(font, 12.0, ["A"])
    end

    test "closing twice is harmless", %{font: font} do
      assert :ok = PDFium.close_font(font)
      assert :ok = PDFium.close_font(font)
    end

    test "reports data that is not a font" do
      assert {:error, :font_load_failed} = PDFium.load_font("not a font")
    end
  end
end
