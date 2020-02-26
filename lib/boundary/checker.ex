defmodule Boundary.Checker do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  def errors(view, calls) do
    Enum.concat([
      invalid_deps(view),
      cycles(view),
      unclassified_modules(view),
      invalid_calls(view, calls)
    ])
  end

  defp invalid_deps(view) do
    for boundary <- Boundary.all(view),
        dep <- boundary.deps,
        error = validate_dep(Boundary.get(view, dep), %{name: dep, file: boundary.file, line: boundary.line}),
        into: MapSet.new(),
        do: error
  end

  defp validate_dep(nil, dep), do: {:unknown_dep, dep}
  defp validate_dep(%{ignore?: true}, dep), do: {:ignored_dep, dep}
  defp validate_dep(%{ignore?: false}, _dep), do: nil

  defp cycles(view) do
    graph = :digraph.new([:cyclic])

    try do
      Enum.each(Boundary.all_names(view), &:digraph.add_vertex(graph, &1))

      for boundary <- Boundary.all(view),
          dep <- boundary.deps,
          do: :digraph.add_edge(graph, boundary.name, dep)

      :digraph.vertices(graph)
      |> Stream.map(&:digraph.get_short_cycle(graph, &1))
      |> Stream.reject(&(&1 == false))
      |> Stream.uniq_by(&MapSet.new/1)
      |> Enum.map(&{:cycle, &1})
    after
      :digraph.delete(graph)
    end
  end

  defp unclassified_modules(view), do: Enum.map(Boundary.unclassified_modules(view), &{:unclassified_module, &1})

  defp invalid_calls(view, calls) do
    for call <- calls,
        from_boundary = Boundary.get(view, call.caller_module),
        not from_boundary.ignore?,
        to_boundary = Boundary.get(view, call.callee_module) || :unknown,
        from_boundary != to_boundary,
        {type, to_boundary_name} <- [call_error(view, call, from_boundary, to_boundary)] do
      {:invalid_call,
       %{
         type: type,
         from_boundary: from_boundary.name,
         to_boundary: to_boundary_name,
         callee: call.callee,
         caller: call.caller_module,
         file: call.file,
         line: call.line
       }}
    end
  end

  defp call_error(view, call, from_boundary, to_boundary) do
    if to_boundary == :unknown,
      do: external_app_call_error(view, call, from_boundary),
      else: in_app_call_error(call, from_boundary, to_boundary)
  end

  defp external_app_call_error(view, call, from_boundary) do
    app = Boundary.app(view, call.callee_module)

    if is_nil(app) or external_dep_allowed?(call, from_boundary, app),
      do: nil,
      else: {:invalid_external_dep_call, call.callee_module}
  end

  defp external_dep_allowed?(call, from_boundary, app) do
    externals = from_boundary.externals

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

  defp in_app_call_error(call, from_boundary, to_boundary) do
    cond do
      to_boundary.ignore? -> nil
      not allowed?(from_boundary, to_boundary) -> {:invalid_cross_boundary_call, to_boundary.name}
      not exported?(to_boundary, call.callee_module) -> {:not_exported, to_boundary.name}
      true -> nil
    end
  end

  defp allowed?(from_boundary, to_boundary),
    do: Enum.any?(from_boundary.deps, &(&1 == to_boundary.name))

  defp exported?(boundary, module),
    do: Enum.any?(boundary.exports, &(&1 == module))
end
