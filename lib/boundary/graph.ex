defmodule Boundary.Graph do
  @moduledoc false

  @opaque t :: %{connections: %{node => Keyword.t()}, name: String.t(), nodes: MapSet.t(node)}
  @type node_name :: String.t()

  @spec new(node_name) :: t()
  def new(name) do
    %{connections: %{}, name: name, nodes: MapSet.new()}
  end

  @spec add_node(t(), node_name()) :: t()
  def add_node(graph, node), do: update_in(graph.nodes, &MapSet.put(&1, node))

  @spec add_dependency(t(), node_name, node_name, Keyword.t()) :: t()
  def add_dependency(graph, from, to, attributes \\ []) do
    %{connections: connections, name: name, nodes: nodes} = graph
    nodes = nodes |> MapSet.put(from) |> MapSet.put(to)
    connections = Map.update(connections, from, %{to => attributes}, &Map.merge(&1, %{to => attributes}))

    %{connections: connections, name: name, nodes: nodes}
  end

  @spec dot(t(), Keyword.t()) :: node_name
  def dot(graph, opts \\ []) do
    graph_content = """
      label="#{graph.name}";
      labelloc=top;
      rankdir=LR;
    #{make_opts(opts)}
    #{nodes(graph)}

    #{connections(graph)}
    """

    graph_content = format_dot(graph_content)
    "digraph {\n#{graph_content}}\n"
  end

  defp nodes(graph), do: Enum.map(graph.nodes, fn node -> ~s/  "#{node}" [shape="box"];\n/ end)

  defp make_opts(options) do
    case options do
      [] -> ""
      _ -> opt_string(options)
    end
  end

  defp connections(graph) do
    for(
      {from, connections} <- graph.connections,
      {to, attributes} <- connections,
      do: ~s/  "#{from}" -> "#{to}"#{connection_attributes(attributes)};\n/
    )
    |> to_string()
  end

  defp opt_string(options) do
    Enum.map(options, fn {k, v} -> "  #{k}=#{v};\n" end)
  end

  defp connection_attributes([]), do: ""

  defp connection_attributes(attributes),
    do: " [#{Enum.join(Enum.map(attributes, fn {k, v} -> "#{k}=#{v}" end), ", ")}]"

  defp format_dot(dot_string) do
    dot_string
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.replace(~r/\n\n$/, "\n")
  end
end
