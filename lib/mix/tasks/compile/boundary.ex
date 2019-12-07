defmodule Mix.Tasks.Compile.Boundary do
  # credo:disable-for-this-file Credo.Check.Readability.Specs

  use Boundary, deps: [Boundary]
  use Mix.Task.Compiler
  alias Boundary.Xref

  @moduledoc """
  Verifies cross-module function calls according to defined boundaries.

  This compiler reports all cross-boundary function calls which are not permitted, according to
  the current definition of boundaries. For details on defining boundaries, see the docs for the
  `Boundary` module.

  ## Usage

  Once you have configured the boundaries, you need to include the compiler in `mix.exs`:

  ```
  defmodule MySystem.MixProject do
    # ...

    def project do
      [
        compilers: [:boundary] ++ Mix.compilers(),
        # ...
      ]
    end

    # ...
  end
  ```

  When developing a library, it's advised to use this compiler only in `:dev` and `:test`
  environments:

  ```
  defmodule Boundary.MixProject do
    # ...

    def project do
      [
        compilers: extra_compilers(Mix.env()) ++ Mix.compilers(),
        # ...
      ]
    end

    # ...

    defp extra_compilers(:prod), do: []
    defp extra_compilers(_env), do: [:boundaries]
  end
  ```

  ## Warnings

  Every invalid cross-boundary call is reported as a compiler warning. Consider the following example:

  ```
  defmodule MySystem.User do
    def auth() do
      MySystemWeb.Endpoint.url()
    end
  end
  ```

  Assuming that calls from `MySystem` to `MySystemWeb` are not allowed, you'll get the following warning:

  ```
  $ mix compile

  warning: forbidden call to MySystemWeb.Endpoint.url/0
    (calls from MySystem to MySystemWeb are not allowed)
    (call originated from MySystem.User)
    lib/my_system/user.ex:3
  ```

  Since the compiler emits warnings, `mix compile` will still succeed, and you can normally start
  your system, even if some boundary rules are violated. The compiler doesn't force you to immediately
  fix these violations, which is a deliberate decision made to avoid disrupting the development flow.

  At the same time, it's worth enforcing boundaries on the CI. This can easily be done by providing
  the `--warnings-as-errors` option to `mix compile`.
  """

  @recursive true

  @impl Mix.Task.Compiler
  def run(argv) do
    Xref.start_link(path())
    Mix.Task.Compiler.after_compiler(:app, &after_compiler(&1, argv))

    tracers = Code.get_compiler_option(:tracers)
    Code.put_compiler_option(:tracers, [__MODULE__ | tracers])

    {:ok, []}
  end

  @doc false
  def trace({remote, meta, callee_module, name, arity}, env) when remote in ~w/remote_function remote_macro/a do
    if env.module != nil do
      Xref.add_call(
        env.module,
        %{callee: {callee_module, name, arity}, file: Path.relative_to_cwd(env.file), line: meta[:line]}
      )
    end

    :ok
  end

  def trace(_event, _env), do: :ok

  defp after_compiler({:ok, diagnostics}, argv) do
    tracers = Enum.reject(Code.get_compiler_option(:tracers), &(&1 == __MODULE__))
    Code.put_compiler_option(:tracers, tracers)

    calls = Xref.calls(path(), app_modules())

    errors = Boundary.MixCompiler.check(calls: calls)
    print_diagnostic_errors(errors)
    {status(errors, argv), diagnostics ++ errors}
  end

  defp after_compiler(status, _argv), do: status

  defp app_modules do
    app = Keyword.fetch!(Mix.Project.config(), :app)
    Application.load(app)
    Application.spec(app, :modules)
  end

  defp status([], _), do: :ok
  defp status([_ | _], argv), do: if(warnings_as_errors?(argv), do: :error, else: :ok)

  defp warnings_as_errors?(argv) do
    {parsed, _argv, _errors} = OptionParser.parse(argv, strict: [warnings_as_errors: :boolean])
    Keyword.get(parsed, :warnings_as_errors, false)
  end

  defp print_diagnostic_errors(errors) do
    if errors != [], do: IO.puts("")
    Enum.each(errors, &print_diagnostic_error/1)
  end

  defp print_diagnostic_error(error) do
    Mix.shell().info([severity(error.severity), error.message, location(error)])
  end

  defp location(error) do
    if error.file != nil and error.file != "" do
      pos = if error.position != nil, do: ":#{error.position}", else: ""
      "\n  #{error.file}#{pos}\n"
    else
      "\n"
    end
  end

  defp severity(severity), do: [:bright, color(severity), "#{severity}: ", :reset]
  defp color(:error), do: :red
  defp color(:warning), do: :yellow

  defp path, do: Path.join(Mix.Project.build_path(), "boundary_calls.ets")
end
