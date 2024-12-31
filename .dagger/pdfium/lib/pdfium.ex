defmodule Pdfium do
  use Dagger.Mod.Object, name: "Pdfium"

  defn check_latest_tag(github_token: Dagger.Secret.t()) :: String.t() do
    known_tag =
      dag()
      |> Dagger.Client.git("https://github.com/gmile/pdfium")
      |> Dagger.GitRepository.with_auth_token(github_token)
      |> Dagger.GitRepository.branch("stable")
      |> Dagger.GitRef.tree()
      |> Dagger.Directory.file("LIBPDFIUM_TAG")
      |> Dagger.File.contents()

    {:ok, all_tags} =
      dag()
      |> Dagger.Client.git("https://github.com/bblanchon/pdfium-binaries")
      |> Dagger.GitRepository.tags(patterns: ~w(chromium/*))

    [latest_tag | _] = Enum.sort(all_tags, :desc)

    if latest_tag > known_tag do
      Jason.encode!(%{new_tag_available: true, tag: latest_tag})
    else
      Jason.encode!(%{new_tag_available: false})
    end
  end

  defn prepare_release_pull_request(
    base: String.t(),
    package_version: String.t() | nil,
    libpdfium_tag: String.t(),
    github_token: Dagger.Secret.t(),
    actor: String.t()
  ) :: Dagger.Container.t() do
    pdfium =
      dag()
      |> Dagger.Client.git("https://github.com/gmile/pdfium")
      |> Dagger.GitRepository.with_auth_token(github_token)
      |> Dagger.GitRepository.branch(base)
      |> Dagger.GitRef.tree()

    package_version =
      if package_version do
        package_version
      else
        {:ok, package_version} =
          pdfium
          |> Dagger.Directory.file("VERSION")
          |> Dagger.File.contents()

        package_version
        |> String.trim_trailing()
        |> Version.parse!()
        |> Map.update!(:patch, & &1 + 1)
        |> Version.to_string()
      end

    libpdfium_tag =
      if libpdfium_tag do
        libpdfium_tag
      else
        {:ok, libpdfium_tag} =
          pdfium
          |> Dagger.Directory.file("PDFIUM_VERSION")
          |> Dagger.File.contents()

        libpdfium_tag
      end

    new_branch_name = "update-libpdfium-to-#{libpdfium_tag}"

    dag()
    |> Dagger.Client.container()
    |> Dagger.Container.from("alpine:3.21")
    |> Dagger.Container.with_exec(~w"apk add git github-cli")
    |> Dagger.Container.with_secret_variable("GH_TOKEN", github_token)
    |> Dagger.Container.with_directory("/pdfium", pdfium)
    |> Dagger.Container.with_workdir("/pdfium")
    |> Dagger.Container.with_exec(~w"gh auth setup-git")
    |> Dagger.Container.with_exec(~w"git config user.name #{actor}")
    |> Dagger.Container.with_exec(~w"git config user.email #{actor}@users.noreply.github.com")
    |> Dagger.Container.with_exec(~w"git fetch origin #{base}")
    |> Dagger.Container.with_exec(~w"git switch --create #{new_branch_name} origin/#{base}")
    |> Dagger.Container.with_new_file("/pdfium/LIBPDFIUM_TAG", libpdfium_tag)
    |> Dagger.Container.with_exec(~w"git add LIBPDFIUM_TAG")
    |> Dagger.Container.with_exec(~w"git commit --message" ++ ["Update libpdfium tag to #{libpdfium_tag}"])
    |> Dagger.Container.with_new_file("/pdfium/VERSION", package_version)
    |> Dagger.Container.with_exec(~w"git add VERSION")
    |> Dagger.Container.with_exec(~w"git commit --message" ++ ["Update package to version #{package_version}"])
    |> Dagger.Container.with_exec(~w"git push origin #{new_branch_name}")
    |> Dagger.Container.with_exec(~w"gh pr create --base stable --reviewer gmile --fill --repo gmile/pdfium" ++ ["--title", "Bump libpdfium to #{libpdfium_tag} tag"])
    # |> Dagger.Container.with_exec(~w"gh pr merge #{new_branch_name} --auto --delete-branch --rebase")
  end

  def collect_build_info(src_dir, platform_name, abi) do
    {erlang_platform_name, pdfium_platform_name} =
      case platform_name do
        "linux/arm64" -> {"aarch64", "arm64"}
        "linux/amd64" -> {"x86_64", "x64"}
      end

    {erlang_abi_name, pdfium_abi_name} =
      case abi do
        "glibc" -> {"linux-gnu", "linux"}
        "musl" -> {"linux-musl", "linux-musl"}
      end

    {:ok, pdfium_tag} =
      src_dir
      |> Dagger.Directory.file("LIBPDFIUM_TAG")
      |> Dagger.File.contents()

    {:ok, package_version} =
      src_dir
      |> Dagger.Directory.file("VERSION")
      |> Dagger.File.contents()

    {build_image_name, nif_version} =
      case abi do
        "glibc" -> {"hexpm/elixir:1.18.1-erlang-27.2-ubuntu-noble-20241015", "2.17"}
        "musl" -> {"hexpm/elixir:1.18.1-erlang-27.2-alpine-3.21.0", "2.17"}
      end

    pdfium_download_url = "https://github.com/bblanchon/pdfium-binaries/releases/download/#{URI.encode_www_form(pdfium_tag)}/pdfium-#{pdfium_abi_name}-#{pdfium_platform_name}.tgz"
    output_filename = "pdfium-nif-#{nif_version}-#{erlang_platform_name}-#{erlang_abi_name}-#{package_version}.tar.gz"

    {
      build_image_name,
      pdfium_download_url,
      output_filename
    }
  end

  defn precompile(src_dir: Dagger.Directory.t(), platform_name: String.t(), abi: String.t()) :: Dagger.File.t() do
    {
      build_image_name,
      pdfium_download_url,
      output_filename
    } = collect_build_info(src_dir, platform_name, abi)

    otp_directory_name="/usr/local/lib/erlang"

    # rename to libpdfium_extract_path
    libpdfium_extract_path="/pdfium"

    compile = ~w(
      gcc
      -march=native
      -Wall
      -Wextra
      -Werror
      -Wno-unused-parameter
      -Wmissing-prototypes
      --pic
      --optimize=2
      --std c11
      --include-directory #{otp_directory_name}/usr/include
      --include-directory #{libpdfium_extract_path}/include
      --compile
      --output=pdfium_nif.o
      pdfium_nif.c
    )

    link = ~w(
      gcc
      pdfium_nif.o
      --shared
      --output=pdfium_nif.so
      --library-directory=#{otp_directory_name}/usr/lib
      --library-directory=#{libpdfium_extract_path}/lib
      -Wl,-s
      -Wl,--disable-new-dtags
      -Wl,-rpath=$ORIGIN
      -l:libpdfium.so
    )

    output_path = "/build/#{output_filename}"

    pack = ~w(
      tar
      --create
      --verbose
      --file=#{output_path}
      --directory /build pdfium_nif.so
      --directory #{libpdfium_extract_path}/lib libpdfium.so
    )

    dag()
    |> Dagger.Client.container(platform: platform_name)
    |> Dagger.Container.from(build_image_name)
    |> with_build_tools(abi)
    |> Dagger.Container.with_workdir("/build")
    |> Dagger.Container.with_file("/build/pdfium_nif.c", Dagger.Directory.file(src_dir, "c_src/pdfium_nif.c"))
    |> Dagger.Container.with_file("/build/pdfium.tar", Dagger.Client.http(dag(), pdfium_download_url))
    |> Dagger.Container.with_exec(~w"mkdir #{libpdfium_extract_path}")
    |> Dagger.Container.with_exec(~w"tar --extract --gunzip --directory=#{libpdfium_extract_path} --file=/build/pdfium.tar")
    |> Dagger.Container.with_exec(compile)
    |> Dagger.Container.with_exec(link)
    |> Dagger.Container.with_exec(pack)
    |> Dagger.Container.file(output_path)
  end

  defn test(precompiled: Dagger.File.t(), platform_name: String.t(), abi: String.t()) :: Dagger.File.t() do
    {:ok, filename} = Dagger.File.name(precompiled)
    precompiled_path = "/test/#{filename}"

    dag()
    |> with_test_image(platform_name, abi)
    |> Dagger.Container.with_workdir("/test")
    |> Dagger.Container.with_file(precompiled_path, precompiled)
    |> Dagger.Container.with_exec(~w"tar --extract --directory=/test/ --file=#{precompiled_path}")
    |> Dagger.Container.with_new_file("/test/test.exs", test_script())
    |> Dagger.Container.with_new_file("/test/test.pdf", test_pdf())
    |> Dagger.Container.with_exec(~w"elixir test.exs")
    |> Dagger.Container.file(precompiled_path)
  end

  defn ci(ref: String.t(), platform_name: String.t(), abi: String.t(), github_token: Dagger.Secret.t()) :: Dagger.File.t() do
    dag()
    |> Dagger.Client.git("https://github.com/gmile/pdfium")
    |> Dagger.GitRepository.with_auth_token(github_token)
    |> Dagger.GitRepository.ref(ref)
    |> Dagger.GitRef.tree()
    |> precompile(platform_name, abi)
    |> test(platform_name, abi)
  end

  defn create_release(pr: String.t(), actor: String.t(), github_token: Dagger.Secret.t(), hex_api_key: Dagger.Secret.t()) :: Dagger.Container.t() do
    gh =
      dag()
      |> Dagger.Client.container()
      |> Dagger.Container.from("alpine:3.21")
      |> Dagger.Container.with_exec(~w"apk add github-cli perl-utils")
      |> Dagger.Container.with_secret_variable("GITHUB_TOKEN", github_token)

    {:ok, <<head_ref::binary-size(40), "\n", base_ref_name::binary >>} =
      gh
      |> Dagger.Container.with_exec(~w"echo #{DateTime.utc_now()}")
      |> Dagger.Container.with_exec(~w"gh pr view #{pr} --json headRefOid,baseRefName --jq .headRefOid,.baseRefName --repo gmile/pdfium")
      |> Dagger.Container.stdout()

    base_ref_name = String.trim_trailing(base_ref_name)

    run_id = ~w"
      gh run list
        --workflow ci.yaml
        --commit #{head_ref}
        --status success
        --limit 1
        --json databaseId
        --repo gmile/pdfium
        --jq .[0].databaseId
    "

    {:ok, run_id} =
      gh
      |> Dagger.Container.with_exec(run_id)
      |> Dagger.Container.stdout()

    gh = Dagger.Container.with_exec(gh, ~w"gh run download #{run_id} --dir /artifacts --repo gmile/pdfium")
    artifacts = Dagger.Container.directory(gh, "/artifacts")

    {:ok, entries} = Dagger.Directory.glob(artifacts, "**/*.tar.gz")
    entries = Enum.map_join(entries, " ", &"/artifacts/#{&1}")

    {:ok, checksums} =
      gh
      |> Dagger.Container.with_exec(~w"shasum --algorithm 256 #{entries}")
      |> Dagger.Container.stdout()

    checksums =
      checksums
      |> String.split("\n", trim: true)
      |> Enum.map(&String.split(&1, ~r/\s+/, parts: 2))
      |> Enum.map(fn [hash, path] -> {Path.basename(path), "sha256:" <> hash} end)
      |> Map.new()

    pdfium =
      dag()
      |> Dagger.Client.git("https://github.com/gmile/pdfium")
      |> Dagger.GitRepository.with_auth_token(github_token)
      |> Dagger.GitRepository.branch(base_ref_name)
      |> Dagger.GitRef.tree()

    {:ok, package_version} =
      pdfium
      |> Dagger.Directory.file("VERSION")
      |> Dagger.File.contents()

    dag()
    |> Dagger.Client.container()
    |> Dagger.Container.from("hexpm/elixir:1.18.1-erlang-27.2-alpine-3.21.0")
    |> Dagger.Container.with_exec(~w"apk add git github-cli")
    |> Dagger.Container.with_secret_variable("GITHUB_TOKEN", github_token)
    |> Dagger.Container.with_directory("/pdfium", pdfium)
    |> Dagger.Container.with_directory("/artifacts", artifacts)
    |> Dagger.Container.with_workdir("/pdfium")
    |> Dagger.Container.with_exec(~w"gh auth setup-git")
    |> Dagger.Container.with_exec(~w"git config user.name #{actor}")
    |> Dagger.Container.with_exec(~w"git config user.email #{actor}@users.noreply.github.com")
    |> Dagger.Container.with_exec(~w"git fetch origin #{base_ref_name}")
    |> Dagger.Container.with_exec(~w"git checkout #{base_ref_name}")
    |> Dagger.Container.with_new_file("/pdfium/checksum.exs", inspect(checksums, pretty: true))
    |> Dagger.Container.with_exec(~w"git add checksum.exs")
    |> Dagger.Container.with_exec(~w"git commit --message" ++ ["Update checksums"])
    |> Dagger.Container.with_exec(~w"git tag v#{package_version} --message" ++ ["Tagging v#{package_version} release"])
    |> Dagger.Container.with_exec(~w"git push origin HEAD:#{base_ref_name} v#{package_version}")
    |> Dagger.Container.with_exec(~w"gh release create v#{package_version} --repo gmile/pdfium #{entries}")
    |> Dagger.Container.with_exec(~w"mix local.hex --force")
    |> Dagger.Container.with_exec(~w"mix do deps.get + deps.compile")
    |> Dagger.Container.with_secret_variable("HEX_API_KEY", hex_api_key)
    |> Dagger.Container.with_exec(~w"mix hex.publish package --yes")
  end

  def test_script do
    """
    defmodule PDFium do
      @on_load :load_nif

      def load_nif do
        :erlang.load_nif(~c"./pdfium_nif", 0)
      end

      def load_document(_filename), do: :erlang.nif_error(:nif_not_loaded)

      def get_page_count(_document), do: :erlang.nif_error(:nif_not_loaded)
    end

    {:ok, ref} = PDFium.load_document("./test.pdf")
    {:ok, pages} = PDFium.get_page_count(ref)

    IO.inspect(pages, label: "pages")
    """
  end

  def test_pdf do
    """
    %PDF-1.0
    1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
    2 0 obj<</Type/Pages/Kids[3 0 R 4 0 R]/Count 2>>endobj
    3 0 obj<</Type/Page/Parent 2 0 R>>endobj
    4 0 obj<</Type/Page/Parent 2 0 R>>endobj
    xref
    0 5
    0000000000 65535 f
    0000000009 00000 n
    0000000053 00000 n
    0000000102 00000 n
    0000000148 00000 n
    trailer<</Size 5/Root 1 0 R>>
    startxref
    194
    %%EOF
    """
  end

  # todo: in principle it should be possible to move all file-related operations and utilities
  #       (tar/wget and tar/coreutils) to a generic busybox so the disappear here
  #
  defp with_build_tools(container, "glibc") do
    container
    |> Dagger.Container.with_exec(~w"apt update")
    |> Dagger.Container.with_exec(~w"apt install build-essential tar jq wget --yes")
  end

  defp with_build_tools(container, "musl") do
    container
    |> Dagger.Container.with_exec(~w"apk add build-base tar jq coreutils")
  end

  defp with_test_image(dag, platform_name, "glibc") do
    dag
    |> Dagger.Client.container(platform: platform_name)
    |> Dagger.Container.from("hexpm/elixir:1.18.1-erlang-27.2-ubuntu-noble-20241015")
    |> Dagger.Container.with_exec(~w"apt update")
    |> Dagger.Container.with_exec(~w"apt install tar")
  end

  defp with_test_image(dag, platform_name, "musl") do
    dag
    |> Dagger.Client.container(platform: platform_name)
    |> Dagger.Container.from("hexpm/elixir:1.18.1-erlang-27.2-alpine-3.21.0")
    |> Dagger.Container.with_exec(~w"apk add tar")
  end
end
