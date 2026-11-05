defmodule Pdfium.Release do
  use Dagger.Mod.Object, name: "Release"

  object do
    field(:package, Dagger.Directory.t())
    field(:receipt, Dagger.File.t())
  end

  defn hex_publish(self, hex_api_key: Dagger.Secret.t()) :: Dagger.Container.t() do
    dag()
    |> Dagger.Client.container()
    |> Dagger.Container.from(Pdfium.image("musl"))
    |> Dagger.Container.with_directory("/pdfium", self.package)
    |> Dagger.Container.with_file("/pdfium/release", self.receipt)
    |> Dagger.Container.with_workdir("/pdfium")
    |> Dagger.Container.with_exec(~w"mix local.hex --force")
    |> Dagger.Container.with_exec(~w"mix deps.get")
    |> Dagger.Container.with_exec(~w"mix elixir_make.checksum --all")
    |> Dagger.Container.with_secret_variable("HEX_API_KEY", hex_api_key)
    |> Dagger.Container.with_exec(~w"mix hex.publish package --yes")
  end
end
