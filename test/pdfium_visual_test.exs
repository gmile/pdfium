defmodule PDFiumVisualTest do
  use ExUnit.Case

  import PDFium.Test.Visual

  alias PDFium.Test.Document

  @moduletag :visual

  @encrypted_r6 Path.expand("fixtures/encrypted-r6-marked.pdf", __DIR__)

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

  test "annotations are drawn, and flattened by the appearance asked for" do
    path = annotated!()
    document = open!(path)
    assert {:ok, [3]} = PDFium.get_annotation_counts(document)
    assert_looks_like(sheet(document), "annotations")

    for usage <- [:display, :print] do
      document = open!(path)
      assert {:ok, :flattened} = PDFium.flatten_page(document, 0, usage)
      assert {:ok, binary} = PDFium.save_to_binary(document)

      flattened = open_binary!(binary)
      assert {:ok, [0]} = PDFium.get_annotation_counts(flattened)
      assert_looks_like(sheet(flattened), "annotations-flattened-#{usage}")
    end
  end

  test "overlays are drawn where the matrix puts them, in the page as displayed" do
    path =
      document!([
        [box: {0, 0, 120, 80}],
        [box: {0, 0, 120, 80}, rotation: 90],
        [box: {50, 30, 170, 110}]
      ])

    upright = open!(document!([[box: {0, 0, 20, 20}, content: mark(0, 0)]]))

    turned =
      open!(document!([[box: {100, 100, 120, 120}, rotation: 90, content: mark(100, 100)]]))

    placements = [
      {upright, 0, 0, {1, 0, 0, 1, 10, 10}},
      {upright, 0, 0, {2, 0, 0, 2, 40, 10}},
      {upright, 0, 0, {0, 1, -1, 0, 110, 10}},
      {upright, 0, 0, {1, 0, 0, 1, 90, 50}},
      {turned, 0, 0, {1, 0, 0, 1, 90, 50}},
      {upright, 0, 1, {1, 0, 0, 1, 10, 10}},
      {turned, 0, 1, {1, 0, 0, 1, 50, 90}},
      {upright, 0, 2, {1, 0, 0, 1, 10, 10}}
    ]

    output = tmp_path()
    assert {:ok, :stamped} = PDFium.stamp(open!(path), placements, output)
    assert_looks_like(sheet(open!(output)), "stamped")

    document = open!(path)
    assert {:ok, :stamped} = PDFium.stamp_in_place(document, placements)
    assert_looks_like(sheet(document), "stamped")
  end

  test "documents are assembled from the pages of others, encrypted ones included" do
    bars = bars!()

    encrypted = open!(@encrypted_r6)
    assert {:ok, 6} = PDFium.get_security_handler_revision(encrypted)
    assert_looks_like(sheet(encrypted), "encrypted-r6-marked")

    assert {:ok, binary} = PDFium.save_to_binary(encrypted, :remove)
    decrypted = open_binary!(binary)
    assert {:ok, nil} = PDFium.get_security_handler_revision(decrypted)
    assert_looks_like(sheet(decrypted), "encrypted-r6-marked")

    source = open!(bars)
    assert {:ok, "Bars"} = PDFium.get_meta_text(source, "Title")

    assert {:ok, binary} =
             PDFium.with_new_document(fn output ->
               with {:ok, :imported} <- PDFium.import_pages(output, source, [2, 0]),
                    {:ok, :imported} <- PDFium.import_pages(output, encrypted, :all, 1),
                    {:ok, :imported} <- PDFium.import_pages(output, source, [1], 3),
                    do: PDFium.save_to_binary(output)
             end)

    assembled = open_binary!(binary)
    assert {:ok, 4} = PDFium.get_page_count(assembled)
    assert_looks_like(sheet(assembled), "assembled")
  end

  defp mark(x, y) do
    "1 0 0 rg #{x} #{y} 5 20 re f " <>
      "0 1 0 rg #{x + 5} #{y + 15} 10 5 re f " <>
      "0 0 1 rg #{x + 5} #{y + 8} 6 4 re f"
  end

  defp content, do: mark(10, 10) <> " 0 g 100 60 10 10 re f"

  defp annotated! do
    document!([
      [
        box: {0, 0, 120, 80},
        content: mark(10, 10),
        annotations: [
          [rect: {40, 40, 60, 60}, flags: 0, content: "1 0 0 rg 0 0 20 20 re f"],
          [rect: {65, 40, 85, 60}, flags: 5, content: "0 1 0 rg 0 0 20 20 re f"],
          [rect: {90, 40, 110, 60}, flags: 4, content: "0 0 1 rg 0 0 20 20 re f"]
        ]
      ]
    ])
  end

  defp bars! do
    pages =
      for count <- 1..3 do
        [
          box: {0, 0, 60, 60},
          content: Enum.map_join(1..count, " ", &"0 g #{&1 * 12} 10 6 40 re f")
        ]
      end

    Document.write!(tmp_path(), pages, Title: "Bars")
  end

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

  defp open_binary!(binary) do
    {:ok, document} = PDFium.load_memory_document(binary)
    on_exit(fn -> PDFium.close_document(document) end)
    document
  end
end
