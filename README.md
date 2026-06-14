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

Releases are driven from the `main` branch by the GitHub Actions `Release` workflow.

The workflow can be run manually, and it also runs on a weekly cron. On cron, it checks the latest
`bblanchon/pdfium-binaries` Chromium tag and exits without publishing when `LIBPDFIUM_TAG` is already
current.

Manual release:

1. open the `Release` workflow in GitHub Actions.
2. optionally provide a package version and libpdfium tag.
3. run the workflow.

The workflow prepares a release commit on `main`, builds all Linux and macOS artifacts, commits
`checksum.exs`, tags the release, creates the GitHub release, and publishes the Hex package.

Local publishing is also possible when release artifacts already exist locally:

```sh
GITHUB_TOKEN=$(gh auth token) HEX_API_KEY=483a... dagger call publish-release \
  --ref main \
  --artifacts ./artifacts \
  --actor gmile \
  --github-token env://GITHUB_TOKEN \
  --hex-api-key env://HEX_API_KEY
```

## Running CI steps locally

1. Prepare:

   ```sh
   mkdir output
   ```

1. Build:

   ```sh
   dagger call \
     precompile --src-dir . --platform-name linux/arm64 --abi musl \
     export --path output/ --allowParentDirPath
   ```

2. Test:

   ```sh
   dagger call test \
     --precompiled output/pdfium-nif-2.17-aarch64-linux-musl-0.1.23.tar.gz \
     --src-dir . \
     --abi musl --platform-name linux/arm64
   ```

## Updating OTP version (for macOS)

```sh
curl -L --fail --output /tmp/OTP-29.0.2-macos-amd64.tar.gz https://github.com/erlef/otp_builds/releases/download/OTP-29.0.2/OTP-29.0.2-macos-amd64.tar.gz
curl -L --fail --output /tmp/OTP-29.0.2-macos-arm64.tar.gz https://github.com/erlef/otp_builds/releases/download/OTP-29.0.2/OTP-29.0.2-macos-arm64.tar.gz

shasum -a 256 /tmp/OTP-29.0.2-macos-amd64.tar.gz
shasum -a 256 /tmp/OTP-29.0.2-macos-arm64.tar.gz

# Then edit custom/builds.json by updating the OTP URLs and hashes
```

## Known issues

* Installing the library was tested and will work in macOS and inside Docker images built by Bob. Installing
  currently doesn't work under Elixir installed via package managers, such as via `apk add elixir` for example.

## License

See [LICENSE].
