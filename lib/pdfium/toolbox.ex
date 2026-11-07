defmodule PDFium.Toolbox do
  @moduledoc """
  Whole jobs built from `PDFium`.

  A job takes documents as paths or `{:bytes, contents}`, opens and closes them
  itself, and answers with the document it made.
  """

  @doc """
  Draws overlays over the pages of `source`, each scaled to fit and centred.

  A placement is `{overlay, page_index}`, pages counted from zero. An overlay
  is drawn by its first page, and placements landing on the same page stack
  in the order given.
  """
  @spec stamp(PDFium.source(), [{PDFium.source(), non_neg_integer()}], PDFium.security()) ::
          {:ok, binary()} | {:error, atom()}
  def stamp(source, placements, security \\ :keep) do
    overlay_sources = placements |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    with_documents([source | overlay_sources], fn [document | overlays] ->
      by_source = Map.new(Enum.zip(overlay_sources, overlays))

      named =
        Enum.map(placements, fn {overlay, page} -> {Map.fetch!(by_source, overlay), 0, page} end)

      with {:ok, pages} <- PDFium.get_page_sizes(document),
           {:ok, sizes} <- sizes_of(overlays),
           {:ok, placed} <- fit_each(named, pages, sizes),
           :ok <- PDFium.stamp(document, placed),
           do: PDFium.save_to_binary(document, security)
    end)
  end

  @doc """
  Draws each page of `overlay_source` over the page of `source` in the same
  place, scaled to fit and centred. The two must have the same number of pages.
  """
  @spec overlay(PDFium.source(), PDFium.source()) :: {:ok, binary()} | {:error, atom()}
  def overlay(source, overlay_source) do
    with_documents([source, overlay_source], fn [document, overlay] ->
      with {:ok, pages} <- PDFium.get_page_sizes(document),
           {:ok, overlay_pages} <- PDFium.get_page_sizes(overlay),
           true <- length(pages) == length(overlay_pages) || {:error, :page_count_mismatch},
           named = Enum.map(0..(length(pages) - 1)//1, &{overlay, &1, &1}),
           {:ok, placed} <- fit_each(named, pages, %{overlay => overlay_pages}),
           :ok <- PDFium.stamp(document, placed),
           do: PDFium.save_to_binary(document)
    end)
  end

  @doc """
  Draws every annotation into the page it sits on and drops it.

  `usage` picks the appearance: `:display` is what a reader shows, `:print`
  what it would print.
  """
  @spec flatten(PDFium.source(), :display | :print, PDFium.security()) ::
          {:ok, binary()} | {:error, atom()}
  def flatten(source, usage \\ :display, security \\ :keep) do
    PDFium.with_document(source, fn document ->
      with {:ok, count} <- PDFium.get_page_count(document),
           :ok <- each_page(count, &PDFium.flatten_page(document, &1, usage)),
           do: PDFium.save_to_binary(document, security)
    end)
  end

  @doc """
  Writes the documents as one, in the order given. A document named twice is
  written twice.
  """
  @spec merge([PDFium.source()]) :: {:ok, binary()} | {:error, atom()}
  def merge([]), do: {:error, :no_documents}

  def merge(sources) do
    with_documents(sources, fn documents ->
      PDFium.with_new_document(fn output ->
        with :ok <- import_each(output, documents), do: PDFium.save_to_binary(output)
      end)
    end)
  end

  @doc """
  Writes the given pages, in the order asked for, as a document of their own.

  Pages are numbered from zero. A page named twice is written twice; naming
  none is refused.
  """
  @spec extract_pages(PDFium.source(), [non_neg_integer()]) :: {:ok, binary()} | {:error, atom()}
  def extract_pages(source, page_indices) do
    PDFium.with_document(source, fn document ->
      PDFium.with_new_document(fn output ->
        with :ok <- PDFium.import_pages(output, document, page_indices, 0),
             do: PDFium.save_to_binary(output)
      end)
    end)
  end

  defp sizes_of(documents) do
    Enum.reduce_while(documents, {:ok, %{}}, fn document, {:ok, sizes} ->
      case PDFium.get_page_sizes(document) do
        {:ok, pages} -> {:cont, {:ok, Map.put(sizes, document, pages)}}
        error -> {:halt, error}
      end
    end)
  end

  defp fit_each(placements, pages, sizes) do
    Enum.reduce_while(placements, {:ok, []}, fn {overlay, overlay_page, page_index},
                                                {:ok, placed} ->
      with {:ok, overlay_size} <- page_at(Map.fetch!(sizes, overlay), overlay_page),
           {:ok, page} <- page_at(pages, page_index) do
        {:cont, {:ok, [{overlay, overlay_page, page_index, fit(overlay_size, page)} | placed]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, placed} -> {:ok, Enum.reverse(placed)}
      error -> error
    end
  end

  defp page_at(pages, index) do
    case Enum.at(pages, index) do
      nil -> {:error, :page_load_failed}
      %{width: width, height: height} when width <= 0 or height <= 0 -> {:error, :empty_page}
      page -> {:ok, page}
    end
  end

  defp fit(%{width: width, height: height}, %{width: page_width, height: page_height}) do
    scale = min(page_width / width, page_height / height)
    {scale, 0.0, 0.0, scale, (page_width - width * scale) / 2, (page_height - height * scale) / 2}
  end

  defp each_page(count, function) do
    Enum.reduce_while(0..(count - 1)//1, :ok, fn index, :ok ->
      case function.(index) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp import_each(output, documents) do
    Enum.reduce_while(documents, {:ok, 0}, fn document, {:ok, at} ->
      with {:ok, count} <- PDFium.get_page_count(document),
           :ok <- PDFium.import_pages(output, document, :all, at) do
        {:cont, {:ok, at + count}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, _at} -> :ok
      error -> error
    end
  end

  defp with_documents(sources, function) do
    opened = Enum.map(sources, &PDFium.open_document/1)

    try do
      case Enum.find(opened, &match?({:error, _reason}, &1)) do
        nil -> function.(Enum.map(opened, fn {:ok, document} -> document end))
        error -> error
      end
    after
      Enum.each(opened, fn
        {:ok, document} -> PDFium.close_document(document)
        _error -> :ok
      end)
    end
  end
end
