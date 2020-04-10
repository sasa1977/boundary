defmodule Mix.Tasks.Boundary.Visualize do
  @shortdoc "Generates a graphviz a dot file for each non-empty boundary."
  @moduledoc "Generates a graphviz a dot file for each non-empty boundary."

  use Boundary, classify_to: Boundary.Mix
  use Mix.Task

  @output_folder "boundary"

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("compile")
    Boundary.Mix.load_app()

    File.mkdir(@output_folder)

    view = Boundary.Mix.app_name() |> Boundary.view()

    view
    |> Boundary.all()
    |> Enum.group_by(&Boundary.parent(view, &1))
    |> Enum.each(fn {main_boundary, boundaries} ->
      nodes = build_nodes(main_boundary, boundaries)
      edges = build_edges(main_boundary, boundaries)
      title = format_title(main_boundary)
      graph = format_graph(title, nodes, edges)
      file_path = format_file_path(main_boundary)

      File.write!(file_path, graph)

      # image_file_path = "#{Path.rootname(file_path)}.png"
      # System.cmd("dot", ["-Tpng", file_path, "-o", image_file_path])
      # System.cmd("open", [image_file_path])
      # Process.sleep(1000)
    end)

    :ok
  end

  defp build_nodes(main_boundary, boundaries) do
    boundaries
    |> Enum.flat_map(fn %{name: name, deps: deps} ->
      [name | Enum.map(deps, &elem(&1, 0))]
    end)
    |> Enum.uniq()
    |> Enum.map(&build_node(main_boundary, &1))
  end

  defp build_node(nil, module), do: {module, :sibling}

  defp build_node(main_boundary, module) do
    if Module.split(main_boundary.name) == Module.split(module) |> Enum.drop(-1) do
      {module, :sibling}
    else
      {module, nil}
    end
  end

  defp build_edges(_main_boundary, boundaries) do
    boundaries
    |> Enum.flat_map(fn %{name: name, deps: deps} ->
      Enum.map(deps, fn {dep_name, mode} ->
        {name, dep_name, mode}
      end)
    end)
  end

  defp format_file_path(boundary) do
    name = if is_nil(boundary), do: "app", else: format_name(boundary.name)
    Path.join([File.cwd!(), @output_folder, "#{name}.dot"])
  end

  defp format_title(nil), do: "#{Boundary.Mix.app_name()} application"
  defp format_title(boundary), do: "#{format_name(boundary.name)} boundary"

  defp format_graph(title, nodes, edges) do
    """
    digraph {
      label="#{title}";
      labelloc=top;

      #{format_nodes(nodes)};

      #{format_edges(edges)};
    }
    """
  end

  defp format_nodes(nodes) do
    nodes
    |> Enum.sort()
    |> Enum.map(&format_node_description/1)
    |> Enum.join(";\n  ")
  end

  def format_node_description({module, :sibling}), do: format_node(module)
  def format_node_description({module, _}), do: "#{format_node(module)} [color = \"gray\"]"

  defp format_edges(edges) do
    edges
    |> Enum.sort()
    |> Enum.map(&format_edge/1)
    |> Enum.join(";\n  ")
  end

  defp format_edge(edge = {module1, module2, _}) do
    "#{format_node(module1)} -> #{format_node(module2)}#{format_edge_attributes(edge)}"
  end

  def format_node(module) when is_atom(module) do
    "\"#{format_name(module)}\""
  end

  defp format_name(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end

  defp format_edge_attributes(_node = {_, _, :runtime}), do: ""
  defp format_edge_attributes(_node = {_, _, :compile}), do: " [label = \"compile\"]"
end
