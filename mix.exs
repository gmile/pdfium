defmodule PDFium.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :pdfium,
      description: "Elixir interface for pdfium",
      licenses: ["MIT"],
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
      make_precompiler_nif_versions: [
        versions: ["2.16", "2.17"]
      ],
      cc_precompiler: [
        cleanup: "clean",
        allow_missing_compiler: true,
        compilers: %{
          {:unix, :linux} => %{
            "x86_64-linux-gnu" => "x86_64-linux-gnu-",
            "aarch64-linux-gnu" => "aarch64-linux-gnu-",
            "armv7l-linux-gnueabihf" => "arm-linux-gnueabihf-",
            "x86_64-linux-musl" => "x86_64-linux-musl-",
            "aarch64-linux-musl" => "aarch64-linux-musl-"
          },
          {:unix, :darwin} => %{
            "x86_64-apple-darwin" => {
              "gcc",
              "g++",
              "<%= cc %> -arch x86_64",
              "<%= cxx %> -arch x86_64"
            },
            "aarch64-apple-darwin" => {
              "gcc",
              "g++",
              "<%= cc %> -arch arm64",
              "<%= cxx %> -arch arm64"
            }
          },
          {:win32, :nt} => %{}
        }
      ],
      make_precompiler: {:nif, CCPrecompiler},
      make_precompiler_filename: "pdfium_nif",
      make_precompiler_priv_paths: ~w"pdfium_nif.so libpdfium.so",
      make_precompiler_url: "https://github.com/gmile/pdfium/releases/download/v#{@version}/@{artefact_filename}"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
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
        c_src/*.[ch]
        Makefile
      "
    ]
  end
end
