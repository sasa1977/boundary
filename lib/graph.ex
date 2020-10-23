defmodule Graph do
  def new(name) do
    %{connections: %{}, name: name, nodes: MapSet.new()}
  end

  def add_dependency(graph, from, to) do
    %{connections: connections, name: name, nodes: nodes} = graph
    nodes = nodes |> MapSet.put(from) |> MapSet.put(to)
    connections = Map.update(connections, from, MapSet.new([to]), &MapSet.put(&1, to))

    %{connections: connections, name: name, nodes: nodes}
  end

  def dot(graph) do
    """
    digraph {
      label=\"#{graph.name}\";
      labelloc=top;
    #{nodes(graph)}

    #{connections(graph)}
    }
    """
  end

  defp nodes(graph), do: Enum.map(graph.nodes, fn node -> "  #{node} [shape=\"box\"];\n" end)

  defp connections(graph) do
    for(
      {from, tos} <- graph.connections,
      to <- tos,
      do: "  \"#{from}\" -> \"#{to}\";\n"
    )
    |> to_string()
  end
end
