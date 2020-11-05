defmodule Boundary.Graph do
  @moduledoc false

  @opaque t :: %{connections: %{node => Keyword.t()}, name: String.t(), nodes: MapSet.t(node), subgraphs: [t]}
  @type node_name :: String.t()

  @spec new(node_name) :: t()
  def new(name), do: %{connections: %{}, name: name, nodes: MapSet.new(), subgraphs: []}

  @spec add_node(t(), node_name()) :: t()
  def add_node(graph, node), do: update_in(graph.nodes, &MapSet.put(&1, node))

  @spec add_dependency(t(), node_name, node_name, Keyword.t()) :: t()
  def add_dependency(graph, from, to, attributes \\ []) do
    %{connections: connections, name: _name, nodes: nodes, subgraphs: _subgraph} = graph
    nodes = nodes |> MapSet.put(from) |> MapSet.put(to)
    connections = Map.update(connections, from, %{to => attributes}, &Map.merge(&1, %{to => attributes}))

    %{graph | nodes: nodes, connections: connections}
  end

  @spec add_subgraph(t(), t()) :: t()
  def add_subgraph(graph, subgraph) do
    %{connections: _connections, name: _name, nodes: _nodes, subgraphs: subgraphs} = graph
    %{graph | subgraphs: [subgraph] ++ subgraphs}
  end

  @spec dot(t(), Keyword.t()) :: node_name
  def dot(graph, opts \\ []) do
    {spaces, opts} = Keyword.pop(opts, :indent, 0)
    indent = String.duplicate(" ", spaces)
    {type, opts} = Keyword.pop(opts, :type, :digraph)

    graph_content = """
    #{indent}  label="#{graph.name}";
    #{indent}  labelloc=top;
    #{indent}  rankdir=LR;
    #{make_opts(opts, indent)}
    #{nodes(graph, indent)}

    #{connections(graph, indent)}

    #{Enum.map(graph.subgraphs, &dot(&1, indent: spaces + 2, type: :subgraph))}
    """

    graph_content = format_dot(graph_content)

    case type do
      :subgraph -> "#{indent}#{type} cluster_#{div(spaces, 2) - 1} {\n#{graph_content}#{indent}}\n"
      _ -> "#{indent}#{type} {\n#{graph_content}#{indent}}\n"
    end
  end

  defp nodes(graph, tab), do: Enum.map(graph.nodes, fn node -> ~s/#{tab}  "#{node}" [shape="box"];\n/ end)

  defp make_opts(options, indent) do
    case options do
      [] -> ""
      _ -> opt_string(options, indent)
    end
  end

  defp connections(graph, tab) do
    for(
      {from, connections} <- graph.connections,
      {to, attributes} <- connections,
      do: ~s/#{tab}  "#{from}" -> "#{to}"#{connection_attributes(attributes)};\n/
    )
    |> to_string()
  end

  defp opt_string(options, indent), do: Enum.map(options, fn {k, v} -> "#{indent}  #{k}=#{v};\n" end)

  defp connection_attributes([]), do: ""

  defp connection_attributes(attributes),
    do: " [#{Enum.join(Enum.map(attributes, fn {k, v} -> "#{k}=#{v}" end), ", ")}]"

  defp format_dot(dot_string) do
    dot_string
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.replace(~r/\n\n$/, "\n")
  end
end
