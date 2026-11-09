defmodule PDFiumVisualTest do
  use ExUnit.Case

  import PDFium.Test.Visual

  alias PDFium.Test.Document

  @moduletag :visual

  test "pages are drawn in their box, turned and cropped" do
    path =
      document!([
        [box: {0, 0, 120, 80}, content: content()],
        [box: {0, 0, 120, 80}, rotation: 90, content: content()],
        [box: {0, 0, 120, 80}, rotation: 180, content: content()],
        [box: {0, 0, 120, 80}, rotation: 270, content: content()],
        [
          box: {50, 30, 170, 110},
          rotation: 90,
          content: mark(60, 40) <> " 0 g 150 90 10 10 re f"
        ],
        [box: {0, 0, 120, 80}, crop: {5, 5, 105, 75}, content: content()]
      ])

    document = open!(path)

    assert {:ok, 6} = PDFium.get_page_count(document)

    assert {:ok, [sizes]} = PDFium.get_page_sizes([document])

    assert Enum.map(sizes, &{&1.width, &1.height}) == [
             {120.0, 80.0},
             {80.0, 120.0},
             {120.0, 80.0},
             {80.0, 120.0},
             {80.0, 120.0},
             {100.0, 70.0}
           ]

    assert {:ok, boxes} = PDFium.get_page_boxes(document)
    assert Enum.map(boxes, & &1.rotation) == [0, 90, 180, 270, 90, 0]

    assert_looks_like(sheet(document), "geometry")
    assert_looks_like(page(document, 0, 144), "geometry-144-dpi")
  end

  defp mark(x, y) do
    "1 0 0 rg #{x} #{y} 5 20 re f " <>
      "0 1 0 rg #{x + 5} #{y + 15} 10 5 re f " <>
      "0 0 1 rg #{x + 5} #{y + 8} 6 4 re f"
  end

  defp content, do: mark(10, 10) <> " 0 g 100 60 10 10 re f"

  defp document!(pages), do: Document.write!(tmp_path(), pages)

  defp tmp_path do
    path = Path.join(System.tmp_dir!(), "pdfium-visual-#{System.unique_integer([:positive])}.pdf")
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp open!(path) do
    {:ok, document} = PDFium.load_document(path)
    on_exit(fn -> PDFium.close_document(document) end)
    document
  end
end
