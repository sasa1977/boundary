defmodule Mix.Tasks.Compile.Boundary do
  # credo:disable-for-this-file Credo.Check.Readability.Specs

  use Boundary, classify_to: Boundary.Mix
  use Mix.Task.Compiler
  alias Boundary.Mix.Xref

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
    Xref.start_link()
    Mix.Task.Compiler.after_compiler(:app, &after_compiler(&1, argv))

    tracers = Code.get_compiler_option(:tracers)
    Code.put_compiler_option(:tracers, [__MODULE__ | tracers])

    {:ok, []}
  end

  @doc false
  def trace({remote, meta, callee_module, name, arity}, env)
      when remote in ~w/remote_function imported_function remote_macro imported_macro/a do
    unless env.module in [nil, callee_module] or system_module?(callee_module) or
             not String.starts_with?(Atom.to_string(callee_module), "Elixir.") do
      Xref.add_call(
        env.module,
        %{
          callee: {callee_module, name, arity},
          file: Path.relative_to_cwd(env.file),
          line: Keyword.get(meta, :line, env.line),
          mode:
            if(is_nil(env.function) or remote in ~w/remote_macro imported_macro/a,
              do: :compile,
              else: :runtime
            )
        }
      )
    end

    :ok
  end

  def trace(_event, _env), do: :ok

  system_apps = ~w/elixir stdlib kernel/a

  system_apps
  |> Stream.each(&Application.load/1)
  |> Stream.flat_map(&Application.spec(&1, :modules))
  |> Enum.each(fn module -> defp system_module?(unquote(module)), do: true end)

  defp system_module?(module), do: :code.which(module) == :preloaded

  defp after_compiler({:error, _} = status, _argv), do: status

  defp after_compiler({status, diagnostics}, argv) when status in [:ok, :noop] do
    Boundary.Mix.load_app()

    tracers = Enum.reject(Code.get_compiler_option(:tracers), &(&1 == __MODULE__))
    Code.put_compiler_option(:tracers, tracers)
    Xref.flush(Application.spec(Boundary.Mix.app_name(), :modules) || [])

    errors = check(Boundary.view(Boundary.Mix.app_name()), Xref.calls())
    print_diagnostic_errors(errors)
    {status(errors, argv), diagnostics ++ errors}
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

  defp check(application, calls) do
    Boundary.errors(application, calls)
    |> Stream.map(&to_diagnostic_error/1)
    |> Enum.sort_by(&{&1.file, &1.position})
  rescue
    e in Boundary.Error ->
      [diagnostic(e.message, file: e.file, position: e.line)]
  end

  defp to_diagnostic_error({:unclassified_module, module}),
    do: diagnostic("#{inspect(module)} is not included in any boundary", file: module_source(module))

  defp to_diagnostic_error({:unknown_dep, dep}) do
    diagnostic("unknown boundary #{inspect(dep.name)} is listed as a dependency",
      file: Path.relative_to_cwd(dep.file),
      position: dep.line
    )
  end

  defp to_diagnostic_error({:ignored_dep, dep}) do
    diagnostic("ignored boundary #{inspect(dep.name)} is listed as a dependency",
      file: Path.relative_to_cwd(dep.file),
      position: dep.line
    )
  end

  defp to_diagnostic_error({:unknown_export, export}) do
    diagnostic("unknown module #{inspect(export.name)} is listed as an export",
      file: Path.relative_to_cwd(export.file),
      position: export.line
    )
  end

  defp to_diagnostic_error({:export_not_in_boundary, export}) do
    diagnostic("module #{inspect(export.name)} can't be exported because it's not a part of this boundary",
      file: Path.relative_to_cwd(export.file),
      position: export.line
    )
  end

  defp to_diagnostic_error({:cycle, cycle}) do
    cycle = cycle |> Stream.map(&inspect/1) |> Enum.join(" -> ")
    diagnostic("dependency cycle found:\n#{cycle}\n")
  end

  defp to_diagnostic_error({:invalid_call, %{type: type} = error}) when type in ~w/runtime call/a do
    {m, f, a} = error.callee

    call_display =
      case type do
        :runtime -> "runtime call"
        :call -> "call"
      end

    message =
      "forbidden #{call_display} to #{Exception.format_mfa(m, f, a)}\n" <>
        "  (#{call_display}s from #{inspect(error.from_boundary)} to #{inspect(error.to_boundary)} are not allowed)\n" <>
        "  (call originated from #{inspect(error.caller)})"

    diagnostic(message, file: Path.relative_to_cwd(error.file), position: error.line)
  end

  defp to_diagnostic_error({:invalid_call, %{type: :not_exported} = error}) do
    {m, f, a} = error.callee

    message =
      "forbidden call to #{Exception.format_mfa(m, f, a)}\n" <>
        "  (module #{inspect(m)} is not exported by its owner boundary #{inspect(error.to_boundary)})\n" <>
        "  (call originated from #{inspect(error.caller)})"

    diagnostic(message, file: Path.relative_to_cwd(error.file), position: error.line)
  end

  defp to_diagnostic_error({:invalid_call, %{type: :invalid_external_dep_call} = error}) do
    {m, f, a} = error.callee

    message =
      "forbidden call to #{Exception.format_mfa(m, f, a)}\n" <>
        "  (calls from #{inspect(error.from_boundary)} to #{inspect(error.to_boundary)} are not allowed)\n" <>
        "  (call originated from #{inspect(error.caller)})"

    diagnostic(message, file: Path.relative_to_cwd(error.file), position: error.line)
  end

  defp to_diagnostic_error({:unknown_option, data}) do
    diagnostic("unknown option #{inspect(data.name)}",
      file: Path.relative_to_cwd(data.file),
      position: data.line
    )
  end

  defp to_diagnostic_error({:dep_in_ignored_boundary, data}) do
    diagnostic("deps can't be provided in an ignored boundary",
      file: Path.relative_to_cwd(data.file),
      position: data.line
    )
  end

  defp to_diagnostic_error({:export_in_ignored_boundary, data}) do
    diagnostic("exports can't be provided in an ignored boundary",
      file: Path.relative_to_cwd(data.file),
      position: data.line
    )
  end

  defp to_diagnostic_error({:invalid_externals_mode, data}) do
    diagnostic("invalid externals_mode",
      file: Path.relative_to_cwd(data.file),
      position: data.line
    )
  end

  defp to_diagnostic_error({:extra_externals_in_strict_mode, data}) do
    diagnostic("extra_externals can't be provided in strict mode",
      file: Path.relative_to_cwd(data.file),
      position: data.line
    )
  end

  defp module_source(module) do
    module.module_info(:compile)
    |> Keyword.fetch!(:source)
    |> to_string()
    |> Path.relative_to_cwd()
  catch
    _, _ -> ""
  end

  def diagnostic(message, opts \\ []) do
    %Mix.Task.Compiler.Diagnostic{
      compiler_name: "boundary",
      details: nil,
      file: "unknown",
      message: message,
      position: nil,
      severity: :warning
    }
    |> Map.merge(Map.new(opts))
  end
end
