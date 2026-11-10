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

Every Monday a workflow opens a pull request that updates libpdfium and bumps
the version. Merging it releases. To do that now:

```sh
gh workflow run update-libpdfium.yaml
```

To update to a specific libpdfium tag:

```sh
nix run .#update -- chromium/8138
```

Every push to `main` that touches `mix.exs` releases, so bump `@version` with
it. If a release fails, bump `@version` again. Tags cannot be reused.

## Repository settings

* a GitHub App with write access to contents and pull requests: `GH_APP_ID`
  variable and `GH_APP_PRIVATE_KEY` secret
* a `hex` environment, which the workload identity of the `pdfium` package on
  hex.pm trusts for `release.yaml`
* required checks named after the CI jobs
* immutable releases

## Known issues

* Installing works on macOS and in Docker images built by Bob. It does not work
  with an Elixir from a package manager, such as `apk add elixir`.

## License

See [LICENSE](https://github.com/gmile/pdfium/blob/main/LICENSE).
