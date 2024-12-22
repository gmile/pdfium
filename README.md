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

## Releasing

Using local computer:

1. Update package version in `VERSION`

2. Update libpdfium version in `LIBPDFIUM_VERSION`

3. Tag release

   ```sh
   git tag v0.1.7
   git push origin v0.1.7
   ```

4. Push new tag

TODO: pack all of the above into a dagger script
TODO: use build naming, e.g. 0.1.0+libpdfium.6889
TODO: add tailscale to GH runners
    https://github.com/PostHog/posthog/blob/9cbcf09f7032498874614086f2a0bd4c23bbe815/.github/workflows/pr-deploy.yml#L45

- name: connect to tailscale
  uses: tailscale/github-action@8b804aa882ac3429b804a2a22f9803a2101a0db9
  env:
      TS_EXPERIMENT_OAUTH_AUTHKEY: true
  with:
      version: 1.42.0
      authkey: ${{ secrets.TAILSCALE_OAUTH_SECRET }}
      args: --advertise-tags tag:github-runner

## github / hexpm configuration

```sh
mix hex.user key generate --permission package:pdfium --key-name pdfium
gh secret set HEX_API_KEY --app actions --body value-from-previous-step
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
