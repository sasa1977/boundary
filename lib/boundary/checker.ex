defmodule Boundary.Checker do
  @moduledoc false

  @type call :: %{
          callee: mfa,
          callee_module: module,
          caller_module: module,
          file: String.t(),
          line: pos_integer
        }

  @type error ::
          {:invalid_deps, [{:unknown | :ignored, Boundary.name()}]}
          | {:cycles, [Boundary.name()]}
          | {:unclassified_modules, [module]}
          | {:empty_boundaries, [Boundary.name()]}
          | {:invalid_calls, [call]}

  @spec check(application: Boundary.application(), calls: [call]) :: :ok | {:error, error}
  def check(opts \\ []) do
    app = Keyword.get_lazy(opts, :application, &current_app/0)

    with :ok <- check_valid_deps(app.boundaries),
         :ok <- check_cycles(app.boundaries),
         :ok <- check_unclassified_modules(app.modules.unclassified),
         :ok <- check_empty_boundaries(app.boundaries, app.modules.classified),
         do: check_calls(app.boundaries, app.modules.classified, Keyword.get_lazy(opts, :calls, &calls/0))
  end

  defp current_app do
    app = Keyword.fetch!(Mix.Project.config(), :app)
    Application.load(app)
    Boundary.application(app)
  end

  @doc false
  def calls do
    Mix.Tasks.Xref.calls()
    |> Stream.map(fn %{callee: {mod, _fun, _arg}} = entry -> Map.put(entry, :callee_module, mod) end)
    |> Enum.reject(&(&1.callee_module == &1.caller_module))
    |> resolve_duplicates()
  end

  defp resolve_duplicates(calls) do
    # If there is a call from `Foo.Bar`, xref may include two entries, one with `Foo` and another with `Foo.Bar` as the
    # caller. In such case, we'll consider only the call with the "deepest" caller (i.e. `Foo.Bar`).

    calls
    |> Enum.group_by(&{&1.file, &1.line, &1.callee})
    |> Enum.map(fn {_, calls} -> Enum.max_by(calls, &String.length(inspect(&1.caller_module))) end)
  end

  defp check_valid_deps(boundaries) do
    boundaries
    |> Stream.flat_map(fn {_boundary, data} -> data.deps end)
    |> Stream.map(&validate_dep(boundaries, &1))
    |> Stream.reject(&is_nil/1)
    |> Stream.uniq()
    |> Enum.sort()
    |> case do
      [] -> :ok
      invalid_deps -> {:error, {:invalid_deps, invalid_deps}}
    end
  end

  defp validate_dep(boundaries, dep) do
    cond do
      not Map.has_key?(boundaries, dep) -> {:unknown, dep}
      Map.fetch!(boundaries, dep).ignore? -> {:ignored, dep}
      true -> nil
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

  defp check_unclassified_modules([]), do: :ok
  defp check_unclassified_modules(unclassified_modules), do: {:error, {:unclassified_modules, unclassified_modules}}

  defp check_empty_boundaries(boundaries, classified_modules) do
    all_boundaries = boundaries |> Map.keys() |> MapSet.new()
    used_boundaries = classified_modules |> Map.values() |> MapSet.new()
    empty_boundaries = MapSet.difference(all_boundaries, used_boundaries)

    if MapSet.size(empty_boundaries) == 0,
      do: :ok,
      else: {:error, {:empty_boundaries, empty_boundaries |> Enum.sort()}}
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
      Map.fetch!(boundaries, from_boundary).ignore? or Map.fetch!(boundaries, to_boundary).ignore? ->
        nil

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

  defp exported?(boundaries, boundary, module), do: Enum.any?(Map.fetch!(boundaries, boundary).exports, &(&1 == module))
end
