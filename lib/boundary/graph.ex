defmodule Boundary.Graph do
  @moduledoc false

  @opaque t :: %{connections: %{node => Keyword.t()}, name: String.t(), nodes: %{node => Keyword.t()}, subgraphs: [t]}
  @type node_name :: String.t()

  @spec new(node_name) :: t()
  def new(name), do: %{connections: %{}, name: name, nodes: %{}, subgraphs: []}

  @spec add_node(t(), node_name(), Keyword.t()) :: t()
  def add_node(graph, node, opts \\ []) do
    Map.update!(
      graph,
      :nodes,
      fn nodes -> Map.update(nodes, node, opts, &Keyword.merge(&1, opts)) end
    )
  end

  @spec add_dependency(t(), node_name, node_name, Keyword.t()) :: t()
  def add_dependency(graph, from, to, attributes \\ []) do
    connections = Map.update(graph.connections, from, %{to => attributes}, &Map.merge(&1, %{to => attributes}))
    %{graph | connections: connections}
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
    #{opts_string(opts, indent)}
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
    |> Enum.map_join(
      "\n",
      fn {subgraph, index} -> dot(subgraph, indent: spaces + 2, type: {:subgraph, index}) end
    )
  end

  defp nodes(graph, tab) do
    Enum.map(
      graph.nodes,
      fn {node, opts} ->
        opts = Keyword.merge([shape: "box"], opts)
        ~s/#{tab}  "#{node}"#{attributes(opts)};\n/
      end
    )
  end

  defp connections(graph, tab) do
    for(
      {from, connections} <- graph.connections,
      {to, attributes} <- connections,
      do: ~s/#{tab}  "#{from}" -> "#{to}"#{attributes(attributes)};\n/
    )
    |> to_string()
  end

  defp opts_string(options, indent), do: Enum.map(options, fn {k, v} -> "#{indent}  #{k}=#{v};\n" end)

  defp attributes([]), do: ""

  defp attributes(attributes),
    do: " [#{Enum.map_join(attributes, ", ", fn {k, v} -> "#{k}=#{v}" end)}]"

  defp format_dot(dot_string) do
    dot_string
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.replace(~r/\n\n$/, "\n")
  end
end
