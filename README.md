## PDFium

Elixir bindings for the pdfium library.

## Installing

Add the dependency:

```elixir
{:pdfium, "~> 0.2"}
```

Or in a script:

```elixir
Mix.install([pdfium: "~> 0.2"])
```

Precompiled NIFs cover OTP 26 and newer on x86_64 and aarch64 Linux, glibc or
musl, and on arm64 macOS. Anywhere else the package compiles from source and
needs a C++ compiler, `make` and `curl`.

## Usage

Open a document:

```elixir
{:ok, document} = PDFium.open_document("file.pdf")
```

Count its pages:

```elixir
{:ok, pages} = PDFium.get_page_count(document)
```

Render a page to a file, with Vix:

```elixir
{:ok, {binary, w, h}} = PDFium.get_page_bitmap(document, 0, 300)
{:ok, image} = Vix.Vips.Image.new_from_binary(binary, w, h, 4, :VIPS_FORMAT_UCHAR)
{:ok, _image} = Image.write(image, "/tmp/sample.png")
```

## Development

Enter the shell, then use mix as usual:

```sh
nix develop
mix compile
mix test
mix dialyzer
mix docs
```

## Running tests

Run the tests for every target this machine can run, and dialyzer:

```sh
nix flake check
```

The visual tests compare renders with the images in `test/fixtures/visual`.
After a change that is meant to draw differently, rewrite them and review the
image diff:

```sh
UPDATE_VISUALS=1 mix test --only visual
```

Build the NIF for a target, or the release archives:

```sh
nix build .#nif-aarch64-linux-musl
nix build .#archives
```

## Releasing

From a clean `main` that matches `origin/main`, with `major`, `minor` or `patch`:

```sh
nix run .#bump -- minor
```

It does what you would by hand:

1. Bump `VERSION` and rename the `[Unreleased]` section of `CHANGELOG.md` to
   `[vX.Y.Z] - YYYY-MM-DD`, with a new empty `[Unreleased]` above it.
2. Commit.
3. Push to `main`.

Once the tests pass, CI publishes the package and its docs to Hex and creates
the GitHub release. A release that failed before its tag was created can be
retried by running the CI workflow on `main`.

Every Monday a workflow opens a pull request that updates libpdfium to its
latest release and bumps `VERSION`. To get one now:

```sh
gh workflow run update-libpdfium.yaml
```

To update to a specific tag, from your machine:

```sh
nix run .#update -- chromium/8152
```

## License

See [LICENSE](https://github.com/gmile/pdfium/blob/main/LICENSE).
