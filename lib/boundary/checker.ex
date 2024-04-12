# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Boundary.Checker do
  @moduledoc false

  def errors(view, references) do
    Enum.concat([
      invalid_config(view),
      invalid_ignores(view),
      ancestor_with_ignored_checks(view),
      invalid_deps(view),
      invalid_exports(view),
      cycles(view),
      unclassified_modules(view),
      invalid_references(view, references),
      unused_dirty_xrefs(view, references)
    ])
    |> Enum.uniq_by(fn
      # deduping by reference minus type/mode, because even if those vary the error can still be the same
      {:invalid_reference, data} -> update_in(data.reference, &Map.drop(&1, [:type, :mode]))
      other -> other
    end)
  end

  defp invalid_deps(view) do
    for boundary <- Boundary.all(view),
        {dep, type} <- boundary.deps,
        error = validate_dep(view, boundary, dep, type),
        error != :ok,
        do: error
  end

  defp invalid_config(view), do: view |> Boundary.all() |> Enum.flat_map(& &1.errors)

  defp invalid_ignores(view) do
    for boundary <- Boundary.all(view),
        boundary.app == view.main_app,
        not boundary.check.in or not boundary.check.out,
        not Enum.empty?(boundary.ancestors),
        do: {:invalid_ignores, boundary}
  end

  defp ancestor_with_ignored_checks(view) do
    for boundary <- Boundary.all(view),
        boundary.app == view.main_app,
        ancestor <- Enum.map(boundary.ancestors, &Boundary.fetch!(view, &1)),
        not ancestor.check.in or not ancestor.check.out,
        do: {:ancestor_with_ignored_checks, boundary, ancestor}
  end

  defp validate_dep(view, from_boundary, dep, type) do
    with {:ok, to_boundary} <- fetch_dep_boundary(view, from_boundary, dep),
         :ok <- validate_dep_check_in(from_boundary, to_boundary),
         do: validate_dep_allowed(view, from_boundary, to_boundary, type)
  end

  defp fetch_dep_boundary(view, from_boundary, dep) do
    case Boundary.get(view, dep) do
      nil -> {:unknown_dep, %{name: dep, file: from_boundary.file, line: from_boundary.line}}
      to_boundary -> {:ok, to_boundary}
    end
  end

  defp validate_dep_check_in(from_boundary, to_boundary) do
    if to_boundary.check.in,
      do: :ok,
      else: {:check_in_false_dep, %{name: to_boundary.name, file: from_boundary.file, line: from_boundary.line}}
  end

  defp validate_dep_allowed(_view, from_boundary, from_boundary, _type),
    do: {:forbidden_dep, %{name: from_boundary.name, file: from_boundary.file, line: from_boundary.line}}

  defp validate_dep_allowed(view, from_boundary, to_boundary, type) do
    parent_boundary = Boundary.parent(view, from_boundary)

    # a boundary can depend on its parent, sibling, or a dep of its parent
    if parent_boundary == to_boundary or
         parent_boundary == Boundary.parent(view, to_boundary) or
         (not is_nil(parent_boundary) and {to_boundary.name, type} in parent_boundary.deps),
       do: :ok,
       else: {:forbidden_dep, %{name: to_boundary.name, file: from_boundary.file, line: from_boundary.line}}
  end

  defp invalid_exports(view) do
    for boundary <- Boundary.all(view),
        export <- exports_to_check(boundary),
        error = validate_export(view, boundary, export),
        into: MapSet.new(),
        do: error
  end

  defp exports_to_check(boundary) do
    Enum.flat_map(
      boundary.exports,
      fn
        export when is_atom(export) -> [export]
        {root, opts} -> Enum.map(Keyword.get(opts, :except, []), &Module.concat(root, &1))
      end
    )
  end

  defp validate_export(view, boundary, export) do
    cond do
      is_nil(Boundary.app(view, export)) ->
        {:unknown_export, %{name: export, file: boundary.file, line: boundary.line}}

      # boundary can re-export exports of its descendants
      exported_by_child_subboundary?(view, boundary, export) ->
        nil

      (Boundary.for_module(view, export) || %{name: nil}).name != boundary.name ->
        {:export_not_in_boundary, %{name: export, file: boundary.file, line: boundary.line}}

      true ->
        nil
    end
  end

  defp exported_by_child_subboundary?(view, boundary, export) do
    case Boundary.for_module(view, export) do
      nil ->
        false

      owner_boundary ->
        # Start with `owner_boundary`, go up the ancestors chain, and find the immediate child of `boundary`
        owner_boundary
        |> Stream.iterate(&Boundary.parent(view, &1))
        |> Stream.take_while(&(not is_nil(&1)))
        |> Enum.find(&(Enum.at(&1.ancestors, 0) == boundary.name))
        |> case do
          nil -> false
          child_subboundary -> export in [child_subboundary.name | child_subboundary.exports]
        end
    end
  end

  defp cycles(view) do
    graph = :digraph.new([:cyclic])

    try do
      Enum.each(Boundary.all(view), &:digraph.add_vertex(graph, &1.name))

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

  defp invalid_references(view, references) do
    for reference <- references,
        not unclassified_protocol_impl?(view, reference),

        # Ignore protocol impl refs to protocol. These refs always exist, but due to classification
        # of the impl, they may belong to different boundaries
        not reference_to_implemented_protocol?(view, reference),
        from_boundary = Boundary.for_module(view, reference.from),
        from_boundary != nil,
        from_boundary.check.aliases or reference.type != :alias_reference,
        to_boundaries = to_boundaries(view, from_boundary, reference),
        {type, to_boundary_name} <- [reference_error(view, reference, from_boundary, to_boundaries)] do
      {:invalid_reference,
       %{
         type: type,
         from_boundary: from_boundary.name,
         to_boundary: to_boundary_name,
         reference: reference
       }}
    end
  end

  defp unclassified_protocol_impl?(view, reference) do
    Boundary.protocol_impl?(view, reference.from) and
      Boundary.Definition.classified_to(reference.from, view.boundary_defs) == nil
  end

  defp reference_to_implemented_protocol?(view, reference),
    do: Boundary.protocol_impl?(view, reference.from) and reference.from.__impl__(:protocol) == reference.to

  defp to_boundaries(view, from_boundary, reference) do
    case Boundary.for_module(view, reference.to) do
      nil ->
        []

      boundary ->
        target_boundaries =
          boundary.ancestors
          |> Enum.reject(&(&1 == from_boundary.name))
          |> Enum.map(&Boundary.fetch!(view, &1))

        [boundary | target_boundaries]
    end
  end

  defp reference_error(_view, _reference, %{check: %{out: false}}, _to_boundaries), do: nil

  defp reference_error(view, reference, from_boundary, []) do
    # If we end up here, we couldn't determine a target boundary, so this is either a cross-app ref, or a ref
    # to an unclassified boundary. In the former case we'll report an error if the type is strict. In the
    # latter case, we won't report an error.
    if cross_app_ref?(view, reference) and check_external_dep?(view, reference, from_boundary),
      do: {:invalid_external_dep_call, reference.to},
      else: nil
  end

  defp reference_error(view, reference, from_boundary, [_ | _] = to_boundaries) do
    errors = Enum.map(to_boundaries, &reference_error(view, reference, from_boundary, &1))

    # if reference to at least one candidate to_boundary is allowed, this succeeds
    unless Enum.any?(errors, &is_nil/1), do: Enum.find(errors, &(not is_nil(&1)))
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp reference_error(view, reference, from_boundary, to_boundary) do
    cond do
      not to_boundary.check.in ->
        nil

      to_boundary == from_boundary ->
        nil

      Boundary.protocol_impl?(view, reference.to) ->
        # We can enter here when there's `defimpl SomeProtocol, for: Type`. In this case, the caller
        # is `SomeProtocol`, while the callee is `SomeProtocol.Type`. This is never an error, so
        # we're ignoring this case.
        nil

      # explicitly allowed dirty refs
      Enum.member?(from_boundary.dirty_xrefs, reference.to) ->
        nil

      not cross_ref_allowed?(view, from_boundary, to_boundary, reference) ->
        tag = if Enum.member?(from_boundary.deps, {to_boundary.name, :compile}), do: :runtime, else: :normal
        {tag, to_boundary.name}

      not exported?(view, to_boundary, reference.to) ->
        {:not_exported, to_boundary.name}

      true ->
        nil
    end
  end

  defp check_external_dep?(view, reference, from_boundary) do
    Boundary.app(view, reference.to) != :boundary and
      (from_boundary.type == :strict or
         MapSet.member?(
           with_ancestors(view, from_boundary, & &1.check.apps),
           {Boundary.app(view, reference.to), reference.mode}
         ))
  end

  defp with_ancestors(view, boundary, fetch_fun) do
    {result, _} =
      [boundary]
      |> Stream.concat(Stream.map(boundary.ancestors, &Boundary.fetch!(view, &1)))
      |> Enum.flat_map_reduce(
        :continue,
        fn
          _boundary, :halt ->
            {:halt, nil}

          boundary, :continue ->
            {fetch_fun.(boundary), if(boundary.type == :strict, do: :halt, else: :continue)}
        end
      )

    MapSet.new(result)
  end

  defp cross_ref_allowed?(view, from_boundary, to_boundary, reference) do
    cond do
      # reference to a child is always allowed
      from_boundary == Boundary.parent(view, to_boundary) ->
        true

      # reference to a sibling or the parent is allowed if target boundary is listed in deps
      Boundary.siblings?(from_boundary, to_boundary) or Boundary.parent(view, from_boundary) == to_boundary ->
        in_deps?(to_boundary, from_boundary.deps, reference)

      # reference to another app's boundary is implicitly allowed unless strict checking is required
      cross_app_ref?(view, reference) and not check_external_dep?(view, reference, from_boundary) ->
        true

      # reference to a non-sibling (either in-app or cross-app) is allowed if it is a dep of myself or any ancestor
      in_deps?(to_boundary, with_ancestors(view, from_boundary, & &1.deps), reference) ->
        true

      # no other reference is allowed
      true ->
        false
    end
  end

  defp in_deps?(%{name: name}, deps, reference) do
    Enum.any?(
      deps,
      fn
        {^name, :runtime} -> true
        {^name, :compile} -> compile_time_reference?(reference)
        _ -> false
      end
    )
  end

  defp compile_time_reference?(%{mode: :compile}), do: true
  defp compile_time_reference?(%{from: module, from_function: {name, arity}}), do: macro_exported?(module, name, arity)
  defp compile_time_reference?(_), do: false

  defp cross_app_ref?(view, reference) do
    to_app = Boundary.app(view, reference.to)

    # to_app may be nil if no module is defined with the given alias
    # such call is treated as an in-app call
    to_app != nil and
      to_app != Boundary.app(view, reference.from)
  end

  defp exported?(view, boundary, module) do
    boundary.implicit? or module == boundary.name or
      Enum.any?(boundary.exports, &export_matches?(view, boundary, &1, module))
  end

  defp export_matches?(_view, _boundary, module, module), do: true

  defp export_matches?(view, boundary, {root, opts}, module) do
    String.starts_with?(to_string(module), to_string(root)) and
      not Enum.any?(Keyword.get(opts, :except, []), &(Module.concat(root, &1) == module)) and
      (Boundary.for_module(view, module) == boundary or exported_by_child_subboundary?(view, boundary, module))
  end

  defp export_matches?(_, _, _, _), do: false

  defp unused_dirty_xrefs(view, references) do
    all_dirty_xrefs =
      for boundary <- Boundary.all(view),
          xref <- boundary.dirty_xrefs,
          into: MapSet.new(),
          do: {boundary.name, xref}

    unused_dirty_xrefs =
      for reference <- references,
          not unclassified_protocol_impl?(view, reference),
          from_boundary = Boundary.for_module(view, reference.from),
          reduce: all_dirty_xrefs,
          do: (xrefs -> MapSet.delete(xrefs, {from_boundary.name, reference.to}))

    unused_dirty_xrefs
    |> Enum.sort()
    |> Enum.map(fn {boundary_name, dirty_xref} ->
      boundary = Boundary.fetch!(view, boundary_name)
      {:unused_dirty_xref, %{name: boundary.name, file: boundary.file, line: boundary.line}, dirty_xref}
    end)
  end
end
