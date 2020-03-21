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
        {dep, type} <- boundary.deps,
        error = validate_dep(view, boundary, dep, type),
        error != :ok,
        into: MapSet.new(),
        do: error
  end

  defp invalid_config(view), do: view |> Boundary.all() |> Enum.flat_map(& &1.errors)

  defp validate_dep(view, from_boundary, dep, type) do
    with {:ok, to_boundary} <- fetch_dep_boundary(view, from_boundary, dep),
         :ok <- validate_dep_not_ignored(from_boundary, to_boundary),
         do: validate_dep_allowed(view, from_boundary, to_boundary, type)
  end

  defp fetch_dep_boundary(view, from_boundary, dep) do
    case Boundary.get(view, dep) do
      nil -> {:unknown_dep, %{name: dep, file: from_boundary.file, line: from_boundary.line}}
      to_boundary -> {:ok, to_boundary}
    end
  end

  defp validate_dep_not_ignored(from_boundary, to_boundary) do
    if to_boundary.ignore?,
      do: {:ignored_dep, %{name: to_boundary.name, file: from_boundary.file, line: from_boundary.line}},
      else: :ok
  end

  defp validate_dep_allowed(_view, from_boundary, from_boundary, _type),
    do: {:forbidden_dep, %{name: from_boundary.name, file: from_boundary.file, line: from_boundary.line}}

  defp validate_dep_allowed(view, from_boundary, to_boundary, type) do
    parent_boundary = Boundary.parent(view, from_boundary)

    # a boundary can depend on its sibling or a dep of its parent
    if parent_boundary == Boundary.parent(view, to_boundary) or
         (not is_nil(parent_boundary) and {to_boundary.name, type} in parent_boundary.deps),
       do: :ok,
       else: {:forbidden_dep, %{name: to_boundary.name, file: from_boundary.file, line: from_boundary.line}}
  end

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

      # boundary can export top-level module of its direct child sub-boundary
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

  defp call_error(_view, _call, %{ignore?: true}, _to_boundaries), do: nil

  defp call_error(view, call, from_boundary, []) do
    # If we end up here, we couldn't determine a target boundary, so this is either a cross-app call, or a call
    # to an unclassified boundary. In the former case we'll report an error if the externals_mode is strict. In the
    # latter case, we won't report an error.
    if cross_app_call?(view, call) and check_external_dep?(view, call, from_boundary),
      do: {:invalid_external_dep_call, call.callee_module},
      else: nil
  end

  defp call_error(view, call, from_boundary, [_ | _] = to_boundaries) do
    errors = Enum.map(to_boundaries, &call_error(view, call, from_boundary, &1))

    # if call to at least one candidate to_boundary is allowed, this succeeds
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

  defp allowed?(%{name: parent}, %{ancestors: [parent | _]}, _call), do: true

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
