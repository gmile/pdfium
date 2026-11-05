defmodule Pdfium.Bump do
  use Dagger.Mod.Object, name: "Bump"

  object do
    field(:ref, Dagger.GitRef.t())
  end

  defn open_pull_request(self, github_token: Dagger.Secret.t()) :: Dagger.Container.t() do
    tree = Dagger.GitRef.tree(self.ref, depth: 0)

    {:ok, libpdfium_tag} =
      tree
      |> Dagger.Directory.file("LIBPDFIUM_TAG")
      |> Dagger.File.contents()

    Pdfium.gh(github_token)
    |> Dagger.Container.with_directory("/pdfium", tree)
    |> Dagger.Container.with_workdir("/pdfium")
    |> Dagger.Container.with_exec(~w"gh auth setup-git")
    |> Dagger.Container.with_exec(~w"git push #{Pdfium.repository_url()} HEAD:refs/heads/update-libpdfium")
    |> Dagger.Container.with_exec(
      ~w"gh pr create --repo #{Pdfium.repository_slug()} --base main --head update-libpdfium --reviewer gmile" ++
        ["--title", "Bump libpdfium to #{libpdfium_tag}", "--body", ""]
    )
  end
end
