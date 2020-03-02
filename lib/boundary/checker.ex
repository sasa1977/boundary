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
  defp validate_dep(_boundary, _dep), do: nil

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
        from_boundary = Boundary.for_module(view, call.caller_module),
        not from_boundary.ignore?,
        to_boundary = Boundary.for_module(view, call.callee_module) || :unknown,
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

  defp call_error(view, call, from_boundary, :unknown) do
    if check_external_dep?(view, call, from_boundary),
      do: {:invalid_external_dep_call, call.callee_module},
      else: nil
  end

  defp call_error(view, call, from_boundary, to_boundary) do
    cond do
      to_boundary.ignore? -> nil
      cross_app_call?(view, call) and not check_external_dep?(view, call, from_boundary) -> nil
      not allowed?(from_boundary, to_boundary) -> {:invalid_cross_boundary_call, to_boundary.name}
      not exported?(to_boundary, call.callee_module) -> {:not_exported, to_boundary.name}
      true -> nil
    end
  end

  defp check_external_dep?(view, call, from_boundary) do
    Boundary.app(view, call.callee_module) != :boundary and
      (from_boundary.externals_mode == :strict or
         Enum.member?(from_boundary.externals, Boundary.app(view, call.callee_module)))
  end

  defp allowed?(from_boundary, to_boundary), do: Enum.any?(from_boundary.deps, &(&1 == to_boundary.name))

  defp cross_app_call?(view, call),
    do: Boundary.app(view, call.caller_module) != Boundary.app(view, call.callee_module)

  defp exported?(boundary, module),
    do: boundary.implicit? or Enum.any?(boundary.exports, &(&1 == module))
end
