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

## Developing

The development environment is a Nix shell carrying Erlang, Elixir and the
tools `custom/build-for-mac.sh` fetches its dependencies with:

```sh
nix develop
```

`mise.toml` pins the same Erlang and Elixir for anyone using mise instead.

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

Every Monday the `Update to latest libpdfium` workflow opens a pull request that
bumps `LIBPDFIUM_TAG` and `VERSION`. Merging it into `main` runs the `Release`
workflow, which builds the artifacts, creates the GitHub release and publishes
the package to hex. Run the workflow by hand to release outside the schedule:

```sh
gh workflow run update-libpdfium.yaml
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
     --precompiled output/pdfium-nif-2.18-aarch64-linux-musl-0.1.29.tar.gz \
     --src-dir . \
     --abi musl --platform-name linux/arm64
   ```

## Releasing manually

1. push a branch with a new libpdfium tag and open a pull request for it:

    ```sh
    env GITHUB_TOKEN=(gh auth token) dagger call prepare-release \
      --libpdfium-tag chromium/7506 \
      --actor gmile \
      --github-token env://GITHUB_TOKEN \
      push --branch update-libpdfium

    env GITHUB_TOKEN=(gh auth token) dagger call open-pull-request \
      --head update-libpdfium \
      --github-token env://GITHUB_TOKEN \
      stdout
    ```

2. merge the pull request, then from `main` with the artifacts of its CI run in `artifacts/`:

    ```sh
    env GITHUB_TOKEN=(gh auth token) dagger call github-release \
      --artifacts artifacts \
      --sha (git rev-parse main) \
      --github-token env://GITHUB_TOKEN \
      stdout

    env HEX_API_KEY=483a... dagger call hex-publish \
      --hex-api-key env://HEX_API_KEY \
      stdout
    ```

## Updating OTP version (for macOS)

```sh
wget https://github.com/erlef/otp_builds/releases/download/OTP-29.1.2/OTP-29.1.2-macos-amd64.tar.gz /tmp
wget https://github.com/erlef/otp_builds/releases/download/OTP-29.1.2/OTP-29.1.2-macos-arm64.tar.gz /tmp

shasum -a 256 /tmp/OTP-29.1.2-macos-amd64.tar.gz
shasum -a 256 /tmp/OTP-29.1.2-macos-arm64.tar.gz

# Then edit custom/build.json by inserting the hashes
```

## Known issues

* Installing the library was tested and will work in macOS and inside Docker images built by Bob. Installing
  currently doesn't work under Elixir installed via package managers, such as via `apk add elixir` for example.

## License

See [LICENSE].
