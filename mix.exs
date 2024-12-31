defmodule PDFium.MixProject do
  use Mix.Project

  @version File.read!("VERSION") |> String.trim_trailing()

  def project do
    [
      app: :pdfium,
      description: "Elixir interface for pdfium",
      link: "https://github.com/gmile/pdfium",
      version: @version,
      elixir: "~> 1.17",
      compilers: [:elixir_make] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
    ] ++ make_precompiler()
  end

  def make_precompiler do
    [
      make_precompiler: {:nif, CCPrecompiler},
      make_precompiler_url: "https://github.com/gmile/pdfium/releases/download/v#{@version}/@{artefact_filename}",
      # TODO: not sure if below is necessary
      cc_precompiler: [
        compilers: %{
          {:unix, :linux} => %{
            "x86_64-linux-gnu" => nil,
            "x86_64-linux-musl" => nil,
            "aarch64-linux-gnu" => nil,
            "aarch64-linux-musl" => nil
          },
          {:unix, :darwin} => %{
            "x86_64-apple-darwin" => nil,
            "aarch64-apple-darwin" => nil
          }
        }
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:cc_precompiler, "~> 0.1", runtime: false},
      {:elixir_make, "~> 0.1", runtime: false}
    ]
  end

  defp package do
    [
      files: ~w"
        lib
        LICENSE
        mix.exs
        README.md
        c_src/pdfium_nif.c
        Makefile
        VERSION
        checksum.exs
      ",
      licenses: ~w"MIT",
      links: %{
        "GitHub" => "https://github.com/gmile/pdfium"
      }
    ]
  end
end
