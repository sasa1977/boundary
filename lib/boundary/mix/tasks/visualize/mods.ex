defmodule Mix.Tasks.Boundary.Visualize.Mods do
  @shortdoc "Visualizes cross-module dependencies in one or more boundaries."

  @moduledoc """
  #{@shortdoc}

  Usage:

      mix boundary.visualize.mods Boundary1 Boundary2 ...

  The graph is printed to the standard output using the [graphviz dot language](https://graphviz.org/doc/info/lang.html).
  """

  use Boundary, classify_to: Boundary.Mix
  use Mix.Task

  alias Boundary.Graph
  alias Boundary.Mix.CompilerState

  @impl Mix.Task
  def run(argv) do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Quiet)
    Mix.Task.run("compile")
    Mix.shell(previous_shell)

    Boundary.Mix.load_app()

    view = Boundary.Mix.View.build()
    boundaries = Enum.map(argv, &Module.concat([&1]))

    state =
      for reference <- CompilerState.references(),
          boundary_from = Boundary.for_module(view, reference.from),
          not is_nil(boundary_from),
          boundary_from.name in boundaries,
          boundary_to = Boundary.for_module(view, reference.to),
          not is_nil(boundary_to),
          boundary_to.name in boundaries,
          reduce: %{main: Graph.new(""), subgraphs: %{}} do
        state ->
          state
          |> add_node(boundary_from.name, reference.from)
          |> add_node(boundary_to.name, reference.to)
          |> add_dependency(reference.from, reference.to)
      end

    Enum.reduce(Map.values(state.subgraphs), state.main, &Graph.add_subgraph(&2, &1))
    |> Graph.dot()
    |> Mix.shell().info()
  end

  defp add_node(state, subgraph_name, node) do
    subgraph =
      state.subgraphs
      |> Map.get_lazy(subgraph_name, fn -> Graph.new("Boundary #{inspect(subgraph_name)}") end)
      |> Graph.add_node(inspect(node), label: List.last(Module.split(node)))

    Map.update!(state, :subgraphs, &Map.put(&1, subgraph_name, subgraph))
  end

  defp add_dependency(state, caller, callee),
    do: Map.update!(state, :main, &Graph.add_dependency(&1, inspect(caller), inspect(callee)))
end
