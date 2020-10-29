defmodule Mix.Tasks.Boundary.Visualize do
  @shortdoc "Generates a graphviz dot file for each non-empty boundary."
  @moduledoc "Generates a graphviz dot file for each non-empty boundary."

  use Boundary, classify_to: Boundary.Mix
  use Mix.Task

  alias Boundary.Graph

  @output_folder "boundary"

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("compile")
    Boundary.Mix.load_app()

    File.mkdir(@output_folder)

    view = Boundary.view(Boundary.Mix.app_name())

    view
    |> Boundary.all()
    |> Stream.filter(&(&1.app == Boundary.Mix.app_name() and (&1.check.in or &1.check.out)))
    |> Enum.group_by(&Boundary.parent(view, &1))
    |> Enum.each(fn {main_boundary, boundaries} ->
      nodes = build_nodes(view, main_boundary, boundaries)
      edges = build_edges(view, main_boundary, boundaries)
      title = title(main_boundary)
      graph = graph(main_boundary, title, nodes, edges)

      file_path = format_file_path(main_boundary)
      File.write!(file_path, graph)
    end)

    Mix.shell().info([:green, "Files successfully generated in the `#{@output_folder}` folder."])

    :ok
  end

  defp build_nodes(view, main_boundary, boundaries) do
    boundaries
    |> Stream.flat_map(&[&1.name | Enum.map(&1.deps, fn {name, _type} -> name end)])
    |> Stream.uniq()
    |> Stream.filter(&include?(view, main_boundary, Boundary.fetch!(view, &1)))
    |> Enum.sort()
  end

  defp build_edges(view, main_boundary, boundaries) do
    for %{name: name, deps: deps} <- boundaries,
        {dep_name, mode} <- deps,
        include?(view, main_boundary, Boundary.fetch!(view, dep_name)),
        do: {name, dep_name, mode}
  end

  defp include?(view, main_boundary, boundary),
    do: boundary.app == Boundary.Mix.app_name() and Boundary.parent(view, boundary) == main_boundary

  defp format_file_path(boundary) do
    name = if is_nil(boundary), do: "app", else: inspect(boundary.name)
    Path.join([File.cwd!(), @output_folder, "#{name}.dot"])
  end

  defp title(nil), do: "#{Boundary.Mix.app_name()} application"
  defp title(boundary), do: "#{inspect(boundary.name)} boundary"

  defp graph(main_boundary, title, nodes, edges) do
    graph = Graph.new(title)
    new_nodes = Enum.map(nodes, fn module -> node_name(main_boundary, module) end)

    new_edges =
      Enum.map(edges, fn {from, to, opts} ->
        {node_name(main_boundary, from), node_name(main_boundary, to), edge_attributes(opts)}
      end)

    graph = Enum.reduce(new_nodes, graph, fn node, graph -> Graph.add_node(graph, node) end)

    graph =
      Enum.reduce(new_edges, graph, fn {from, to, attributes}, graph ->
        Graph.add_dependency(graph, from, to, attributes)
      end)

    Graph.dot(graph)
  end

  defp node_name(nil, module), do: inspect(module)
  defp node_name(main_boundary, module), do: String.replace(inspect(module), ~r/^#{inspect(main_boundary.name)}\./, "")

  defp edge_attributes(:runtime), do: []
  defp edge_attributes(:compile), do: [label: "compile"]
end
