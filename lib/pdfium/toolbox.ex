defmodule PDFium.Toolbox do
  @moduledoc """
  Whole jobs, built from the building blocks in `PDFium`.

  Everything here could be written by a caller against `PDFium` itself, and is
  here because more than one caller wanted it. Where a job has to decide
  something the library cannot know — where an overlay belongs on a page, say —
  it is decided here rather than in the binding.

  A job names its documents by path rather than taking them open, and opens and
  closes them itself. Reach for `PDFium` when you want to hold a document open
  across several pieces of work.
  """

  @doc """
  Draws overlays over the pages of `document`, each scaled to fit and centred,
  and writes the result.

  Each placement is `{overlay, page_index}`, with pages counted from zero, and
  each overlay is drawn by its first page. Placements landing on the same page
  stack in the order given.

  `overlay/3` is for an overlay with a page per page of the document.

  Fitting and centring is what makes an overlay drawn at the size of the page it
  goes over land exactly where it was drawn. `PDFium.stamp/3` takes the matrix
  itself for anywhere else.
  """
  @spec stamp(Path.t(), [{Path.t(), non_neg_integer()}], Path.t()) ::
          {:ok, :stamped} | {:error, atom()}
  def stamp(path, placements, output_path) do
    overlay_paths = placements |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    with_documents([path | overlay_paths], fn [document | overlays] ->
      by_path = Map.new(Enum.zip(overlay_paths, overlays))

      named = Enum.map(placements, fn {path, page} -> {Map.fetch!(by_path, path), 0, page} end)

      with {:ok, [pages | overlay_pages]} <- PDFium.get_page_sizes([document | overlays]),
           sizes = overlays |> Enum.zip(overlay_pages) |> Map.new(),
           {:ok, placed} <- fit_each(named, pages, sizes) do
        PDFium.stamp(document, placed, output_path)
      end
    end)
  end

  @spec fit_each(
          [{reference(), non_neg_integer(), non_neg_integer()}],
          [PDFium.page_size()],
          map()
        ) ::
          {:ok, [{reference(), non_neg_integer(), non_neg_integer(), PDFium.placement()}]}
          | {:error, atom()}
  defp fit_each(placements, pages, sizes) do
    Enum.reduce_while(placements, {:ok, []}, fn {overlay, overlay_page, page_index},
                                                {:ok, placed} ->
      with {:ok, overlay_size} <- page_at(Map.fetch!(sizes, overlay), overlay_page),
           {:ok, page} <- page_at(pages, page_index) do
        {:cont, {:ok, placed ++ [{overlay, overlay_page, page_index, fit(overlay_size, page)}]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec page_at([PDFium.page_size()], non_neg_integer()) ::
          {:ok, PDFium.page_size()} | {:error, atom()}
  defp page_at(pages, index) do
    case Enum.at(pages, index) do
      nil -> {:error, :page_load_failed}
      %{width: width, height: height} when width <= 0 or height <= 0 -> {:error, :empty_overlay}
      page -> {:ok, page}
    end
  end

  @spec fit(PDFium.page_size(), PDFium.page_size()) :: PDFium.placement()
  defp fit(%{width: width, height: height}, %{width: page_width, height: page_height}) do
    scale = min(page_width / width, page_height / height)

    {scale, 0.0, 0.0, scale, (page_width - width * scale) / 2, (page_height - height * scale) / 2}
  end

  @doc """
  Draws each page of `overlay` over the page of `document` in the same place.

  This is what a header and footer is: one page per page of the document, each
  carrying that page's own number, and a header only where one belongs. Naming
  the pairing is what the caller would otherwise have to spell out for every
  page, and get right.

  The two must have the same number of pages, which is refused rather than
  guessed at - a mismatch means the overlay was rendered for a different
  document.
  """
  @spec overlay(Path.t(), Path.t(), Path.t()) :: {:ok, :stamped} | {:error, atom()}
  def overlay(path, overlay_path, output_path) do
    with_documents([path, overlay_path], fn [document, overlay] ->
      with {:ok, [pages, overlay_pages]} <- PDFium.get_page_sizes([document, overlay]),
           true <- length(pages) == length(overlay_pages) || {:error, :page_count_mismatch},
           {:ok, placed} <- fit_pairwise(overlay, pages, overlay_pages) do
        PDFium.stamp(document, placed, output_path)
      end
    end)
  end

  @doc """
  Overlays as `overlay/3` does, answering with the document rather than writing
  it out.
  """
  @spec overlay_to_binary(PDFium.source(), PDFium.source()) ::
          {:ok, binary()} | {:error, atom()}
  def overlay_to_binary(source, overlay_source) do
    with_documents([source, overlay_source], fn [document, overlay] ->
      with {:ok, [pages, overlay_pages]} <- PDFium.get_page_sizes([document, overlay]),
           true <- length(pages) == length(overlay_pages) || {:error, :page_count_mismatch},
           {:ok, placed} <- fit_pairwise(overlay, pages, overlay_pages),
           {:ok, :stamped} <- PDFium.stamp_in_place(document, placed) do
        PDFium.save_to_binary(document)
      end
    end)
  end

  @spec fit_pairwise(reference(), [PDFium.page_size()], [PDFium.page_size()]) ::
          {:ok, [{reference(), non_neg_integer(), non_neg_integer(), PDFium.placement()}]}
          | {:error, atom()}
  defp fit_pairwise(overlay, pages, overlay_pages) do
    pages
    |> Enum.zip(overlay_pages)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{page, overlay_page}, index}, {:ok, placed} ->
      if page.width > 0 and page.height > 0 and overlay_page.width > 0 and overlay_page.height > 0 do
        {:cont, {:ok, placed ++ [{overlay, index, index, fit(overlay_page, page)}]}}
      else
        {:halt, {:error, :page_load_failed}}
      end
    end)
  end

  @doc """
  Draws every annotation in a document into the page it sits on and writes the
  result.

  Answers `{:ok, :nothing_to_do}` without writing anything when no page had an
  annotation to draw.
  """
  @spec flatten(Path.t(), Path.t()) ::
          {:ok, :flattened | :nothing_to_do} | {:error, atom()}
  @spec flatten(Path.t(), Path.t(), :display | :print) ::
          {:ok, :flattened | :nothing_to_do} | {:error, atom()}
  def flatten(path, output_path, usage \\ :display) do
    PDFium.with_document(path, fn document ->
      with {:ok, page_count} <- PDFium.get_page_count(document),
           {:ok, drawn?} <- flatten_each(document, page_count, usage) do
        if drawn? do
          with {:ok, :saved} <- PDFium.save(document, output_path), do: {:ok, :flattened}
        else
          {:ok, :nothing_to_do}
        end
      end
    end)
  end

  @spec flatten_each(reference(), non_neg_integer(), :display | :print) ::
          {:ok, boolean()} | {:error, atom()}
  defp flatten_each(document, page_count, usage) do
    Enum.reduce_while(0..(page_count - 1)//1, {:ok, false}, fn index, {:ok, drawn?} ->
      case PDFium.flatten_page(document, index, usage) do
        {:ok, :flattened} -> {:cont, {:ok, true}}
        {:ok, :nothing_to_do} -> {:cont, {:ok, drawn?}}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Writes the named documents as one, in the order named.

  A document named twice is written twice.
  """
  @spec merge([Path.t()], Path.t()) :: {:ok, :merged} | {:error, atom()}
  def merge([], _output_path), do: {:error, :no_documents}

  def merge(paths, output_path) do
    with_documents(paths, fn documents ->
      PDFium.with_new_document(fn output ->
        with {:ok, _at} <- import_each(output, documents),
             {:ok, :saved} <- PDFium.save(output, output_path) do
          {:ok, :merged}
        end
      end)
    end)
  end

  @spec import_each(reference(), [reference()]) :: {:ok, non_neg_integer()} | {:error, atom()}
  defp import_each(output, documents) do
    Enum.reduce_while(documents, {:ok, 0}, fn document, {:ok, at} ->
      with {:ok, count} <- PDFium.get_page_count(document),
           {:ok, :imported} <- PDFium.import_pages(output, document, :all, at) do
        {:cont, {:ok, at + count}}
      else
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Writes the given pages, in the order asked for, as a document of their own.

  Pages are numbered from zero. Naming one twice writes it twice; naming none
  is refused rather than taken to mean all of them.
  """
  @spec extract_pages(Path.t(), [non_neg_integer()], Path.t()) ::
          {:ok, :extracted} | {:error, atom()}
  def extract_pages(path, page_indices, output_path) do
    PDFium.with_document(path, fn document ->
      PDFium.with_new_document(fn output ->
        with {:ok, :imported} <- PDFium.import_pages(output, document, page_indices, 0),
             {:ok, :saved} <- PDFium.save(output, output_path) do
          {:ok, :extracted}
        end
      end)
    end)
  end

  @spec with_documents([Path.t()], ([reference()] -> result)) ::
          result | {:error, PDFium.load_error()}
        when result: term()
  defp with_documents(sources, function) do
    opened = Enum.map(sources, &open/1)

    try do
      case Enum.find(opened, &match?({:error, _reason}, &1)) do
        nil -> function.(Enum.map(opened, fn {:ok, document} -> document end))
        {:error, reason} -> {:error, reason}
      end
    after
      Enum.each(opened, fn
        {:ok, document} -> PDFium.close_document(document)
        {:error, _reason} -> :ok
      end)
    end
  end

  @spec open(PDFium.source()) :: {:ok, reference()} | {:error, atom()}
  defp open({:bytes, contents}), do: PDFium.load_memory_document(contents)
  defp open(path), do: PDFium.load_document(path)
end
