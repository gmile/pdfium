# PDFium

Bindings to [PDFium](https://pdfium.googlesource.com/pdfium/). Uses statically compiled library https://github.com/bblanchon/pdfium-binaries.

## Installation

The package can be installed by adding `pdfium` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pdfium, "~> 0.1"}
  ]
end
```

## Development

1. Clean-up `_build` directory. Run:

    ```sh
    rm -fr _build
    ```

2. For macOS, run:

    ```sh
    iex -S mix do clean + compile
    ```

3. For Alpine Linux:

    ```sh
    docker run --interactive --tty --workdir /pdfium --volume $(pwd):/pdfium alpine:3.21 ash
    ```

    or for x86_64 platform:

    ```sh
    docker run --interactive --tty --workdir /pdfium --volume $(pwd):/pdfium --platform linux/amd64 alpine:3.21 ash
    ```

    then:

    ```sh
    apk add build-base curl tar elixir
    rm _build deps # just in case
    mix do local.rebar --force + local.hex --force
    ```

    and:

    ```sh
    mix elixir_make.precompile
    ```

    or:

    ```sh
    iex -S mix # will compile
    ```

4. Run:

    ```elixir
    {:ok, document} = PDFium.load_document("/Users/eugene/Downloads/7ade6db09604a8b41104763c6f16a987.pdf")
    {:ok, pages} = PDFium.get_page_count(document)
    pages # => 1
    ```

## Building

Prepare linux builders:

```sh
docker build --platform=linux/amd64 --load --tag pdfium-musl-builder - < Dockerfile.musl
docker build --platform=linux/arm64 --load --tag pdfium-glibc-builder - < Dockerfile.glibc
docker build --platform=linux/amd64 --load --tag pdfium-glibc-builder - < Dockerfile.glibc
```

# for docker builds consider "native" target

```sh
./build-for-mac.sh macos amd64 27.2
./build-for-mac.sh macos arm64 27.2

docker build --platform=linux/arm64 --load --tag pdfium-musl-builder - < Dockerfile.musl
docker run --workdir=/pdfium-build --platform=linux/arm64 --mount type=bind,source=(pwd),target=/pdfium-build pdfium-musl-builder ./build-for-linux.sh linux-musl armv8-a 27.2

docker build --platform=linux/amd64 --load --tag pdfium-musl-builder - < Dockerfile.musl
docker run --workdir=/pdfium-build --platform=linux/amd64 --mount type=bind,source=(pwd),target=/pdfium-build pdfium-musl-builder ./build-for-linux.sh linux-musl x86-64 27.2

docker build --platform=linux/arm64 --load --tag pdfium-glibc-builder - < Dockerfile.glibc
docker run --workdir=/pdfium-build --platform=linux/arm64 --mount type=bind,source=(pwd),target=/pdfium-build pdfium-glibc-builder ./build-for-linux.sh linux armv8-a 27.2

docker build --platform=linux/amd64 --load --tag pdfium-glibc-builder - < Dockerfile.glibc
docker run --workdir=/pdfium-build --platform=linux/amd64 --mount type=bind,source=(pwd),target=/pdfium-build pdfium-glibc-builder ./build-for-linux.sh linux x86-64 27.2
```

## Precompiling

Run:

```sh
mix elixir_make.precompile
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/pdfium>.

## Copyright

Copyright © 2024 Ievgen Pyrogov. See [LICENSE](LICENSE) for further details.
