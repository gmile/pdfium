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
      make_precompiler: {:nif, CCPrecompiler},
      make_precompiler_filename: "pdfium_nif",
      make_precompiler_priv_paths: ~w"pdfium_nif.so libpdfium.dylib",
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
