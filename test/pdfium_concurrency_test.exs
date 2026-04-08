defmodule PDFiumConcurrencyTest do
  use ExUnit.Case

  @pdf_path "minimal.pdf"

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
end
