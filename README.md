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

The development environment is a Nix shell carrying Erlang, Elixir, zig, the
Dagger CLI at the version the module pins and `gh`:

```sh
nix develop
```

`mix compile` builds the NIF for this machine with `zig build`, driven by
`build.zig`, which fetches the libpdfium archive and the Fine headers declared in
`build.zig.zon`.

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
bumps the libpdfium archives and the version in `build.zig.zon`. Merging
it into `main` runs the `Release` workflow, which builds the artifacts, creates
the GitHub release and publishes the package to hex. Run the workflow by hand to
release outside the schedule:

```sh
gh workflow run update-libpdfium.yaml
```

For any other tag or version, open a pull request that sets `.version` in
`build.zig.zon` by hand and points it at the archives of that tag with
`zig fetch --save`. Every change to that file is released, so bump the version
with it. Merging releases the same way.

## Running CI steps locally

`ci` builds the NIF for one target, runs the test suite against it where the
target can run in a container, and returns the archive:

```sh
dagger call ci --target aarch64-linux-musl archive export --path .
```

The targets are `aarch64-linux-gnu`, `aarch64-linux-musl`, `x86_64-linux-gnu`,
`x86_64-linux-musl`, `aarch64-apple-darwin` and `x86_64-apple-darwin`, all
compiled with zig in one image. The macOS ones are only built, so `mix test` on
a Mac is their check. `dagger check` runs all six. The workflows load the workspace from git
rather than from a checkout, and the same works from any directory:

```sh
dagger --workspace github.com/gmile/pdfium@main check
```

CI keeps zig's cache per target. After changing the zig version, warm the
caches on `main` once so pull requests start from them:

```sh
gh workflow run ci.yaml --ref main
```

## When a release fails

Releases are immutable, so a tag can never be reused, not even after deleting
the release. Whatever failed, the way forward is another pull request bumping
`.version` in `build.zig.zon` to the next patch. The same holds for a change to
that file that forgot to bump the version: the release run goes red once and
the next bump releases normally.

The six archives of any run can be fetched for inspection:

```sh
gh run download 42028488533 --dir artifacts
```

## Repository settings the workflows rely on

* a GitHub App installed on the repository with write access to contents and
  pull requests; its id is the `GH_APP_ID` variable and its private key the
  `GH_APP_PRIVATE_KEY` secret
* the `HEX_API_KEY` secret for `mix hex.publish`
* required checks named after the CI jobs, one per matrix entry
* immutable releases, which is why a failed release is followed by a bump

## Known issues

* Installing the library was tested and will work in macOS and inside Docker images built by Bob. Installing
  currently doesn't work under Elixir installed via package managers, such as via `apk add elixir` for example.

## License

See [LICENSE].
