defmodule Mix.Tasks.Boundary.Visualize do
  @shortdoc "Generates a graphviz a dot file for each non-empty boundary."
  @moduledoc "Generates a graphviz a dot file for each non-empty boundary."

  use Boundary, classify_to: Boundary.Mix
  use Mix.Task

  @output_folder "dot"

  @impl Mix.Task
  def run(_argv) do
    name = "Test.Graph"
    edges = [{"A", "B"}, {"A", "C"}, {"B", "C", style: :dotted}]
    output_graph(name, edges)
  end

  def output_graph(name, edges) do
    content = format_graph(name, edges)
    write_graph(name, content)
    :ok
  end

  defp write_graph(name, content) do
    output_path = Path.join([File.cwd!(), @output_folder])
    dotfile_path = Path.join(output_path, "#{name}.dot")
    pngfile_path = Path.join(output_path, "#{name}.png")
    File.mkdir(output_path)
    File.write!(dotfile_path, content)
    # System.cmd("dot", ["-Tpng", dotfile_path, "-o", pngfile_path])
    # System.cmd("open", [pngfile_path])
    # Process.sleep(5000)
  end

  defp format_graph(title, edges) do
    """
    digraph {
      #{edges |> Enum.map(&format_edge/1) |> Enum.join("\n  ")}

      label="#{title}";
      labelloc=top;
    }
    """
  end

  defp format_edge({node1, node2}), do: format_edge({node1, node2, []})
  defp format_edge({node1, node2, attributes}), do: "#{node1} -> #{node2}#{format_attributes(attributes)}"

  defp format_attributes([]), do: ""
  defp format_attributes(attributes), do: " [#{attributes |> Enum.map(&format_attribute/1) |> Enum.join(", ")}]"
  defp format_attribute({name, value}), do: "#{name} = #{value}"
end
