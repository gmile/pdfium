defmodule PDFium.MixProject do
  use Mix.Project

  @version File.read!("VERSION") |> String.trim()
  @libpdfium "chromium/8152"

  def project do
    [
      app: :pdfium,
      description: "Elixir interface for pdfium",
      link: "https://github.com/gmile/pdfium",
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:elixir_make] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md"],
        skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
      ],
      dialyzer: [
        plt_add_apps: [:ex_unit],
        plt_core_path: "_build/plts",
        plt_local_path: "_build/plts"
      ]
    ] ++ make_precompiler()
  end

  def make_precompiler do
    [
      make_targets: ["all"],
      make_env: &make_env/0,
      make_precompiler: {:nif, CCPrecompiler},
      make_precompiler_filename: "pdfium_nif",
      make_precompiler_nif_versions: [versions: ["2.17"]],
      make_precompiler_url:
        "https://github.com/gmile/pdfium/releases/download/v#{@version}/@{artefact_filename}",
      cc_precompiler: [
        compilers: %{
          {:unix, :linux} => %{
            "x86_64-linux-gnu" => nil,
            "x86_64-linux-musl" => nil,
            "aarch64-linux-gnu" => nil,
            "aarch64-linux-musl" => nil
          },
          {:unix, :darwin} => %{
            "aarch64-apple-darwin" => nil
          }
        }
      ]
    ]
  end

  defp make_env do
    %{
      "PDFIUM_TAG" => @libpdfium,
      "FINE_INCLUDE_DIR" => Path.join(Mix.Project.deps_path(), "fine/c_include")
    }
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:cc_precompiler, "~> 0.1", runtime: false},
      {:elixir_make, "~> 0.1", runtime: false},
      {:fine, "~> 0.2", runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ~w"
        c_src/pdfium_nif.cpp
        CHANGELOG.md
        checksum.exs
        lib
        LICENSE
        Makefile
        mix.exs
        README.md
        VERSION
      ",
      licenses: ~w"MIT",
      links: %{
        "GitHub" => "https://github.com/gmile/pdfium"
      }
    ]
  end
end
