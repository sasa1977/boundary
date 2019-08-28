defmodule Boundary.Test.Application do
  def empty() do
    %{modules: MapSet.new(), boundaries: [], ownership: %{}, membership: %{}}
  end

  def check(app, calls) do
    config_string = inspect(app.boundaries, limit: :infinity, pretty: true)
    {:ok, boundaries} = Boundary.from_string(config_string)
    Boundary.MixCompiler.check(%{boundaries: boundaries, modules: app.modules, calls: calls})
  end

  def merge(app1, app2) do
    %{
      app1
      | boundaries: app1.boundaries ++ app2.boundaries,
        modules: MapSet.union(app1.modules, app2.modules),
        ownership: Map.merge(app1.ownership, app2.ownership),
        membership: Map.merge(app1.membership, app2.membership)
    }
  end

  def disjoint?(app1, app2) do
    MapSet.disjoint?(MapSet.new(boundaries(app1)), MapSet.new(boundaries(app2))) and
      MapSet.disjoint?(app1.modules, app2.modules)
  end

  def boundaries(app), do: Enum.map(app.boundaries, &boundary_name/1)

  def num_boundaries(app), do: map_size(app.ownership)

  def add_boundary(app, boundary, boundary_data \\ []) do
    boundaries = [{boundary, Map.merge(%{exports: [], deps: []}, Map.new(boundary_data))} | app.boundaries]
    ownership = Map.put_new(app.ownership, boundary, MapSet.new())
    %{app | boundaries: boundaries, ownership: ownership}
  end

  def add_module(app, {boundary, module}) do
    modules = MapSet.put(app.modules, module)

    {ownership, membership} =
      if boundary != nil do
        {
          Map.update!(app.ownership, boundary, &MapSet.put(&1, module)),
          Map.put(app.membership, module, boundary)
        }
      else
        {app.ownership, app.membership}
      end

    %{app | modules: modules, ownership: ownership, membership: membership}
  end

  def add_modules(app, boundary \\ nil, modules), do: Enum.reduce(modules, app, &add_module(&2, {boundary, &1}))

  def add_deps(app, deps), do: %{app | boundaries: Enum.reduce(deps, app.boundaries, &add_dep(&2, &1))}

  def module_boundary(app, module), do: Map.fetch!(app.membership, module)

  def boundary_modules(app, boundary_name), do: Map.fetch!(app.ownership, boundary_name)

  def allowed_callees(app, boundary, boundary), do: boundary_modules(app, boundary)
  def allowed_callees(app, _from_boundary, to_boundary), do: boundary_exports(app, to_boundary)

  def allowed_deps(app) do
    app.boundaries
    |> Stream.flat_map(fn {name, data} -> [{name, name}] ++ Enum.map(data.deps, &{name, &1}) end)
    |> Enum.uniq()
  end

  def all_invalid_calls(app) do
    %{
      invalid_cross_boundary_calls: invalid_cross_boundary_calls(app),
      invalid_private_calls: invalid_private_calls(app)
    }
    |> Stream.reject(fn {_key, elements} -> Enum.empty?(elements) end)
    |> Map.new()
  end

  defp invalid_cross_boundary_calls(app) do
    for {boundary_from, from_data} <- app.boundaries,
        {boundary_to, to_data} <- app.boundaries,
        boundary_from != boundary_to and boundary_to not in from_data.deps,
        module_from <- boundary_modules(app, boundary_from),
        module_to <- to_data.exports,
        do: {module_from, module_to}
  end

  defp invalid_private_calls(app) do
    for {boundary_from, from_data} <- app.boundaries,
        {boundary_to, to_data} <- app.boundaries,
        boundary_from != boundary_to and boundary_to in from_data.deps,
        module_from <- boundary_modules(app, boundary_from),
        module_to <- boundary_modules(app, boundary_to),
        module_to not in to_data.exports,
        do: {module_from, module_to}
  end

  defp boundary_name({name, _}), do: name

  defp add_dep([{from, data} | rest], {from, to}), do: [{from, %{data | deps: Enum.uniq([to | data.deps])}} | rest]
  defp add_dep([other | rest], {from, to}), do: [other | add_dep(rest, {from, to})]

  defp boundary_exports(app, boundary_name) do
    {^boundary_name, data} = Enum.find(app.boundaries, &match?({^boundary_name, _data}, &1))
    data.exports
  end
end
