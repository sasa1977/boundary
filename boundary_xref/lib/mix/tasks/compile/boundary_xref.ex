defmodule Mix.Tasks.Compile.BoundaryXref do
  use Mix.Task.Compiler

  @recursive true

  def calls() do
    app = Keyword.fetch!(Mix.Project.config(), :app)
    Application.load(app)
    app_modules = MapSet.new(Application.spec(app, :modules))
    BoundaryXref.finalize(app_modules)
    Enum.map(BoundaryXref.calls(path()), fn {caller, meta} -> Map.put(meta, :caller_module, caller) end)
  end

  @impl Mix.Task.Compiler
  def run(_argv) do
    BoundaryXref.start_link(path())
    Mix.Task.Compiler.after_compiler(:app, &after_compiler/1)

    tracers = Code.get_compiler_option(:tracers)
    Code.put_compiler_option(:tracers, [__MODULE__ | tracers])

    {:ok, []}
  end

  @doc false
  def trace({remote, meta, callee_module, name, arity}, env) when remote in ~w/remote_function remote_macro/a do
    if env.module != nil do
      BoundaryXref.add_call(
        env.module,
        %{callee: {callee_module, name, arity}, file: Path.relative_to_cwd(env.file), line: meta[:line]}
      )
    end

    :ok
  end

  def trace(_event, _env), do: :ok

  defp after_compiler(status) do
    BoundaryXref.finalize()
    tracers = Enum.reject(Code.get_compiler_option(:tracers), &(&1 == __MODULE__))
    Code.put_compiler_option(:tracers, tracers)
    status
  end

  defp path(), do: Path.join(Mix.Project.build_path(), "boundary_calls.dets")
end
