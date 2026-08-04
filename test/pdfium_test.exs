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

    test "measures a string that is only whitespace", %{font: font} do
      # Nothing inked anchors this measurement, so summing glyph extents answers
      # zero for a single space and loses one space from every longer run.
      # Callers that measure the gaps between words as strings in their own right
      # would be told there are no gaps.
      assert {:ok, widths} = PDFium.measure_text(font, 12.0, [" ", "  ", "   "])

      assert_widths(widths, [3.0, 6.0, 9.0])
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

  describe "draw_text/5" do
    setup do
      {:ok, font} = PDFium.load_font(File.read!(Path.expand("fixtures/measuring.ttf", __DIR__)))

      {:ok, font: font}
    end

    # The bitmap runs top down and a page runs bottom up, so a row has to be
    # turned back around before it can be compared with the baseline asked for.
    defp ink_box(path) do
      {:ok, document} = PDFium.load_document(path)

      try do
        {:ok, bitmap, width, height} = PDFium.get_page_bitmap(document, 0, 72)

        {box, _index} =
          for <<r::8, g::8, b::8, _a::8 <- bitmap>>, reduce: {nil, 0} do
            {box, index} ->
              if div(r + g + b, 3) < 200 do
                x = rem(index, width)
                y = height - div(index, width) - 1

                case box do
                  nil -> {{x, y, x, y}, index + 1}
                  {x0, y0, x1, y1} -> {{min(x0, x), min(y0, y), max(x1, x), max(y1, y)}, index + 1}
                end
              else
                {box, index + 1}
              end
          end

        box
      after
        PDFium.close_document(document)
      end
    end

    test "puts the pen where it was told to", %{font: font, output: output} do
      assert {:ok, :drawn} = PDFium.draw_text(font, 48.0, {300, 300}, [{"A", 100, 150}], output)

      assert {x0, y0, _x1, _y1} = ink_box(output)

      # The glyph fills its cell and has no side bearings, so its corner is the pen.
      assert_in_delta x0, 100, 2
      assert_in_delta y0, 150, 2
    end

    test "keeps the placements apart", %{font: font, output: output} do
      placements = [{"A", 40, 60}, {"A", 40, 200}]

      assert {:ok, :drawn} = PDFium.draw_text(font, 24.0, {300, 300}, placements, output)

      assert {_x0, y0, _x1, y1} = ink_box(output)

      assert y1 - y0 > 140, "two baselines 140 apart should span at least that far"
    end

    test "writes a page of the size it was given", %{font: font, output: output} do
      assert {:ok, :drawn} = PDFium.draw_text(font, 12.0, {200, 400}, [{"A", 10, 10}], output)

      {:ok, document} = PDFium.load_document(output)
      {:ok, _bitmap, width, height} = PDFium.get_page_bitmap(document, 0, 72)
      PDFium.close_document(document)

      assert {width, height} == {200, 400}
    end

    test "writes one page however many times it is called", %{font: font, output: output} do
      # The page is built inside the font's own document, so failing to take it
      # back out would leave the next overlay carrying every page drawn before it.
      for _ <- 1..5 do
        assert {:ok, :drawn} = PDFium.draw_text(font, 12.0, {100, 100}, [{"A", 10, 10}], output)
      end

      {:ok, document} = PDFium.load_document(output)
      assert {:ok, 1} = PDFium.get_page_count(document)
      PDFium.close_document(document)
    end

    test "draws nothing when given nothing", %{font: font, output: output} do
      assert {:ok, :drawn} = PDFium.draw_text(font, 12.0, {100, 100}, [], output)

      assert ink_box(output) == nil
    end

    test "still measures after drawing", %{font: font, output: output} do
      assert {:ok, :drawn} = PDFium.draw_text(font, 12.0, {100, 100}, [{"A", 10, 10}], output)

      assert {:ok, [width]} = PDFium.measure_text(font, 12.0, ["A"])
      assert_in_delta width, 6.0, 0.0001
    end

    test "reports a closed font", %{font: font, output: output} do
      assert :ok = PDFium.close_font(font)

      assert {:error, :font_closed} =
               PDFium.draw_text(font, 12.0, {100, 100}, [{"A", 10, 10}], output)
    end

    test "reports placements that do not line up", %{font: font, output: output} do
      assert {:error, :placement_mismatch} =
               PDFium.NIF.draw_text(font, 12.0, 100.0, 100.0, ["A", "B"], [10.0], [10.0], output)
    end
  end
end
