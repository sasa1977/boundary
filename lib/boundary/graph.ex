defmodule Boundary.Graph do
  @moduledoc false

  @opaque t :: %{connections: %{node => node}, name: String.t(), nodes: MapSet.t(node)}
  @type node_name :: String.t()

  @spec new(node_name) :: t()
  def new(name) do
    %{connections: %{}, name: name, nodes: MapSet.new()}
  end

  @spec add_dependency(t(), node_name, node_name, List.t()) :: t()
  def add_dependency(graph, from, to, label \\ []) do
    %{connections: connections, name: name, nodes: nodes} = graph
    nodes = nodes |> MapSet.put(from) |> MapSet.put(to)
    connections = Map.update(connections, from, %{to => label}, &Map.merge(&1, %{to => label}))

    %{connections: connections, name: name, nodes: nodes}
  end

  @spec dot(t(), List.t()) :: node_name
  def dot(graph, opts \\ []) do
    """
    digraph {
      label=\"#{graph.name}\";
      labelloc=top;
    #{make_opts(opts)}
    #{nodes(graph)}

    #{connections(graph)}
    }
    """
  end

  defp nodes(graph), do: Enum.map(graph.nodes, fn node -> "  #{node} [shape=\"box\"];\n" end)

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
      do:
        case attributes do
          [] -> "  \"#{from}\" -> \"#{to}\";\n"
          _ -> "  \"#{from}\" -> \"#{to}\" #{connection_attributes(attributes)};\n"
        end
    )
    |> to_string()
  end

  defp opt_string(options) do
    Enum.map(options, fn {k, v} -> "  #{k}=#{v};\n" end)
  end

  defp connection_attributes(labels), do: Enum.map(labels, fn {k, v} -> "#{k}=#{v}" end)
end
