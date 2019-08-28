defmodule Boundary.Checker do
  @moduledoc false

  def check(boundaries, app_modules, calls) do
    with :ok <- check_duplicates(boundaries),
         boundaries = Map.new(boundaries),
         :ok <- check_valid_deps(boundaries),
         :ok <- check_cycles(boundaries),
         {:ok, classified_modules} <- classify_modules(boundaries, app_modules),
         :ok <- check_unused_boundaries(boundaries, classified_modules),
         do: check_calls(boundaries, classified_modules, calls)
  end

  defp check_duplicates(normalized_boundaries) do
    for {boundary, _} <- normalized_boundaries, reduce: %{} do
      histogram -> Map.update(histogram, boundary, 1, &(&1 + 1))
    end
    |> Stream.filter(fn {_boundary, count} -> count > 1 end)
    |> Stream.map(fn {boundary, _count} -> boundary end)
    |> Enum.sort()
    |> case do
      [] -> :ok
      duplicates -> {:error, {:duplicate_boundaries, duplicates}}
    end
  end

  defp check_valid_deps(boundaries) do
    boundaries
    |> Stream.flat_map(fn {boundary, data} -> Stream.map(data.deps, &{boundary, &1}) end)
    |> Stream.reject(fn {_boundary, dep} -> Map.has_key?(boundaries, dep) end)
    |> Stream.map(fn {_boundary, dep} -> dep end)
    |> Stream.uniq()
    |> Enum.sort()
    |> case do
      [] -> :ok
      invalid_deps -> {:error, {:invalid_deps, invalid_deps}}
    end
  end

  defp check_cycles(boundaries) do
    graph = :digraph.new([:cyclic])

    try do
      Enum.each(Map.keys(boundaries), &:digraph.add_vertex(graph, &1))

      boundaries
      |> Stream.flat_map(fn {boundary, data} -> Stream.map(data.deps, &{boundary, &1}) end)
      |> Enum.each(fn {boundary, dep} -> false = match?({:error, _}, :digraph.add_edge(graph, boundary, dep)) end)

      :digraph.vertices(graph)
      |> Stream.map(&:digraph.get_short_cycle(graph, &1))
      |> Stream.reject(&(&1 == false))
      |> Enum.uniq_by(&MapSet.new/1)
      |> Enum.sort_by(&length/1)
      |> case do
        [] -> :ok
        cycles -> {:error, {:cycles, cycles}}
      end
    after
      :digraph.delete(graph)
    end
  end

  defp classify_modules(boundaries, app_modules) do
    boundaries_search_space =
      boundaries
      |> Map.keys()
      |> Enum.sort(&>=/2)
      |> Enum.map(&%{name: &1, parts: Module.split(&1)})

    Enum.reduce(
      app_modules,
      {%{}, []},
      fn module, {classified, unclassified} ->
        parts = Module.split(module)

        case Enum.find(boundaries_search_space, &List.starts_with?(parts, &1.parts)) do
          nil -> {classified, [module | unclassified]}
          boundary -> {Map.put(classified, module, boundary.name), unclassified}
        end
      end
    )
    |> case do
      {classified, []} -> {:ok, classified}
      {_classified, unclassified} -> {:error, {:unclassified_modules, unclassified}}
    end
  end

  defp check_unused_boundaries(boundaries, classified_modules) do
    all_boundaries = boundaries |> Map.keys() |> MapSet.new()
    used_boundaries = classified_modules |> Map.values() |> MapSet.new()
    unused_boundaries = MapSet.difference(all_boundaries, used_boundaries)

    if MapSet.size(unused_boundaries) == 0,
      do: :ok,
      else: {:error, {:unused_boundaries, unused_boundaries |> Enum.sort()}}
  end

  defp check_calls(boundaries, classified_modules, calls) do
    calls
    |> Stream.filter(&Map.has_key?(classified_modules, &1.callee_module))
    |> Enum.sort_by(&{&1.file, &1.line})
    |> Stream.map(&check_call(&1, boundaries, classified_modules))
    |> Stream.reject(&is_nil/1)
    |> Enum.sort_by(&{&1.file, &1.line})
    |> case do
      [] -> :ok
      invalid_calls -> {:error, {:invalid_calls, invalid_calls}}
    end
  end

  defp check_call(entry, boundaries, classified_modules) do
    from_boundary = Map.fetch!(classified_modules, entry.caller_module)
    to_boundary = Map.fetch!(classified_modules, entry.callee_module)

    cond do
      not allowed?(boundaries, from_boundary, to_boundary) ->
        %{
          type: :invalid_cross_boundary_call,
          from_boundary: from_boundary,
          to_boundary: to_boundary,
          callee: entry.callee,
          file: entry.file,
          line: entry.line
        }

      from_boundary != to_boundary and not exported?(boundaries, to_boundary, entry.callee_module) ->
        %{
          type: :not_exported,
          boundary: to_boundary,
          callee: entry.callee,
          file: entry.file,
          line: entry.line
        }

      true ->
        nil
    end
  end

  defp allowed?(boundaries, from_boundary, to_boundary) do
    from_boundary == to_boundary or
      Enum.any?(Map.fetch!(boundaries, from_boundary).deps, &(&1 == to_boundary))
  end

  defp exported?(_boundaries, boundary, boundary), do: true
  defp exported?(boundaries, boundary, module), do: Enum.any?(Map.fetch!(boundaries, boundary).exports, &(&1 == module))
end
