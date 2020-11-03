defmodule Mix.Tasks.Boundary.Visualize.Funs do
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
    name = "function calls inside #{:persistent_term.get({__MODULE__, :module})}"

    list = :ets.tab2list(__MODULE__)
    graph = Graph.new(name)

    graph =
      Enum.reduce(list, graph, fn {k, v}, graph ->
        graph
        |> Graph.add_node(k)
        |> Graph.add_node(v)
        |> Graph.add_dependency(k, v)
      end)

    Mix.shell().info(Graph.dot(graph))
    status
  end
end
