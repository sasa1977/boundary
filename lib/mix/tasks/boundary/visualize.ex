defmodule Mix.Tasks.Boundary.Visualize do
  @shortdoc "Generates a graphviz a dot file for each non-empty boundary."
  @moduledoc "Generates a graphviz a dot file for each non-empty boundary."

  use Boundary, classify_to: Boundary.Mix
  use Mix.Task

  @output_folder "dot"

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("compile")
    Boundary.Mix.load_app()

    app_name = Boundary.Mix.app_name()

    graph =
      format_graph(
        "#{app_name} application",
        app_name
        |> Boundary.view()
        |> Boundary.all()
        |> Stream.filter(&(&1.app == Boundary.Mix.app_name()))
        |> Stream.reject(&Enum.empty?(&1.deps))
        |> Stream.filter(&Enum.empty?(&1.ancestors))
        |> Enum.sort_by(& &1.name)
        |> Enum.flat_map(&boundary_to_edges/1)
      )

    write_graph("app", graph) |> draw_graph

    :ok
  end

  defp boundary_to_edges(%{name: name, deps: deps}) do
    boundary_node = format_node(name)

    deps
    |> Enum.sort()
    |> Enum.map(fn {name, _mode} ->
      dep_node = format_node(name)
      {boundary_node, dep_node}
    end)
  end

  defp format_graph(title, edges) do
    """
    digraph {
      #{edges |> Enum.map(&format_edge/1) |> Enum.join(";\n  ")};

      label="#{title}";
      labelloc=top;
    }
    """
  end

  def format_node(module_name) do
    module_name
    |> Module.split()
    |> Enum.join(".")
  end

  defp format_edge({node1, node2}), do: format_edge({node1, node2, []})
  defp format_edge({node1, node2, attributes}), do: "#{node1} -> #{node2}#{format_attributes(attributes)}"

  defp format_attributes([]), do: ""
  defp format_attributes(attributes), do: " [#{attributes |> Enum.map(&format_attribute/1) |> Enum.join(", ")}]"
  defp format_attribute({name, value}), do: "#{name} = #{value}"

  defp write_graph(name, content) do
    output_path = Path.join([File.cwd!(), @output_folder])
    dot_file_path = Path.join(output_path, "#{name}.dot")
    File.mkdir(output_path)
    File.write!(dot_file_path, content)
    dot_file_path
  end

  defp draw_graph(dot_file_path) do
    image_dir_path = Path.dirname(dot_file_path)
    image_file_name = Path.basename(dot_file_path, ".dot")
    image_file_path = Path.join([image_dir_path, "#{image_file_name}.png"]) |> IO.inspect()
    System.cmd("dot", ["-Tpng", dot_file_path, "-o", image_file_path])
    System.cmd("open", [image_file_path])
    Process.sleep(1000)
  end
end
