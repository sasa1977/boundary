defmodule Boundary.Checker do
  @moduledoc false

  @type error ::
          {:unknown_dep, dep_error}
          | {:ignored_dep, dep_error}
          | {:cycle, [Boundary.name()]}
          | {:unclassified_module, [module]}
          | {:invalid_call, [Boundary.call()]}

  @type dep_error :: %{name: Boundary.name(), file: String.t(), line: pos_integer}

  @spec errors(application: Boundary.application(), calls: [Boundary.call()]) :: [error]
  def errors(opts \\ []) do
    app = Keyword.get_lazy(opts, :application, &current_app/0)

    Enum.concat([
      invalid_deps(app.boundaries),
      cycles(app.boundaries),
      unclassified_modules(app.modules.unclassified),
      invalid_calls(app.boundaries, app.modules.classified, Keyword.fetch!(opts, :calls))
    ])
  end

  defp current_app do
    app = Keyword.fetch!(Mix.Project.config(), :app)
    Application.load(app)
    Boundary.application(app)
  end

  defp invalid_deps(boundaries) do
    boundaries
    |> Stream.flat_map(fn {_boundary, data} -> Enum.map(data.deps, &%{name: &1, file: data.file, line: data.line}) end)
    |> Stream.map(&validate_dep(boundaries, &1))
    |> Stream.reject(&is_nil/1)
    |> Stream.uniq()
  end

  defp validate_dep(boundaries, dep) do
    cond do
      not Map.has_key?(boundaries, dep.name) -> {:unknown_dep, dep}
      Map.fetch!(boundaries, dep.name).ignore? -> {:ignored_dep, dep}
      true -> nil
    end
  end

  defp cycles(boundaries) do
    graph = :digraph.new([:cyclic])

    try do
      Enum.each(Map.keys(boundaries), &:digraph.add_vertex(graph, &1))

      boundaries
      |> Stream.flat_map(fn {boundary, data} -> Stream.map(data.deps, &{boundary, &1}) end)
      |> Enum.each(fn {boundary, dep} -> :digraph.add_edge(graph, boundary, dep) end)

      :digraph.vertices(graph)
      |> Stream.map(&:digraph.get_short_cycle(graph, &1))
      |> Stream.reject(&(&1 == false))
      |> Stream.uniq_by(&MapSet.new/1)
      |> Enum.map(&{:cycle, &1})
    after
      :digraph.delete(graph)
    end
  end

  defp unclassified_modules(unclassified_modules) do
    unclassified_modules
    |> Stream.reject(& &1.protocol_impl?)
    |> Stream.map(&{:unclassified_module, &1.name})
  end

  defp invalid_calls(boundaries, classified_modules, calls) do
    calls
    |> Stream.filter(&Map.has_key?(classified_modules, &1.callee_module))
    |> Stream.filter(&Map.has_key?(classified_modules, &1.caller_module))
    |> Enum.sort_by(&{&1.file, &1.line})
    |> Stream.map(&call_error(&1, boundaries, classified_modules))
    |> Stream.reject(&is_nil/1)
    |> Stream.map(&{:invalid_call, &1})
  end

  defp call_error(entry, boundaries, classified_modules) do
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
          caller: entry.caller_module,
          file: entry.file,
          line: entry.line
        }

      from_boundary != to_boundary and not exported?(boundaries, to_boundary, entry.callee_module) ->
        %{
          type: :not_exported,
          boundary: to_boundary,
          caller: entry.caller_module,
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
