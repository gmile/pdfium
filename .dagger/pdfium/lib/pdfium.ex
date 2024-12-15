defmodule Pdfium do
  use Dagger.Mod.Object, name: "Pdfium"

  @doc """
  Produces artifact
  """
  defn precompile(plat: String.t(), libc: String.t(), build_scripts_src_dir: Dagger.Directory.t(), c_src_dir: Dagger.Directory.t()) :: Dagger.File.t() do
    in_erl_platform =
      case plat do
        "linux/arm64" -> "armv8-a"
        "linux/amd64" -> "x86-64"
      end

    out_erl_platform =
      case plat do
        "linux/arm64" -> "aarch64"
        "linux/amd64" -> "x86_64"
      end

    base =
      case libc do
        "glibc" ->
          dag()
          |> Dagger.Client.container(platform: plat)
          |> Dagger.Container.from("hexpm/elixir:1.17.3-erlang-27.2-ubuntu-noble-20241015")
          |> Dagger.Container.with_exec(~w"apt update")
          |> Dagger.Container.with_exec(~w"apt install build-essential tar jq wget --yes")
        
        "musl" ->
          dag()
          |> Dagger.Client.container(platform: plat)
          |> Dagger.Container.from("hexpm/elixir:1.17.3-erlang-27.2-alpine-3.20.3")
          |> Dagger.Container.with_exec(~w"apk add build-base tar jq coreutils")
      end

    out_name =
      case libc do
        "glibc" -> "gnu"
        "musl" -> "musl"
      end

    what_to_build =
      case libc do
        "glibc" -> "linux"
        "musl" -> "linux-musl"
      end

    src = Dagger.Directory.file(c_src_dir, "pdfium_nif.c")
    builds = Dagger.Directory.file(build_scripts_src_dir, "builds.json")
    build_script = Dagger.Directory.file(build_scripts_src_dir, "build-for-linux.sh")

    base
    |> Dagger.Container.with_workdir("/build")
    |> Dagger.Container.with_file("/build/pdfium_nif.c", src)
    |> Dagger.Container.with_file("/build/builds.json", builds)
    |> Dagger.Container.with_file("/build/build-for-linux.sh", build_script)
    |> Dagger.Container.with_exec(~w"./build-for-linux.sh #{what_to_build} #{in_erl_platform} 27.2")
    |> Dagger.Container.file("/build/pdfium-nif-2.17-#{out_erl_platform}-linux-#{out_name}-0.1.0.tar.gz")
  end

  # modify to only accept a path to file to test
  #
  defn test(plat: String.t(), libc: String.t(), build_scripts_src_dir: Dagger.Directory.t(), c_src_dir: Dagger.Directory.t()) :: Dagger.File.t() do
    archive = precompile(plat, libc, build_scripts_src_dir, c_src_dir)

    dag()
    |> Dagger.Client.container(platform: plat)
    |> Dagger.Container.from("hexpm/elixir:1.17.3-erlang-27.2-alpine-3.20.3")
    |> Dagger.Container.with_exec(~w"apk add tar")
    |> Dagger.Container.with_workdir("/test")
    |> Dagger.Container.with_file("/test/archive.tar", archive)
    |> Dagger.Container.with_exec(~w"tar --extract --directory=/test/ --file=/test/archive.tar")
    |> Dagger.Container.with_new_file("/test/test.exs", test_script())
    |> Dagger.Container.with_new_file("/test/test.pdf", test_pdf())
    |> Dagger.Container.with_exec(~w"elixir test.exs")
    |> Dagger.Container.stdout()
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
    3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>endobj
    4 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>endobj
    xref
    0 5
    0000000000 65535 f
    0000000009 00000 n
    0000000053 00000 n
    0000000102 00000 n
    0000000165 00000 n
    trailer<</Size 5/Root 1 0 R>>
    startxref
    228
    %%EOF
    """
  end
end
