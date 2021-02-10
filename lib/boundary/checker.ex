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
      invalid_references(view, references)
    ])
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

  defp validate_export(view, %{name: boundary_name} = boundary, export) do
    cond do
      is_nil(Boundary.app(view, export)) ->
        {:unknown_export, %{name: export, file: boundary.file, line: boundary.line}}

      # boundary can export top-level module of its direct child sub-boundary
      match?(%{ancestors: [^boundary_name | _]}, Boundary.get(view, export)) ->
        nil

      (Boundary.for_module(view, export) || %{name: nil}).name != boundary.name ->
        {:export_not_in_boundary, %{name: export, file: boundary.file, line: boundary.line}}

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

  defp invalid_references(view, references) do
    for reference <- references,
        from_boundary = Boundary.for_module(view, reference.from),
        to_boundaries = to_boundaries(view, reference),
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

  defp to_boundaries(view, reference) do
    to_boundary = Boundary.for_module(view, reference.to)

    # main sub-boundary module may also be exported by its parent
    parent_boundary =
      if not is_nil(to_boundary) and reference.to == to_boundary.name,
        do: Boundary.parent(view, to_boundary)

    Enum.reject([to_boundary, parent_boundary], &is_nil/1)
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

      reference.type == :alias_reference and not from_boundary.check.aliases ->
        nil

      to_boundary == from_boundary ->
        nil

      Boundary.protocol_impl?(reference.to) ->
        # We can enter here when there's `defimpl SomeProtocol, for: Type`. In this case, the caller
        # is `SomeProtocol`, while the callee is `SomeProtocol.Type`. This is never an error, so
        # we're ignoring this case.
        nil

      not cross_ref_allowed?(view, from_boundary, to_boundary, reference) ->
        tag = if Enum.member?(from_boundary.deps, {to_boundary.name, :compile}), do: :runtime, else: :normal
        {tag, to_boundary.name}

      not exported?(to_boundary, reference.to) ->
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
    [boundary]
    |> Stream.concat(Stream.map(boundary.ancestors, &Boundary.fetch!(view, &1)))
    |> Stream.take_while(&(&1.type != :strict))
    |> Stream.flat_map(&fetch_fun.(&1))
    |> MapSet.new()
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

  defp cross_app_ref?(view, reference),
    do: Boundary.app(view, reference.from) != Boundary.app(view, reference.to)

  defp exported?(boundary, module),
    do: boundary.implicit? or module == boundary.name or Enum.any?(boundary.exports, &export_matches?(&1, module))

  defp export_matches?(module, module), do: true

  defp export_matches?({root, opts}, module) do
    String.starts_with?(to_string(module), to_string(root)) and
      not Enum.any?(Keyword.get(opts, :except, []), &(Module.concat(root, &1) == module))
  end

  defp export_matches?(_, _), do: false
end
