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
bumps `LIBPDFIUM_TAG` to the latest tag and `VERSION` to the next patch. Merging
it into `main` runs the `Release` workflow, which builds the artifacts, creates
the GitHub release and publishes the package to hex. Run the workflow by hand to
release outside the schedule:

```sh
gh workflow run update-libpdfium.yaml
```

For any other tag or version, open a pull request that edits the two files by
hand. Merging it releases the same way.

## Running CI steps locally

`ci` builds the NIF for one platform, runs the test suite against it and
returns the archive:

```sh
dagger call ci --platform-name linux/arm64 --abi musl export --path .
```

`dagger check` runs it for all four Linux platforms. The workflows load the
workspace from git rather than from a checkout, and the same works from any
directory:

```sh
dagger --workspace github.com/gmile/pdfium@main check
```

## When a release fails

The `Release` workflow creates the GitHub release before it publishes to hex, so
a failure in the hex step leaves a release behind that a re-run would refuse to
create again. Delete it together with its tag, then re-run the failed job:

```sh
gh release delete v0.1.46 --cleanup-tag --yes
```

```sh
gh run rerun 42028488533 --failed
```

The six archives of any run can be fetched for inspection or for running the
release steps by hand:

```sh
gh run download 42028488533 --dir artifacts
```

## Updating OTP version (for macOS)

```sh
wget https://github.com/erlef/otp_builds/releases/download/OTP-29.1.2/OTP-29.1.2-macos-amd64.tar.gz /tmp
wget https://github.com/erlef/otp_builds/releases/download/OTP-29.1.2/OTP-29.1.2-macos-arm64.tar.gz /tmp

shasum -a 256 /tmp/OTP-29.1.2-macos-amd64.tar.gz
shasum -a 256 /tmp/OTP-29.1.2-macos-arm64.tar.gz

# Then edit custom/build.json by inserting the hashes
```

## Repository settings the workflows rely on

* a GitHub App installed on the repository with write access to contents and
  pull requests; its id is the `GH_APP_ID` variable and its private key the
  `GH_APP_PRIVATE_KEY` secret
* the `HEX_API_KEY` secret for `mix hex.publish`
* required checks named after the CI jobs, one per matrix entry

## Known issues

* Installing the library was tested and will work in macOS and inside Docker images built by Bob. Installing
  currently doesn't work under Elixir installed via package managers, such as via `apk add elixir` for example.

## License

See [LICENSE].
