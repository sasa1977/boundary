defmodule Boundary.Checker do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  def errors(view, calls) do
    Enum.concat([
      invalid_config(view),
      invalid_deps(view),
      invalid_exports(view),
      cycles(view),
      unclassified_modules(view),
      invalid_calls(view, calls)
    ])
  end

  defp invalid_deps(view) do
    for boundary <- Boundary.all(view),
        {dep, _type} <- boundary.deps,
        error = validate_dep(Boundary.get(view, dep), %{name: dep, file: boundary.file, line: boundary.line}),
        into: MapSet.new(),
        do: error
  end

  defp invalid_config(view), do: view |> Boundary.all() |> Enum.flat_map(& &1.errors)

  defp validate_dep(nil, dep), do: {:unknown_dep, dep}
  defp validate_dep(%{ignore?: true}, dep), do: {:ignored_dep, dep}
  defp validate_dep(_boundary, _dep), do: nil

  defp invalid_exports(view) do
    for boundary <- Boundary.all(view),
        export <- boundary.exports,
        error = validate_export(view, boundary, %{name: export, file: boundary.file, line: boundary.line}),
        into: MapSet.new(),
        do: error
  end

  defp validate_export(view, %{name: boundary_name} = boundary, export) do
    cond do
      is_nil(Boundary.app(view, export.name)) ->
        {:unknown_export, export}

      match?(%{ancestors: [^boundary_name | _]}, Boundary.get(view, export.name)) ->
        nil

      (Boundary.for_module(view, export.name) || %{name: nil}).name != boundary.name ->
        {:export_not_in_boundary, export}

      true ->
        nil
    end
  end

  defp cycles(view) do
    graph = :digraph.new([:cyclic])

    try do
      Enum.each(Boundary.all_names(view), &:digraph.add_vertex(graph, &1))

      for boundary <- Boundary.all(view),
          {dep, _type} <- boundary.deps,
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
        to_boundaries = to_boundaries(view, call),
        {type, to_boundary_name} <- [call_error(view, call, from_boundary, to_boundaries)] do
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

  defp to_boundaries(view, call) do
    to_boundary = Boundary.for_module(view, call.callee_module)

    # main sub-boundary module may also be exported by its parent
    parent_boundary =
      if not is_nil(to_boundary) and call.callee_module == to_boundary.name,
        do: Boundary.parent(view, to_boundary)

    Enum.reject([to_boundary, parent_boundary], &is_nil/1)
  end

  defp call_error(view, call, from_boundary, []) do
    if check_external_dep?(view, call, from_boundary),
      do: {:invalid_external_dep_call, call.callee_module},
      else: nil
  end

  defp call_error(view, call, from_boundary, [_ | _] = to_boundaries) do
    errors = Enum.map(to_boundaries, &call_error(view, call, from_boundary, &1))
    unless Enum.any?(errors, &is_nil/1), do: Enum.find(errors, &(not is_nil(&1)))
  end

  defp call_error(view, call, from_boundary, to_boundary) do
    cond do
      to_boundary.ignore? -> nil
      to_boundary == from_boundary -> nil
      cross_app_call?(view, call) and not check_external_dep?(view, call, from_boundary) -> nil
      not allowed?(from_boundary, to_boundary, call) -> invalid_cross_call_error(call, from_boundary, to_boundary)
      not exported?(to_boundary, call.callee_module) -> {:not_exported, to_boundary.name}
      true -> nil
    end
  end

  defp check_external_dep?(view, call, from_boundary) do
    Boundary.app(view, call.callee_module) != :boundary and
      (from_boundary.externals_mode == :strict or
         Enum.member?(from_boundary.externals, Boundary.app(view, call.callee_module)))
  end

  defp allowed?(from_boundary, %{name: name}, call) do
    Enum.any?(
      from_boundary.deps,
      fn
        {^name, :runtime} -> true
        {^name, :compile} -> compile_time_call?(call)
        _ -> false
      end
    )
  end

  defp compile_time_call?(%{mode: :compile}), do: true
  defp compile_time_call?(%{caller: {module, name, arity}}), do: macro_exported?(module, name, arity)
  defp compile_time_call?(_), do: false

  defp invalid_cross_call_error(call, from_boundary, to_boundary) do
    tag =
      if call.mode == :runtime and Enum.member?(from_boundary.deps, {to_boundary.name, :compile}),
        do: :runtime,
        else: :call

    {tag, to_boundary.name}
  end

  defp cross_app_call?(view, call),
    do: Boundary.app(view, call.caller_module) != Boundary.app(view, call.callee_module)

  defp exported?(boundary, module),
    do: boundary.implicit? or Enum.any?(boundary.exports, &(&1 == module))
end
