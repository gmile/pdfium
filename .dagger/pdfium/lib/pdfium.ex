defmodule Pdfium do
  use Dagger.Mod.Object, name: "Pdfium"

  # == Automatic deployment scenario ==
  #
  # 1. create & checkout a branch called "release-libpdfium-#{LIBPDFIUM_TAG}" from "stable" branch
  #
  # 2. in the new branch:
  #
  #   1. update contents of LIBPDFIUM_TAG file and commit
  #
  #   2. update contents of VERSION (always just bump patch version, for example 0.1.0 -> v0.1.1) file, commit
  #
  # 3. push branch to GH and open a PR from the branch against "stable" and run "gh pr merge --auto --delete-branch"
  #
  # 4. wait for PR checks to be green:
  #
  #   1. precompile artifacts
  #
  #   2. test artifacts and test the lib itself
  #
  #   3. if all good, upload the artifacts to GitHub
  #
  # 5. once PR is merged:
  #
  #   1. download files from GH artifacts from merged PR
  #
  #   2. create a release called "v#{VERSION}" (this will automatically create a tag) with all files
  #
  #   3. release new lib version on hex
  #
  # NOTE: only file expected to change during automatic process is LIBPDFIUM_TAG, so it should not cause
  #       conflicts later when main is rebased against stable
  #
  # == Manual deployment scenario ==
  #
  # 1. create & checkout a branch called "release-#{VERSION}" from "main" branch
  #
  # 2. in the new branch:
  #
  #   1. update contents of VERSION file & commit
  #
  # 3. push branch to GH and open a PR from the branch against "main" and run "gh pr merge --auto --delete-branch"
  #
  # 4. wait for PR checks to be green:
  #
  #   1. precompile artifacts, linux and macos
  #
  #   2. test artifacts and test the lib itself
  #
  #   3. if all good, upload all artifacts to GitHub
  #
  # 5. once PR is merged:
  #
  #   1. download files from GH artifacts from merged PR
  #
  #   2. create a release called "v#{VERSION}" (this will automatically create a tag) with all files
  #
  #   3. release new lib version on hex
  #
  #   4. (additionally) merge main to stable
  #

  defn hello_world() :: String.t() do
    ~s"""
    {"new_tag":"world","new_tag_available":true}
    """
  end

  defn precompile(cur_dir: Dagger.Directory.t(), platform_name: String.t(), abi: String.t(), src_dir: Dagger.Directory.t(), pdfium_tag: String.t()) :: Dagger.File.t() do
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

    pdfium_tag = URI.encode_www_form(pdfium_tag)
    pdfium_download_url = "https://github.com/bblanchon/pdfium-binaries/releases/download/#{pdfium_tag}/pdfium-#{pdfium_abi_name}-#{pdfium_platform_name}.tgz"

    otp_directory_name="/usr/local/lib/erlang"
    pdfium_directory_name="/pdfium"

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
      --include-directory #{pdfium_directory_name}/include
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
      --library-directory=#{pdfium_directory_name}/lib
      -Wl,-s
      -Wl,--disable-new-dtags
      -Wl,-rpath=$ORIGIN
      -l:libpdfium.so
    )

    output = "/build/pdfium-nif-2.17-#{erlang_platform_name}-#{erlang_abi_name}-0.1.0.tar.gz"

    pack = ~w(
      tar
      --create
      --verbose
      --file=#{output}
      --directory /build pdfium_nif.so
      --directory #{pdfium_directory_name}/lib libpdfium.so
    )

    dag()
    |> Dagger.Client.container(platform: platform_name)
    |> with_base_image(abi)
    |> with_tools(abi)
    |> Dagger.Container.with_workdir("/build")
    |> Dagger.Container.with_file("/build/pdfium_nif.c", Dagger.Directory.file(src_dir, "pdfium_nif.c"))
    |> Dagger.Container.with_file("/build/pdfium.tar", Dagger.Client.http(dag(), pdfium_download_url))
    |> Dagger.Container.with_exec(~w"mkdir #{pdfium_directory_name}")
    |> Dagger.Container.with_exec(~w"tar --extract --gunzip --directory=#{pdfium_directory_name} --file=/build/pdfium.tar")
    |> Dagger.Container.with_exec(compile)
    |> Dagger.Container.with_exec(link)
    |> Dagger.Container.with_exec(pack)
    |> Dagger.Container.file(output)
  end

  defn test(precompiled: Dagger.File.t(), platform_name: String.t(), abi: String.t()) :: Dagger.Container.t() do
    dag()
    |> Dagger.Client.container(platform: platform_name)
    |> with_base_image(abi)
    |> Dagger.Container.with_exec(~w"apk add tar")
    |> Dagger.Container.with_workdir("/test")
    |> Dagger.Container.with_file("/test/precompiled.tar", precompiled)
    |> Dagger.Container.with_exec(~w"tar --extract --directory=/test/ --file=/test/precompiled.tar")
    |> Dagger.Container.with_new_file("/test/test.exs", test_script())
    |> Dagger.Container.with_new_file("/test/test.pdf", test_pdf())
    |> Dagger.Container.with_exec(~w"elixir test.exs")
  end

  # update to build_and_test
  defn build_test_and_publish(
    cur_dir: Dagger.Directory.t(),
    platform_name: String.t(),
    abi: String.t(),
    src_dir: Dagger.Directory.t(),
    tag: String.t(),
    pdfium_tag: String.t(),
    github_token: Dagger.Secret.t()
  ) :: Dagger.Container.t() do
    file = precompile(cur_dir, platform_name, abi, src_dir, pdfium_tag)
    {:ok, filename} = Dagger.File.name(file)

    test(file, platform_name, abi)
    |> Dagger.Container.sync()

    dag()
    |> Dagger.Client.container()
    |> with_github_cli(github_token)
    |> Dagger.Container.with_file(filename, file)
    |> Dagger.Container.with_exec(~w"gh release upload #{tag} #{filename} --repo gmile/pdfium")
  end

  defn create_release(tag: String.t(), draft: String.t(), github_token: Dagger.Secret.t()) :: Dagger.Container.t() do
    dag()
    |> Dagger.Client.container()
    |> with_github_cli(github_token)
    |> Dagger.Container.with_exec(~w"gh release create #{tag} --repo gmile/pdfium --draft=#{draft}")
  end

  defn edit_release(tag: String.t(), draft: String.t(), github_token: Dagger.Secret.t()) :: Dagger.Container.t() do
    dag()
    |> Dagger.Client.container()
    |> with_github_cli(github_token)
    |> Dagger.Container.with_exec(~w"gh release edit #{tag} --repo gmile/pdfium --draft=#{draft}")
  end

  defn publish_to_hex(src_dir: Dagger.Directory.t(), hex_api_key: Dagger.Secret.t()) :: Dagger.Container.t() do
    dag()
    |> Dagger.Client.container()
    |> Dagger.Container.from("hexpm/elixir:1.18.0-erlang-27.2-alpine-3.21.0")
    |> Dagger.Container.with_exec(~w"mix local.hex --force")
    |> Dagger.Container.with_secret_variable("HEX_API_KEY", hex_api_key)
    |> Dagger.Container.with_workdir("/pdfium")
    |> Dagger.Container.with_directory("/pdfium", src_dir)
    |> Dagger.Container.with_exec(~w"mix hex.publish package --yes")
  end

  # gh release edit v1.0 --draft=false

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

  defp with_base_image(container, "glibc") do
    container
    |> Dagger.Container.from("hexpm/elixir:1.18.0-erlang-27.2-ubuntu-noble-20241015")
  end

  defp with_base_image(container, "musl") do
    container
    |> Dagger.Container.from("hexpm/elixir:1.18.0-erlang-27.2-alpine-3.21.0")
  end

  defp with_tools(container, "glibc") do
    container
    |> Dagger.Container.with_exec(~w"apt update")
    |> Dagger.Container.with_exec(~w"apt install build-essential tar jq wget --yes")
  end

  defp with_tools(container, "musl") do
    container
    |> Dagger.Container.with_exec(~w"apk add build-base tar jq coreutils")
  end

  def with_github_cli(container, github_token) do
    container
    |> Dagger.Container.from("alpine:3.21")
    |> Dagger.Container.with_secret_variable("GITHUB_TOKEN", github_token)
    |> Dagger.Container.with_exec(~w"apk add github-cli")
  end
end
