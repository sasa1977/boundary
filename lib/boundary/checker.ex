defmodule Boundary.Checker do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  def errors(spec, calls) do
    Enum.concat([
      invalid_deps(spec),
      cycles(spec),
      unclassified_modules(spec),
      invalid_calls(spec, calls)
    ])
  end

  defp invalid_deps(spec) do
    spec.boundaries
    |> Stream.flat_map(fn {_boundary, data} -> Enum.map(data.deps, &%{name: &1, file: data.file, line: data.line}) end)
    |> Stream.map(&validate_dep(spec, &1))
    |> Stream.reject(&is_nil/1)
    |> Stream.uniq()
  end

  defp validate_dep(spec, dep) do
    cond do
      not Map.has_key?(spec.boundaries, dep.name) -> {:unknown_dep, dep}
      Map.fetch!(spec.boundaries, dep.name).ignore? -> {:ignored_dep, dep}
      true -> nil
    end
  end

  defp cycles(spec) do
    graph = :digraph.new([:cyclic])

    try do
      Enum.each(Map.keys(spec.boundaries), &:digraph.add_vertex(graph, &1))

      spec.boundaries
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

  defp unclassified_modules(spec) do
    spec.modules.unclassified
    |> Stream.reject(& &1.protocol_impl?)
    |> Stream.map(&{:unclassified_module, &1.name})
  end

  defp invalid_calls(spec, calls) do
    for call <- calls,
        from_boundary = Map.get(spec.modules.classified, call.caller_module),
        not is_nil(from_boundary) and not Map.fetch!(spec.boundaries, from_boundary).ignore?,
        to_boundary = Map.get(spec.modules.classified, call.callee_module, :unknown),
        from_boundary != to_boundary,
        {type, to_boundary} <- [call_error(spec, call, from_boundary, to_boundary)] do
      {:invalid_call,
       %{
         type: type,
         from_boundary: from_boundary,
         to_boundary: to_boundary,
         callee: call.callee,
         caller: call.caller_module,
         file: call.file,
         line: call.line
       }}
    end
  end

  defp call_error(spec, call, from_boundary, to_boundary) do
    if to_boundary == :unknown,
      do: external_app_call_error(spec, call, from_boundary),
      else: in_app_call_error(spec, call, from_boundary, to_boundary)
  end

  defp external_app_call_error(spec, call, from_boundary) do
    app = Map.get(spec.module_to_app, call.callee_module)

    if is_nil(app) or external_dep_allowed?(spec, call, from_boundary, app),
      do: nil,
      else: {:invalid_external_dep_call, call.callee_module}
  end

  defp external_dep_allowed?(spec, call, from_boundary, app) do
    externals = Map.fetch!(spec.boundaries, from_boundary).externals

    case Map.fetch(externals, app) do
      :error ->
        true

      {:ok, {:only, allowed}} ->
        Enum.any?(allowed, &prefix?(Module.split(&1), Module.split(call.callee_module)))

      {:ok, {:except, forbidden}} ->
        not Enum.any?(forbidden, &prefix?(Module.split(&1), Module.split(call.callee_module)))
    end
  end

  defp prefix?([], _), do: true
  defp prefix?([head | tail1], [head | tail2]), do: prefix?(tail1, tail2)
  defp prefix?(_, _), do: false

  defp in_app_call_error(spec, call, from_boundary, to_boundary) do
    cond do
      Map.fetch!(spec.boundaries, to_boundary).ignore? -> nil
      not allowed?(spec.boundaries, from_boundary, to_boundary) -> {:invalid_cross_boundary_call, to_boundary}
      not exported?(spec.boundaries, to_boundary, call.callee_module) -> {:not_exported, to_boundary}
      true -> nil
    end
  end

  defp allowed?(boundaries, from_boundary, to_boundary),
    do: Enum.any?(Map.fetch!(boundaries, from_boundary).deps, &(&1 == to_boundary))

  defp exported?(boundaries, boundary, module),
    do: Enum.any?(Map.fetch!(boundaries, boundary).exports, &(&1 == module))
end
