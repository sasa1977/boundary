defmodule Boundaries.Test.Project do
  def empty() do
    %{modules: MapSet.new(), boundaries: [], ownership: %{}, membership: %{}}
  end

  def check(project, calls) do
    config_string = inspect(project.boundaries, limit: :infinity, pretty: true)
    {:ok, boundaries} = Boundaries.from_string(config_string)
    Boundaries.check(boundaries, project.modules, calls)
  end

  def merge(project1, project2) do
    %{
      project1
      | boundaries: project1.boundaries ++ project2.boundaries,
        modules: MapSet.union(project1.modules, project2.modules),
        ownership: Map.merge(project1.ownership, project2.ownership),
        membership: Map.merge(project1.membership, project2.membership)
    }
  end

  def disjoint?(project1, project2) do
    MapSet.disjoint?(MapSet.new(boundaries(project1)), MapSet.new(boundaries(project2))) and
      MapSet.disjoint?(project1.modules, project2.modules)
  end

  def boundaries(project), do: Enum.map(project.boundaries, &boundary_name/1)

  def num_boundaries(project), do: map_size(project.ownership)

  def add_boundary(project, boundary, boundary_data \\ []) do
    boundaries = [{boundary, Map.merge(%{exports: [], deps: []}, Map.new(boundary_data))} | project.boundaries]
    ownership = Map.put_new(project.ownership, boundary, MapSet.new())
    %{project | boundaries: boundaries, ownership: ownership}
  end

  def add_module(project, {boundary, module}) do
    modules = MapSet.put(project.modules, module)

    {ownership, membership} =
      if boundary != nil do
        {
          Map.update!(project.ownership, boundary, &MapSet.put(&1, module)),
          Map.put(project.membership, module, boundary)
        }
      else
        {project.ownership, project.membership}
      end

    %{project | modules: modules, ownership: ownership, membership: membership}
  end

  def add_modules(project, boundary \\ nil, modules), do: Enum.reduce(modules, project, &add_module(&2, {boundary, &1}))

  def add_deps(project, deps), do: %{project | boundaries: Enum.reduce(deps, project.boundaries, &add_dep(&2, &1))}

  def module_boundary(project, module), do: Map.fetch!(project.membership, module)

  def boundary_modules(project, boundary_name), do: Map.fetch!(project.ownership, boundary_name)

  def allowed_callees(project, boundary, boundary), do: boundary_modules(project, boundary)
  def allowed_callees(project, _from_boundary, to_boundary), do: boundary_exports(project, to_boundary)

  def allowed_deps(project) do
    project.boundaries
    |> Stream.flat_map(fn {name, data} -> [{name, name}] ++ Enum.map(data.deps, &{name, &1}) end)
    |> Enum.uniq()
  end

  def all_invalid_calls(project) do
    %{
      invalid_cross_boundary_calls: invalid_cross_boundary_calls(project),
      invalid_private_calls: invalid_private_calls(project)
    }
    |> Stream.reject(fn {_key, elements} -> Enum.empty?(elements) end)
    |> Map.new()
  end

  defp invalid_cross_boundary_calls(project) do
    for {boundary_from, from_data} <- project.boundaries,
        {boundary_to, to_data} <- project.boundaries,
        boundary_from != boundary_to and boundary_to not in from_data.deps,
        module_from <- boundary_modules(project, boundary_from),
        module_to <- to_data.exports,
        do: {module_from, module_to}
  end

  defp invalid_private_calls(project) do
    for {boundary_from, from_data} <- project.boundaries,
        {boundary_to, to_data} <- project.boundaries,
        boundary_from != boundary_to and boundary_to in from_data.deps,
        module_from <- boundary_modules(project, boundary_from),
        module_to <- boundary_modules(project, boundary_to),
        module_to not in to_data.exports,
        do: {module_from, module_to}
  end

  defp boundary_name({name, _}), do: name

  defp add_dep([{from, data} | rest], {from, to}), do: [{from, %{data | deps: Enum.uniq([to | data.deps])}} | rest]
  defp add_dep([other | rest], {from, to}), do: [other | add_dep(rest, {from, to})]

  defp boundary_exports(project, boundary_name) do
    {^boundary_name, data} = Enum.find(project.boundaries, &match?({^boundary_name, _data}, &1))
    data.exports
  end
end
