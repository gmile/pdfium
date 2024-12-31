## PDFium

Native bindings for pdfium project

## Installing

* for Mix projects, add the following under `deps` in `mix.exs`:

    ```elixir
    {:pdfium, "~> 0.1"}
    ```

* for single-file Elixir scripts, add the following:

    ```elixir
    Mix.install([pdfium: "~> 0.1"])
    ```

## Usage

1. open a PDF file descriptor:

   ```elixir
   {:ok, document} = PDFium.load_document("file.pdf")
   # => {:ok, #Reference<0.2181297728.2193227786.166499>}
   ```

2. get the number of pages in the file:

   ```elixir
   {:ok, pages} = PDFium.get_page_count(document)
   # => {:ok, 1}
   ```

3. render a page to file:

   ```elixir
   {:ok, ref} = PDFium.load_document("/Users/eugene/Downloads/7ade6db09604a8b41104763c6f16a987.pdf")
   {:ok, binary, w, h} = PDFium.get_page_bitmap(ref, 0, 300) # 300 for DPI
   {:ok, image} = Vix.Vips.Image.new_from_binary(binary, w, h, 4, :VIPS_FORMAT_UCHAR)
   {:ok, _image} = Image.write(image, "/tmp/sample.png")
   ```

## Releasing

1. bump version in `VERSION` file. Run:

   ```sh
   echo -n (awk 'BEGIN{FS=OFS="."} {$NF+=1}1' VERSION) > VERSION
   ```

2. commit and push the change:

   ```sh
   git add VERSION
   git commit --message "Bump library version"
   git push origin main
   ```

3. create a PR from `main` to `stable`. Run:

   ```sh
   gh pr create --base stable --fill
   ```

4. wait until the PR checks are green, then merge the PR

## Known issues

* Installing the library was tested and will work in macOS and inside Docker built by Bob. Installing
  currently doesn't work under Elixir installed via package managers, like `apk add elixir`.

## License

See [LICENSE].
