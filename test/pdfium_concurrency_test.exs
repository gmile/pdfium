defmodule PDFiumConcurrencyTest do
  use ExUnit.Case

  @pdf_path Path.expand("../custom/test.pdf", __DIR__)

  test "concurrent load/close does not corrupt PDFium state" do
    concurrency = System.schedulers_online() * 4
    iterations = 200

    errors = :counters.new(1, [:atomics])

    1..concurrency
    |> Enum.map(fn _ ->
      Task.async(fn ->
        for _ <- 1..iterations do
          case PDFium.load_document(@pdf_path) do
            {:ok, doc} ->
              PDFium.get_page_count(doc)
              PDFium.close_document(doc)

            {:error, _code} ->
              :counters.add(errors, 1, 1)
          end
        end
      end)
    end)
    |> Task.await_many(:infinity)

    assert :counters.get(errors, 1) == 0

    # Verify PDFium is still healthy after stress
    assert {:ok, doc} = PDFium.load_document(@pdf_path)
    assert {:ok, _pages} = PDFium.get_page_count(doc)
    assert :ok = PDFium.close_document(doc)
  end

  describe "dropping a document while another caller renders" do
    setup do
      path =
        Path.join(System.tmp_dir!(), "pdfium-heavy-#{System.unique_integer([:positive])}.pdf")

      on_exit(fn -> File.rm(path) end)

      {:ok, heavy} =
        path |> PDFium.Test.Document.write!([[content: curves(20_000)]]) |> PDFium.load_document()

      on_exit(fn -> PDFium.close_document(heavy) end)
      {:ok, _, _, _} = PDFium.get_page_bitmap(heavy, 0, 300)
      {render_us, {:ok, _, _, _}} = :timer.tc(fn -> PDFium.get_page_bitmap(heavy, 0, 300) end)

      {:ok, heavy: heavy, render_us: render_us}
    end

    test "does not wait for the render when the document was closed", context do
      assert drop_us(context, fn document -> PDFium.close_document(document) end) <
               div(context.render_us, 4)
    end

    test "does not wait for the render when the document was never closed", context do
      assert drop_us(context, fn _document -> :ok end) < div(context.render_us, 4)

      assert {:ok, document} = PDFium.load_memory_document(File.read!(@pdf_path))
      assert {:ok, _pages} = PDFium.get_page_count(document)
    end
  end

  defp drop_us(%{heavy: heavy}, before_drop) do
    test = self()

    holder =
      spawn(fn ->
        {:ok, document} = PDFium.load_memory_document(File.read!(@pdf_path))
        before_drop.(document)
        Process.put(:document, document)
        send(test, :ready)

        receive do
          :drop -> :ok
        end
      end)

    holder_ref = Process.monitor(holder)
    assert_receive :ready

    renderer =
      spawn_link(fn ->
        send(test, :rendering)
        PDFium.get_page_bitmap(heavy, 0, 300)
      end)

    assert_receive :rendering
    Process.sleep(20)

    {us, _} =
      :timer.tc(fn ->
        send(holder, :drop)
        assert_receive {:DOWN, ^holder_ref, _, _, _}, 10_000
      end)

    renderer_ref = Process.monitor(renderer)
    assert_receive {:DOWN, ^renderer_ref, _, _, _}, 10_000

    us
  end

  defp curves(count) do
    for i <- 1..count, into: "" do
      x = rem(i * 37, 560)
      y = rem(i * 53, 740)

      "0.#{rem(i, 9)} g #{x} #{y} m #{x + 40} #{y + 7} #{x + 3} #{y + 45} #{x + 30} #{y + 30} c #{x + 9} #{y + 2} l h f\n"
    end
  end
end
