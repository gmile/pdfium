defmodule Pdfium do
  use Dagger.Mod.Object, name: "Pdfium"

  @repository_url "https://github.com/gmile/pdfium"
  @repository_slug "gmile/pdfium"
  @libpdfium_binaries_url "https://github.com/bblanchon/pdfium-binaries"
  @fine_url "https://github.com/elixir-nx/fine"
  @fine_tag "v0.1.6"
  @alpine_image "alpine:3.23.4"
  @gcc_image "gcc:14-bookworm"
  @glibc_image "hexpm/elixir:1.20.2-erlang-29.0.3-ubuntu-noble-20260610"
  @musl_image "hexpm/elixir:1.20.2-erlang-29.0.3-alpine-3.23.5"
  @nif_version "2.18"
  @source_paths ~w(c_src/** lib/pdfium/nif.ex LIBPDFIUM_TAG VERSION)

  defn prepare_release_pull_request(
    base: String.t(),
    package_version: String.t() | nil,
    libpdfium_tag: String.t() | nil,
    github_token: Dagger.Secret.t(),
    actor: String.t()
  ) :: String.t() do
    repository = Dagger.Client.git(dag(), @repository_url, http_auth_token: github_token)
    base_ref = Dagger.GitRepository.branch(repository, base)
    base_tree = Dagger.GitRef.tree(base_ref)

    {:ok, known_tag} =
      base_tree
      |> Dagger.Directory.file("LIBPDFIUM_TAG")
      |> Dagger.File.contents()

    libpdfium_tag = libpdfium_tag || latest_libpdfium_tag()

    if libpdfium_tag == String.trim(known_tag) do
      "#{base} is already on #{libpdfium_tag}"
    else
      open_release_pull_request(repository, base, libpdfium_tag, package_version, github_token, actor)
    end
  end

  defp open_release_pull_request(repository, base, libpdfium_tag, package_version, github_token, actor) do
    base_ref = Dagger.GitRepository.branch(repository, base)
    base_tree = Dagger.GitRef.tree(base_ref)
    package_version = package_version || next_patch_version(base_tree)
    new_branch_name = "update-libpdfium-to-#{libpdfium_tag}"

    with_tag = Dagger.Directory.with_new_file(base_tree, "LIBPDFIUM_TAG", libpdfium_tag)
    with_version = Dagger.Directory.with_new_file(with_tag, "VERSION", package_version)

    {:ok, _} =
      base_ref
      |> commit(Dagger.Directory.changes(with_tag, base_tree), "Update libpdfium tag to #{libpdfium_tag}", actor)
      |> commit(Dagger.Directory.changes(with_version, with_tag), "Update package to version #{package_version}", actor)
      |> Dagger.GitRef.push(to: repository, branch: new_branch_name)
      |> Dagger.GitPushResult.sha()

    {:ok, _} =
      gh(github_token)
      |> Dagger.Container.with_exec(
        ~w"gh pr create --repo #{@repository_slug} --base #{base} --head #{new_branch_name} --reviewer gmile" ++
          ["--title", "Bump libpdfium to #{libpdfium_tag} tag", "--body", ""]
      )
      |> Dagger.Container.sync()

    "opened #{new_branch_name} against #{base}"
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

    pdfium_download_url =
      "https://github.com/bblanchon/pdfium-binaries/releases/download/#{URI.encode_www_form(pdfium_tag)}/pdfium-#{pdfium_abi_name}-#{pdfium_platform_name}.tgz"

    output_filename =
      "pdfium-nif-#{@nif_version}-#{erlang_platform_name}-#{erlang_abi_name}-#{package_version}.tar.gz"

    {
      image(abi),
      pdfium_download_url,
      output_filename
    }
  end

  defn precompile(src_dir: Dagger.Directory.t(), platform_name: String.t(), abi: String.t()) ::
         Dagger.File.t() do
    {
      build_image_name,
      pdfium_download_url,
      output_filename
    } = collect_build_info(src_dir, platform_name, abi)

    otp_directory_name = "/usr/local/lib/erlang"

    libpdfium_extract_path = "/pdfium"

    fine_include_path = "/fine"

    compile = ~w(
      g++
      -Wall
      -Wextra
      -Werror
      -Wno-unused-parameter
      --pic
      -fvisibility=hidden
      --optimize=2
      --std=c++17
      --include-directory=#{otp_directory_name}/usr/include
      --include-directory=#{libpdfium_extract_path}/include
      --include-directory=#{fine_include_path}
      --compile
      --output=pdfium_nif.o
      pdfium_nif.cpp
    )

    link = ~w(
      g++
      pdfium_nif.o
      --shared
      --output=pdfium_nif.so
      --library-directory=#{otp_directory_name}/usr/lib
      --library-directory=#{libpdfium_extract_path}/lib
      -static-libstdc++
      -Wl,-s
      -Wl,--disable-new-dtags
      -Wl,-rpath,$ORIGIN
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

    fine_headers =
      dag()
      |> Dagger.Client.git(@fine_url)
      |> Dagger.GitRepository.tag(@fine_tag)
      |> Dagger.GitRef.tree()
      |> Dagger.Directory.directory("c_include")

    libpdfium =
      dag()
      |> Dagger.Client.http(pdfium_download_url)
      |> Dagger.File.extract()

    dag()
    |> with_build_image(platform_name, abi, build_image_name)
    |> Dagger.Container.with_workdir("/build")
    |> Dagger.Container.with_file(
      "/build/pdfium_nif.cpp",
      Dagger.Directory.file(src_dir, "c_src/pdfium_nif.cpp")
    )
    |> Dagger.Container.with_directory(fine_include_path, fine_headers)
    |> Dagger.Container.with_directory(libpdfium_extract_path, libpdfium)
    |> Dagger.Container.with_exec(compile)
    |> Dagger.Container.with_exec(link)
    |> Dagger.Container.with_exec(pack)
    |> Dagger.Container.file(output_path)
  end

  defn test(
         precompiled: Dagger.File.t(),
         src_dir: Dagger.Directory.t(),
         platform_name: String.t(),
         abi: String.t()
       ) :: Dagger.File.t() do
    {:ok, _} =
      dag()
      |> Dagger.Client.container(platform: platform_name)
      |> Dagger.Container.from(image(abi))
      |> Dagger.Container.with_workdir("/test")
      |> Dagger.Container.with_directory("/test", Dagger.File.extract(precompiled))
      |> Dagger.Container.with_file("/test/nif.ex", Dagger.Directory.file(src_dir, "lib/pdfium/nif.ex"))
      |> Dagger.Container.with_new_file("/test/test.exs", test_script())
      |> Dagger.Container.with_new_file("/test/test.pdf", test_pdf())
      |> Dagger.Container.with_exec(~w"elixir test.exs")
      |> Dagger.Container.sync()

    precompiled
  end

  defn ci(ws: Dagger.Workspace.t(), platform_name: String.t(), abi: String.t()) :: Dagger.File.t() do
    src_dir = Dagger.Workspace.directory(ws, "/", include: @source_paths)

    src_dir
    |> precompile(platform_name, abi)
    |> test(src_dir, platform_name, abi)
  end

  @check true
  defn amd64_glibc(ws: Dagger.Workspace.t()) :: Dagger.Void.t() do
    check(ws, "linux/amd64", "glibc")
  end

  @check true
  defn amd64_musl(ws: Dagger.Workspace.t()) :: Dagger.Void.t() do
    check(ws, "linux/amd64", "musl")
  end

  @check true
  defn arm64_glibc(ws: Dagger.Workspace.t()) :: Dagger.Void.t() do
    check(ws, "linux/arm64", "glibc")
  end

  @check true
  defn arm64_musl(ws: Dagger.Workspace.t()) :: Dagger.Void.t() do
    check(ws, "linux/arm64", "musl")
  end

  defn create_release(pr: String.t(), actor: String.t(), github_token: Dagger.Secret.t(), hex_api_key: Dagger.Secret.t()) :: Dagger.Void.t() do
    {:ok, now} = Dagger.Client.current_timestamp(dag())

    gh =
      gh(github_token)
      |> Dagger.Container.with_env_variable("CACHE_BUSTER", now)

    {:ok, <<head_ref::binary-size(40), "\n", base_ref_name::binary >>} =
      gh
      |> Dagger.Container.with_exec(~w"gh pr view #{pr} --json headRefOid,baseRefName --jq .headRefOid,.baseRefName --repo #{@repository_slug}")
      |> Dagger.Container.stdout()

    base_ref_name = String.trim_trailing(base_ref_name)

    run_id = ~w"
      gh run list
        --workflow ci.yaml
        --commit #{head_ref}
        --status success
        --limit 1
        --json databaseId
        --repo #{@repository_slug}
        --jq .[0].databaseId
    "

    {:ok, run_id} =
      gh
      |> Dagger.Container.with_exec(run_id)
      |> Dagger.Container.stdout()

    gh = Dagger.Container.with_exec(gh, ~w"gh run download #{run_id} --dir /artifacts --repo #{@repository_slug}")
    artifacts = Dagger.Container.directory(gh, "/artifacts")

    {:ok, entries} = Dagger.Directory.glob(artifacts, "**/*.tar.gz")
    entries = Enum.map(entries, &"/artifacts/#{&1}")

    {:ok, checksums} =
      gh
      |> Dagger.Container.with_exec(~w"sha256sum" ++ entries)
      |> Dagger.Container.stdout()

    checksums =
      checksums
      |> String.split("\n", trim: true)
      |> Enum.map(&String.split(&1, ~r/\s+/, parts: 2))
      |> Enum.map(fn [hash, path] -> {Path.basename(path), "sha256:" <> hash} end)
      |> Map.new()

    repository = Dagger.Client.git(dag(), @repository_url, http_auth_token: github_token)
    base_ref = Dagger.GitRepository.branch(repository, base_ref_name)
    base_tree = Dagger.GitRef.tree(base_ref)

    {:ok, package_version} =
      base_tree
      |> Dagger.Directory.file("VERSION")
      |> Dagger.File.contents()

    with_checksums = Dagger.Directory.with_new_file(base_tree, "checksum.exs", inspect(checksums, pretty: true))

    {:ok, release_sha} =
      base_ref
      |> commit(Dagger.Directory.changes(with_checksums, base_tree), "Update checksums", actor)
      |> Dagger.GitRef.push(to: repository, branch: base_ref_name)
      |> Dagger.GitPushResult.sha()

    {:ok, _} =
      gh
      |> Dagger.Container.with_exec(
        ~w"gh release create v#{package_version} --repo #{@repository_slug} --target #{release_sha}" ++
          ["--title", "v#{package_version}"] ++ entries
      )
      |> Dagger.Container.sync()

    {:ok, _} =
      dag()
      |> Dagger.Client.container()
      |> Dagger.Container.from(@musl_image)
      |> Dagger.Container.with_directory("/pdfium", with_checksums)
      |> Dagger.Container.with_workdir("/pdfium")
      |> Dagger.Container.with_exec(~w"mix local.hex --force")
      |> Dagger.Container.with_exec(~w"mix do deps.get + deps.compile")
      |> Dagger.Container.with_secret_variable("HEX_API_KEY", hex_api_key)
      |> Dagger.Container.with_exec(~w"mix hex.publish package --yes")
      |> Dagger.Container.sync()

    :ok
  end

  def test_script do
    """
    # The module the library ships, rather than a copy of it kept in step by
    # hand: a NIF that declares a function the module does not will not load at
    # all, so a copy left behind fails the build for the wrong reason.
    Code.require_file("nif.ex")

    {:ok, document} = PDFium.NIF.load_document("./test.pdf")
    {:ok, pages} = PDFium.NIF.get_page_count(document)
    {:ok, boxes} = PDFium.NIF.get_page_boxes(document)

    ^pages = length(boxes)

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

  defp check(ws, platform_name, abi) do
    case Dagger.File.sync(ci(ws, platform_name, abi)) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp commit(ref, changes, message, actor) do
    {:ok, now} = Dagger.Client.current_timestamp(dag())

    Dagger.GitRef.with_commit(ref, changes, message, now, actor, "#{actor}@users.noreply.github.com")
  end

  defp gh(github_token) do
    dag()
    |> Dagger.Client.container()
    |> Dagger.Container.from(@alpine_image)
    |> Dagger.Container.with_exec(~w"apk add github-cli")
    |> Dagger.Container.with_secret_variable("GH_TOKEN", github_token)
  end

  defp next_patch_version(tree) do
    {:ok, package_version} =
      tree
      |> Dagger.Directory.file("VERSION")
      |> Dagger.File.contents()

    package_version
    |> String.trim_trailing()
    |> Version.parse!()
    |> Map.update!(:patch, & &1 + 1)
    |> Version.to_string()
  end

  defp latest_libpdfium_tag do
    {:ok, tags} =
      dag()
      |> Dagger.Client.git(@libpdfium_binaries_url)
      |> Dagger.GitRepository.tags(patterns: ~w(chromium/*))

    Enum.max_by(tags, &tag_number/1)
  end

  defp tag_number("chromium/" <> number), do: String.to_integer(number)

  defp image("glibc"), do: @glibc_image
  defp image("musl"), do: @musl_image

  defp with_build_image(dag, platform_name, "glibc", otp_image_name) do
    otp_directory =
      dag
      |> Dagger.Client.container(platform: platform_name)
      |> Dagger.Container.from(otp_image_name)
      |> Dagger.Container.directory("/usr/local/lib/erlang")

    dag
    |> Dagger.Client.container(platform: platform_name)
    |> Dagger.Container.from(@gcc_image)
    |> Dagger.Container.with_directory("/usr/local/lib/erlang", otp_directory)
  end

  defp with_build_image(dag, platform_name, "musl", build_image_name) do
    dag
    |> Dagger.Client.container(platform: platform_name)
    |> Dagger.Container.from(build_image_name)
    |> Dagger.Container.with_exec(~w"apk add build-base tar")
  end
end
