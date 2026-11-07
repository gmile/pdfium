defmodule PDFium.Test.Helpers do
  import ExUnit.Callbacks, only: [on_exit: 1]

  alias PDFium.Test.Document

  def tmp_path do
    path = Path.join(System.tmp_dir!(), "pdfium-test-#{System.unique_integer([:positive])}.pdf")
    on_exit(fn -> File.rm(path) end)
    path
  end

  def document!(pages), do: tmp_path() |> Document.write!(pages)

  def write({:ok, binary}, path), do: File.write(path, binary)
  def write(error, _path), do: error

  def open!(path) do
    {:ok, document} = PDFium.open_document(path)
    on_exit(fn -> PDFium.close_document(document) end)
    document
  end

  def revision_of(path) do
    {:ok, revision} = PDFium.get_security_handler_revision(open!(path))
    revision
  end

  def colour_at(path, across, up, page \\ 0) do
    document = open!(path)
    {:ok, {bitmap, width, height}} = PDFium.get_page_bitmap(document, page, 72)

    x = trunc(across * width)
    y = height - trunc(up * height) - 1
    offset = (y * width + x) * 4

    <<_::binary-size(^offset), red::8, green::8, blue::8, _alpha::8, _rest::binary>> = bitmap

    {red, green, blue}
  end

  def blue?({red, green, blue}), do: blue > 200 and red < 100 and green < 100
end
