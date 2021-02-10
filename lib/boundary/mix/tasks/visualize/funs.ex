# credo:disable-for-this-file Credo.Check.Readability.Specs

defmodule Mix.Tasks.Boundary.Visualize.Funs do
  @shortdoc "Visualizes cross-function dependencies in a single module."

  @moduledoc """
  #{@shortdoc}

  Usage:

      mix boundary.visualize.funs SomeModule

  The graph is printed to the standard output using the [graphviz dot language](https://graphviz.org/doc/info/lang.html).
  """

  use Boundary, classify_to: Boundary.Mix
  use Mix.Task

  alias Boundary.Graph

  @impl Mix.Task
  def run(argv) do
    unless match?([_], argv),
      do: Mix.raise("usage: mix boundary.visualize.functions SomeModule")

    tracers = Code.get_compiler_option(:tracers)
    Code.put_compiler_option(:tracers, [__MODULE__ | tracers])

    :ets.new(__MODULE__, [:named_table, :public, :duplicate_bag, write_concurrency: true])
    :persistent_term.put({__MODULE__, :module}, hd(argv))

    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Quiet)
    :persistent_term.put({__MODULE__, :shell}, previous_shell)

    # need to force recompile the project so we can collect traces
    Mix.Task.Compiler.after_compiler(:app, &after_compiler/1)
    Mix.Task.reenable("compile")
    Mix.Task.run("compile", ["--force"])
  end

  @doc false
  def trace({local, _meta, callee_fun, _arity}, env) when local in ~w/local_function local_macro/a do
    {caller_fun, _arity} = env.function

    if inspect(env.module) == :persistent_term.get({__MODULE__, :module}) and caller_fun != callee_fun,
      do: :ets.insert(__MODULE__, {caller_fun, callee_fun})

    :ok
  end

  def trace(_other, _env), do: :ok

  defp after_compiler(status) do
    Mix.shell(:persistent_term.get({__MODULE__, :shell}))
    Mix.shell().info(build_graph())
    status
  end

  defp build_graph do
    name = "function calls inside #{:persistent_term.get({__MODULE__, :module})}"

    calls()
    |> Enum.reduce(Graph.new(name), fn {from, to}, graph ->
      graph
      |> Graph.add_node(from)
      |> Graph.add_node(to)
      |> Graph.add_dependency(from, to)
    end)
    |> Graph.dot()
  end

  defp calls, do: :ets.tab2list(__MODULE__)
end
