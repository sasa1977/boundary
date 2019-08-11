defmodule Mix.Tasks.Compile.Boundaries do
  use Mix.Task.Compiler

  @moduledoc """
  Verifies cross-module function calls according to defined boundaries.

  A boundary is a named group of one or more modules. Each boundary exports some (but not all!)
  of its modules, and can depend on other boundaries. During compilation, the boundary compiler
  finds and reports all cross-module function calls which are not permitted according to the
  boundary configuration.

  ## Configuration

  Boundaries are configured in the `boundaries.exs` file in the root folder of the project. Here is
  a simple configuration example which defines two boundaries, `MySystem` and `MySystemWeb`:

  ```
  [
    {MySystem, deps: [], exports: [User]},
    {MySystemWeb, deps: [MySystem]}
  ]
  ```

  A boundary is an alias which contains one or more modules. Boundary modules are determined
  automatically from the boundary name. For example, the `MySystem` boundary contains the `MySystem`
  module, as well as any module whose name starts with `MySystem.` (e.g. `MySystem.User`,
  `MySystem.User.Schema`, ...).

  Each boundary must contain at least one module, and each module must be a part of some boundary.
  If these conditions are not met, the compiler will emit corresponding warnings.

  ### Dependencies

  Function calls between modules belonging to different boundaries are by default forbidden. You
  have to explicitly permit such calls through the `:deps` option:

  ```
  {MySystemWeb, deps: [MySystem]}
  ```

  Here, we allow invocations from `MySystemWeb` modules to `MySystem` modules.

  Dependencies are not transient. If `A` depends on `B`, and `B` depends on `C`, calls from
  `A` to `C` are still considered invalid. In addition, circular dependencies (direct or indirect)
  are not allowed.

  ### Exports

  Cross-boundary calls can only be made to the exported modules. By default, a boundary only
  exports the root module (i.e. the module having the same name as the boundary).

  Consider the following configuration:

  ```
  [
    {MySystem, deps: []},
    {MySystemWeb, deps: [MySystem]}
  ]
  ```

  With such configuration, all modules from the `MySystemWeb` boundary can make calls to functions
  from the `MySystem` module. However, calls to other modules, such as `MySystem.User`, are still
  not permitted.

  You can export additional modules from the boundary by providing the `:exports` option:

  ```
  [
    {MySystem, deps: [], exports: [User, Order]},
    {MySystemWeb, deps: [MySystem]}
  ]
  ```

  With such configuration, `MySystemWeb` modules can invoke functions from `MySystem`,
  `MySystem.User`, and `MySystem.Order`.

  Note that the root module is always exported.

  ### Promoting modules to boundaries

  It's worth mentioning that the example configurations you've seen so far won't work on a typical
  Phoenix project. The reason is that when you generate a Phoenix project with `mix phx.new`,
  the code in `MySystem.Application` references `MySystemWeb.Endpoint`:

  ```
  defmodule MySystem.Application do
    # ...

    def start(_type, _args) do
      children = [
        # reference to `MySystemWeb.Endpoint`
        MySystemWeb.Endpoint

        # ...
      ]

      # ...
    end

    # ...
  end
  ```

  To make this work, you need to turn `MySystem.Application` into a boundary, and export
  `Endpoint` in `MySystemWeb`:

  ```
  [
    {MySystem, deps: [], exports: [User]},
    {MySystemWeb, deps: [MySystem], exports: [Endpoint]},
    {MySystem.Application, deps: [MySystem, MySystemWeb]}
  ]
  ```

  With such configuration, the `MySystem` boundary won't include modules from `MySystem.Application`.
  These modules are now extracted into a separate boundary.

  ## Usage

  Once you have configured the boundaries, you need to include the compiler in `mix.exs`:

  ```
  defmodule MySystem.MixProject do
    # ...

    def project do
      [
        compilers: Mix.compilers() ++ [:boundaries],
        # ...
      ]
    end

    # ...
  end
  ```

  When developing a library, it's advised to use boundaries only in `:dev` and `:test` environments:

  ```
  defmodule Boundaries.MixProject do
    # ...

    def project do
      [
        compilers: Mix.compilers() ++ extra_compilers(Mix.env()),
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
  def run(_) do
    app = Keyword.fetch!(Mix.Project.config(), :app)
    Application.load(app)

    boundaries = load_boundaries!()
    calls = calls()
    app_modules = app_modules(app, calls)

    case Boundaries.check(boundaries, app_modules, calls) do
      :ok ->
        {:ok, []}

      {:error, errors} ->
        print_diagnostic_errors(errors)
        {:ok, errors}
    end
  end

  defp load_boundaries!() do
    with {:ok, config_string} <- config_string(),
         {:ok, boundaries} <- Boundaries.from_string(config_string) do
      boundaries
    else
      {:error, reason} -> Mix.raise(reason)
    end
  end

  defp config_string() do
    with {:error, _reason} <- File.read("boundaries.exs"),
         do: {:error, "could not open `boundaries.exs`"}
  end

  defp calls() do
    Enum.map(
      Mix.Tasks.Xref.calls(),
      fn %{callee: {mod, _fun, _arg}} = entry -> Map.put(entry, :callee_module, mod) end
    )
  end

  defp app_modules(app, calls) do
    calls
    |> Stream.map(& &1.caller_module)
    |> MapSet.new()
    |> MapSet.union(MapSet.new(Application.spec(app, :modules)))
  end

  defp print_diagnostic_errors(errors) do
    IO.puts("")
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
end
