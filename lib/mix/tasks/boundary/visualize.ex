defmodule Mix.Tasks.Boundary.Visualize do
  @shortdoc "Generates a graphviz dot file for each non-empty boundary."
  @moduledoc "Generates a graphviz dot file for each non-empty boundary."

  use Boundary, classify_to: Boundary.Mix
  use Mix.Task

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
      title = format_title(main_boundary)
      graph = format_graph(title, nodes, edges)
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
    |> Stream.map(fn name -> {name, if(name != main_boundary[:name], do: :sibling, else: nil)} end)
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

  defp format_title(nil), do: "#{Boundary.Mix.app_name()} application"
  defp format_title(boundary), do: "#{inspect(boundary.name)} boundary"

  defp format_graph(title, nodes, edges) do
    body =
      [
        [
          ~s/label="#{title}"/,
          ~s/labelloc=top/
        ],
        node_clauses(nodes),
        edge_clauses(edges)
      ]
      |> Stream.reject(&Enum.empty?/1)
      |> Stream.intersperse(?\n)
      |> Enum.map(fn part -> with [_ | _] = clauses <- part, do: Enum.map(clauses, &"  #{&1};\n") end)

    "digraph {\n#{body}}\n"
  end

  defp node_clauses(nodes) do
    nodes
    |> Enum.sort()
    |> Enum.map(&format_node_description/1)
  end

  defp format_node_description({module, :sibling}), do: format_node(module)
  defp format_node_description({module, _}), do: ~s/#{format_node(module)} [color = "gray"]/

  defp edge_clauses(edges) do
    edges
    |> Enum.sort()
    |> Enum.map(&format_edge/1)
  end

  defp format_edge({module1, module2, _} = edge),
    do: "#{format_node(module1)} -> #{format_node(module2)}#{format_edge_attributes(edge)}"

  defp format_node(module), do: ~s/"#{inspect(module)}"/

  defp format_edge_attributes({_, _, :runtime}), do: ""
  defp format_edge_attributes({_, _, :compile}), do: ~s/ [label = "compile"]/
end
