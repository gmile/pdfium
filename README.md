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

The development environment is a Nix shell carrying Erlang, Elixir, a C++
compiler and `gh`:

```sh
nix develop
```

CI pushes everything it builds to the `gmile` Cachix cache, the musl Erlang
among it. To download those instead of building them, trust the cache once:

```sh
cachix use gmile
```

`mix compile` builds the NIF for this machine through the `Makefile`, which
downloads the libpdfium archive for the `@libpdfium` tag in `mix.exs` and
compiles `c_src/pdfium_nif.cpp` against it and the Fine headers from hex. This
is also what a user of the package gets when no precompiled NIF matches their
platform.

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
bumps `@libpdfium` and `@version` in `mix.exs` and the archive hashes in
`nix/libpdfium.nix`. Merging it into `main` runs the `Release` workflow, which
builds the archives on a Linux and a macOS runner, creates the GitHub release
and publishes the package to hex. Run the workflow by hand to
release outside the schedule:

```sh
gh workflow run update-libpdfium.yaml
```

For any other tag, run the same app the workflow runs with the tag as its
argument:

```sh
nix run .#update -- chromium/8138
```

Every push to `main` that touches `mix.exs` is released, so bump `@version`
with it.

## Running CI steps locally

The flake builds the NIF for every Linux target from any Linux machine with
the cross toolchains of nixpkgs, and the macOS one on a Mac:

```sh
nix build .#nif-aarch64-linux-musl
```

The targets are `aarch64-linux-gnu`, `aarch64-linux-musl`, `x86_64-linux-gnu`,
`x86_64-linux-musl` and `aarch64-apple-darwin`. `nix build` alone builds the
one for this machine, and `nix build .#archives` the tarballs this machine can
build. Nix caches every derivation by its inputs, so a NIF is rebuilt only when
`c_src/`, `mix.exs` or the toolchain change, and CI keeps the store between
runs with `cache-nix-action`.

Every workflow step is a flake app, so it runs the same way on a runner and
here:

```sh
nix run .#test-aarch64-linux-musl
nix run .#release
nix run .#update
```

`test-<target>` puts that target's NIF in `priv/` and runs `mix test` on an
Erlang built against the same libc, so a musl target runs on a musl BEAM from
`pkgsMusl`. A system only has the test apps for the targets it can run: both of
its Linux targets, or the macOS one. CI runs each on a runner of its kind.
`release` creates the GitHub release from a directory of archives and publishes
the package to hex. `update` moves `mix.exs` and `nix/libpdfium.nix` to the
latest libpdfium, bumps the version, pushes the `update-libpdfium` branch and
opens the pull request.

## When a release fails

Releases are immutable, so a tag can never be reused, not even after deleting
the release. Whatever failed, the way forward is another pull request bumping
`@version` in `mix.exs` to the next patch. The same holds for a change to that
file that forgot to bump the version: the release run goes red once and the
next bump releases normally.

The archives of any run can be fetched for inspection:

```sh
gh run download 42028488533 --dir artifacts
```

## Repository settings the workflows rely on

* a GitHub App installed on the repository with write access to contents and
  pull requests; its id is the `GH_APP_ID` variable and its private key the
  `GH_APP_PRIVATE_KEY` secret
* the `HEX_API_KEY` secret for `mix hex.publish`
* the `CACHIX_AUTH_TOKEN` secret, a write token for the `gmile` Cachix cache
* required checks named after the CI jobs, one per matrix entry
* immutable releases, which is why a failed release is followed by a bump

## Known issues

* Installing the library was tested and will work in macOS and inside Docker images built by Bob. Installing
  currently doesn't work under Elixir installed via package managers, such as via `apk add elixir` for example.

## License

See [LICENSE].
