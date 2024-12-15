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

4. Run:

    ```elixir
    {:ok, document} = PDFium.load_document("/Users/eugene/Downloads/7ade6db09604a8b41104763c6f16a987.pdf")
    {:ok, pages} = PDFium.get_page_count(document)
    pages # => 1
    ```

## Building (locally)

1. Build all targets:

    ```sh
    ./custom/build-all.sh
    ```

2. Upload all targets:

    ```sh
    gh release upload v0.1.0 custom/pdfium-nif-2.17*
    ```

3. Generate checksums:

    ```sh
    mix elixir_make.checksum --all
    ```

4. Commit checksums (???)

5. Push commit

6. Create tag

## Building via dagger

```sh
dagger call \
  precompile --c-src-dir c_src --build-scripts-src-dir custom --plat linux/amd64 \
  export --path output/ --allowParentDirPath
```

## Precompiling

Run:

```sh
mix elixir_make.precompile
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/pdfium>.

## TODO

- [ ] for docker builds consider just using "native" target in the script

## Copyright

Copyright © 2024 Ievgen Pyrogov. See [LICENSE](LICENSE) for further details.
