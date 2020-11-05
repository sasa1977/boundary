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
    nodes = graph.nodes |> MapSet.put(from) |> MapSet.put(to)
    connections = Map.update(graph.connections, from, %{to => attributes}, &Map.merge(&1, %{to => attributes}))
    %{graph | nodes: nodes, connections: connections}
  end

  @spec add_subgraph(t(), t()) :: t()
  def add_subgraph(graph, subgraph),
    do: %{graph | subgraphs: [subgraph | graph.subgraphs]}

  @spec dot(t(), Keyword.t()) :: node_name
  def dot(graph, opts \\ []) do
    {type, opts} = Keyword.pop(opts, :type, :digraph)
    {spaces, opts} = Keyword.pop(opts, :indent, 0)
    indent = String.duplicate(" ", spaces)

    graph_content = """
    #{indent}  label="#{graph.name}";
    #{indent}  labelloc=top;
    #{indent}  rankdir=LR;
    #{make_opts(opts, indent)}
    #{nodes(graph, indent)}

    #{connections(graph, indent)}

    #{subgraphs(graph, spaces)}
    """

    graph_content = format_dot(graph_content)

    header =
      case type do
        {:subgraph, index} -> "subgraph cluster_#{index}"
        _ -> to_string(type)
      end

    "#{indent}#{header} {\n#{graph_content}#{indent}}\n"
  end

  defp subgraphs(graph, spaces) do
    graph.subgraphs
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(fn {subgraph, index} -> dot(subgraph, indent: spaces + 2, type: {:subgraph, index}) end)
    |> Enum.join("\n")
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
