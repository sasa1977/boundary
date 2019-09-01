defmodule Boundary.Test.Generator do
  @moduledoc false
  # credo:disable-for-this-file Credo.Check.Readability.Specs

  import StreamData
  import ExUnitProperties, only: [gen: 1, gen: 2]

  alias Boundary.Test.Application

  def app do
    gen all roots <- module_tree(),
            roots = Enum.map(roots, &with_node_sizes/1),
            roots <- roots |> Enum.map(&pick_modules/1) |> fixed_list(),
            roots <- roots |> Enum.map(&pick_boundaries/1) |> fixed_list(),
            do: Enum.reduce(roots, Application.empty(), &collect_app(&2, &1))
  end

  def with_valid_calls(app) do
    unshrinkable(
      gen all length <- integer(2..map_size(app.boundaries)),
              boundaries = app |> Application.boundaries() |> Enum.take_random(length),
              valid_deps = make_deps(boundaries),
              valid_calls <- calls(app, Application.allowed_deps(app)),
              do: {valid_calls, Application.add_deps(app, valid_deps)}
    )
  end

  def with_invalid_calls(app) do
    gen all calls_and_errors <- invalid_calls_and_errors(app),
            {calls, errors} = Enum.unzip(calls_and_errors),
            do: {calls, Enum.sort_by(errors, &{&1.file, &1.position})}
  end

  defp invalid_calls_and_errors(app) do
    app
    |> Application.all_invalid_calls()
    |> call_and_error(app)
    |> list_of()
    |> nonempty()
  end

  defp call_and_error(all_invalid_calls, app) do
    gen all type <- member_of(Map.keys(all_invalid_calls)),
            {caller_module, callee_module} <- member_of(Map.fetch!(all_invalid_calls, type)) do
      call = call(caller_module, callee_module)
      error = expected_error(type, app, call)
      {call, error}
    end
  end

  defp expected_error(:invalid_cross_boundary_calls, app, call) do
    from_boundary = Application.module_boundary(app, call.caller_module)
    to_boundary = Application.module_boundary(app, call.callee_module)
    {m, f, a} = call.callee

    diagnostic(
      call,
      "forbidden call to #{Exception.format_mfa(m, f, a)}\n" <>
        "  (calls from #{inspect(from_boundary)} to #{inspect(to_boundary)} are not allowed)"
    )
  end

  defp expected_error(:invalid_private_calls, app, call) do
    {m, f, a} = call.callee
    to_boundary = Application.module_boundary(app, call.callee_module)

    diagnostic(
      call,
      "forbidden call to #{Exception.format_mfa(m, f, a)}\n" <>
        "  (module #{inspect(call.callee_module)} is not exported by its owner boundary #{inspect(to_boundary)})"
    )
  end

  defp diagnostic(call, message) do
    %Mix.Task.Compiler.Diagnostic{
      compiler_name: "boundary",
      details: nil,
      severity: :warning,
      file: call.file,
      position: call.line,
      message: message
    }
  end

  defp calls(_app, []), do: constant([])

  defp calls(app, deps) do
    gen all deps <- list_of(member_of(deps)),
            calls <- deps |> Enum.map(&cross_boundary_call(app, &1)) |> fixed_list(),
            do: calls
  end

  defp cross_boundary_call(app, {from_boundary, to_boundary}) do
    gen all caller_module <- member_of(Application.boundary_modules(app, from_boundary)),
            callee_module <- member_of(Application.allowed_callees(app, from_boundary, to_boundary)),
            do: call(caller_module, callee_module)
  end

  defp call(caller_module, callee_module) do
    id = :erlang.unique_integer([:positive])

    %{
      file: "#{id}",
      line: id,
      callee: {callee_module, :"call_#{id}", 1},
      callee_module: callee_module,
      caller_module: caller_module
    }
  end

  defp make_deps([a, b]), do: [{a, b}]
  defp make_deps([a | rest]), do: Enum.map(rest, &{a, &1}) ++ make_deps(rest)

  def with_unknown_deps(app) do
    gen all unknown_boundaries <- list_of(unknown_boundary(app, atom(:alias)), min_length: 1, max_length: 20),
            app <- add_deps(app, unknown_boundaries),
            do: {unknown_boundaries, app}
  end

  def with_ignored_deps(app) do
    gen all ignored_deps <- uniq_list_of(unknown_boundary(app, atom(:alias)), min_length: 1, max_length: 20),
            app <- add_deps(app, ignored_deps),
            app =
              Enum.reduce(
                ignored_deps,
                app,
                fn boundary, app ->
                  app
                  |> Application.add_boundary(boundary, ignore?: true)
                  |> Application.add_module({boundary, boundary})
                end
              ),
            do: {ignored_deps, app}
  end

  defp add_deps(app, deps) do
    length = length(deps)

    gen all invalid_boundaries <- list_of(member_of(app.boundaries), min_length: length, max_length: length),
            invalid_boundaries = Enum.map(invalid_boundaries, fn {boundary, _} -> boundary end),
            do: Application.add_deps(app, Enum.zip(invalid_boundaries, deps))
  end

  def with_cycle(app) do
    all_boundaries = Application.boundaries(app)

    gen all length <- integer(2..min(10, length(all_boundaries))),
            boundaries = Enum.take_random(all_boundaries, length),
            do: {boundaries, Application.add_deps(app, cycle_deps(boundaries))}
  end

  defp cycle_deps(boundaries),
    do: (boundaries ++ [hd(boundaries)]) |> Stream.chunk_every(2, 1, :discard) |> Enum.map(&List.to_tuple/1)

  def with_unclassified_modules(app) do
    gen all new_modules <- new_modules(app),
            do: {new_modules, Application.add_modules(app, new_modules)}
  end

  def with_unclassified_protocol_impls(app) do
    gen all new_modules <- new_modules(app),
            do: Enum.reduce(new_modules, app, &Application.add_module(&2, {nil, &1}, protocol_impl?: true))
  end

  defp new_modules(app) do
    gen all new_roots <- list_of(unknown_boundary(app, module_part()), min_length: 1, max_length: 10),
            new_modules <-
              new_roots
              |> Enum.map(&map(atom(:alias), fn rest -> Module.concat(&1, rest) end))
              |> fixed_list()
              |> map(&Enum.uniq/1),
            do: new_modules
  end

  defp unknown_boundary(app, generator),
    do: filter(generator, &is_nil(Enum.find(app.boundaries, fn {boundary, _} -> boundary == &1 end)))

  defp collect_app(app, node, parent_name \\ nil) do
    name = concat(parent_name, node.name)

    app =
      if node.boundary? do
        mandatory_exports = if node.module?, do: [node.name], else: []
        exports = (mandatory_exports ++ node.exports) |> Stream.uniq() |> Enum.map(&concat(parent_name, &1))

        app
        |> Application.add_boundary(name, exports: exports)
        |> Application.add_modules(name, Enum.map(node.owned_modules, &concat(parent_name, &1)))
      else
        app
      end

    Enum.reduce(node.children, app, &collect_app(&2, &1, name))
  end

  defp with_node_sizes(node) do
    children = Enum.map(node.children, &with_node_sizes/1)
    size = 1 + (children |> Stream.map(& &1.size) |> Enum.sum())
    Map.put(%{node | children: children}, :size, size)
  end

  defp pick_modules(node, tree_size \\ nil) do
    tree_size = tree_size || node.size

    bind(module?(node, tree_size), fn module? ->
      node.children
      |> Enum.map(&pick_modules(&1, tree_size))
      |> fixed_list()
      |> map(fn children -> Map.merge(node, %{children: children, module?: module?}) end)
    end)
  end

  defp pick_boundaries(node, tree_size \\ nil) do
    tree_size = tree_size || node.size

    node.children
    |> Enum.map(&pick_boundaries(&1, tree_size))
    |> fixed_list()
    |> map(&%{node | children: &1})
    |> bind(&maybe_make_boundary(&1, tree_size))
  end

  defp module?(%{size: 1}, _tree_size), do: constant(true)
  defp module?(node, tree_size), do: probabilistic_boolean(node.size, tree_size, false)

  defp maybe_make_boundary(node, tree_size) do
    owned_modules = owned_modules(node)

    cond do
      owned_modules == [] -> constant(false)
      node.size == tree_size -> constant(true)
      true -> probabilistic_boolean(node.size, tree_size, true)
    end
    |> bind(fn
      false -> constant(Map.put(node, :boundary?, false))
      true -> generate_boundary(node, owned_modules)
    end)
  end

  defp generate_boundary(node, owned_modules) do
    gen all exports <- nonempty(list_of(member_of(owned_modules))),
            do: Map.merge(node, %{boundary?: true, owned_modules: owned_modules, exports: Enum.uniq(exports)})
  end

  defp owned_modules(node, parent_name \\ nil) do
    if not is_nil(parent_name) and node.boundary?,
      do: [],
      else: collect_owned_modules(node, concat(parent_name, node.name))
  end

  defp collect_owned_modules(node, node_name) do
    Enum.reduce(
      node.children,
      if(node.module?, do: [node_name], else: []),
      &(owned_modules(&1, node_name) ++ &2)
    )
  end

  defp probabilistic_boolean(size, total_size, boolean) do
    positive = min(99, round(100 * size / total_size))
    negative = 100 - positive
    frequency([{positive, constant(boolean)}, {negative, constant(not boolean)}])
  end

  defp module_tree do
    nonempty(
      tree(
        constant([]),
        fn children ->
          nonempty(
            uniq_list_of(fixed_map(%{name: module_part(), children: children}), uniq_fun: & &1.name, max_length: 10)
          )
        end
      )
    )
    |> scale(&max(2, &1))
  end

  defp module_part, do: map(atom(:alias), fn full_alias -> :"Elixir.#{full_alias |> Module.split() |> hd()}" end)

  defp concat(nil, name), do: name
  defp concat(name, nil), do: name
  defp concat(parent_name, name), do: Module.concat(parent_name, name)
end
