defmodule PDFium do
  @on_load :load_nif

  def load_nif do
    path = :filename.join(:code.priv_dir(:pdfium), ~c"pdfium_nif")
    :erlang.load_nif(path, 0)
  end

  def load_document(_filename), do: :erlang.nif_error(:nif_not_loaded)

  def get_page_count(_document), do: :erlang.nif_error(:nif_not_loaded)

  def get_page_bitmap(_document, _page_number, _dpi), do: :erlang.nif_error(:nif_not_loaded)

  def test do
    {:ok, ref} = PDFium.load_document("/Users/eugene/Downloads/7ade6db09604a8b41104763c6f16a987.pdf")
    {:ok, binary, w, h} = PDFium.get_page_bitmap(ref, 0, 300) # 300 for DPI
    {:ok, image} = Vix.Vips.Image.new_from_binary(binary, w, h, 4, :VIPS_FORMAT_UCHAR)
    Image.write(image, "/tmp/sample.png")
  end
end
