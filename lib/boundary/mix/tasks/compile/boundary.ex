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
    defp extra_compilers(_env), do: [:boundary]
  end
  ```

  ## Warnings

  Every invalid cross-boundary usage is reported as a compiler warning. Consider the following example:

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

  warning: forbidden reference to MySystemWeb
    (references from MySystem to MySystemWeb are not allowed)
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
  def trace({remote, meta, to_module, name, arity}, env)
      when remote in ~w/remote_function imported_function remote_macro imported_macro/a do
    mode = if is_nil(env.function) or remote in ~w/remote_macro imported_macro/a, do: :compile, else: :runtime
    record(to_module, meta, env, mode, {to_module, name, arity})
  end

  def trace({:struct_expansion, meta, to_module, _keys}, env),
    do: record(to_module, meta, env, :compile, {:struct_expansion, to_module})

  def trace({:alias_reference, meta, to_module}, env) do
    unless env.function == {:boundary, 1} do
      mode = if is_nil(env.function), do: :compile, else: :runtime
      record(to_module, meta, env, mode, {:alias_reference, to_module})
    end

    :ok
  end

  def trace(_event, _env), do: :ok

  defp record(to_module, meta, env, mode, to) do
    unless env.module in [nil, to_module] or system_module?(to_module) or
             not String.starts_with?(Atom.to_string(to_module), "Elixir.") do
      Xref.record(
        env.module,
        %{
          to: to,
          from: env.function,
          file: Path.relative_to_cwd(env.file),
          line: Keyword.get(meta, :line, env.line),
          mode: mode
        }
      )
    end

    :ok
  end

  system_apps = ~w/elixir stdlib kernel/a

  system_apps
  |> Stream.each(&Application.load/1)
  |> Stream.flat_map(&Application.spec(&1, :modules))
  |> Enum.each(fn module -> defp system_module?(unquote(module)), do: true end)

  defp system_module?(module), do: :code.which(module) == :preloaded

  defp after_compiler({:error, _} = status, _argv), do: status

  defp after_compiler({status, diagnostics}, argv) when status in [:ok, :noop] do
    # We're reloading the app to make sure we have the latest version. This fixes potential stale state in ElixirLS.
    Application.unload(Boundary.Mix.app_name())
    Application.load(Boundary.Mix.app_name())

    tracers = Enum.reject(Code.get_compiler_option(:tracers), &(&1 == __MODULE__))
    Code.put_compiler_option(:tracers, tracers)
    Xref.flush(Application.spec(Boundary.Mix.app_name(), :modules) || [])

    view =
      case Boundary.Mix.read_manifest("boundary_view") do
        nil -> rebuild_view()
        view -> Boundary.View.refresh(view) || rebuild_view()
      end

    Boundary.Mix.write_manifest("boundary_view", Boundary.View.drop_main_app(view))

    errors = check(view, Xref.entries())
    print_diagnostic_errors(errors)
    {status(errors, argv), diagnostics ++ errors}
  end

  defp rebuild_view do
    Boundary.Mix.load_app()
    Boundary.View.build(Boundary.Mix.app_name())
  end

  defp status([], _), do: :ok
  defp status([_ | _], argv), do: if(warnings_as_errors?(argv), do: :error, else: :ok)

  defp warnings_as_errors?(argv) do
    {parsed, _argv, _errors} = OptionParser.parse(argv, strict: [warnings_as_errors: :boolean])
    Keyword.get(parsed, :warnings_as_errors, false)
  end

  defp print_diagnostic_errors(errors) do
    if errors != [], do: Mix.shell().info("")
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

  defp check(application, entries) do
    Boundary.errors(application, entries)
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

  defp to_diagnostic_error({:check_in_false_dep, dep}) do
    diagnostic("boundary #{inspect(dep.name)} can't be a dependency because it has check.in set to false",
      file: Path.relative_to_cwd(dep.file),
      position: dep.line
    )
  end

  defp to_diagnostic_error({:forbidden_dep, dep}) do
    diagnostic(
      "#{inspect(dep.name)} can't be listed as a dependency because it's not a sibling, a parent, or a dep of some ancestor",
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

  defp to_diagnostic_error({:unknown_boundary, info}) do
    diagnostic("unknown boundary #{inspect(info.name)}",
      file: Path.relative_to_cwd(info.file),
      position: info.line
    )
  end

  defp to_diagnostic_error({:cant_reclassify, info}) do
    diagnostic("only mix task and protocol implementation can be reclassified",
      file: Path.relative_to_cwd(info.file),
      position: info.line
    )
  end

  defp to_diagnostic_error({:invalid_reference, error}) do
    reason =
      case error.type do
        :normal ->
          "(references from #{inspect(error.from_boundary)} to #{inspect(error.to_boundary)} are not allowed)"

        :runtime ->
          "(runtime references from #{inspect(error.from_boundary)} to #{inspect(error.to_boundary)} are not allowed)"

        :not_exported ->
          module = inspect(Boundary.Reference.to_module(error.reference))
          "(module #{module} is not exported by its owner boundary #{inspect(error.to_boundary)})"

        :invalid_external_dep_call ->
          "(references from #{inspect(error.from_boundary)} to #{inspect(error.to_boundary)} are not allowed)"
      end

    message = "forbidden reference to #{inspect(Boundary.Reference.to_module(error.reference))}\n  #{reason}"

    diagnostic(message, file: Path.relative_to_cwd(error.reference.file), position: error.reference.line)
  end

  defp to_diagnostic_error({:unknown_option, %{name: :ignore?, value: value} = data}) do
    diagnostic(
      "ignore?: #{value} is deprecated, use check: [in: #{not value}, out: #{not value}] instead",
      file: Path.relative_to_cwd(data.file),
      position: data.line
    )
  end

  defp to_diagnostic_error({:unknown_option, data}) do
    diagnostic("unknown option #{inspect(data.name)}",
      file: Path.relative_to_cwd(data.file),
      position: data.line
    )
  end

  defp to_diagnostic_error({:deps_in_check_out_false, data}) do
    diagnostic("deps can't be listed if check.out is set to false",
      file: Path.relative_to_cwd(data.file),
      position: data.line
    )
  end

  defp to_diagnostic_error({:apps_in_check_out_false, data}) do
    diagnostic("check apps can't be listed if check.out is set to false",
      file: Path.relative_to_cwd(data.file),
      position: data.line
    )
  end

  defp to_diagnostic_error({:exports_in_check_in_false, data}) do
    diagnostic("can't export modules if check.in is set to false",
      file: Path.relative_to_cwd(data.file),
      position: data.line
    )
  end

  defp to_diagnostic_error({:invalid_type, data}) do
    diagnostic("invalid type",
      file: Path.relative_to_cwd(data.file),
      position: data.line
    )
  end

  defp to_diagnostic_error({:invalid_ignores, boundary}) do
    diagnostic("can't disable checks in a sub-boundary",
      file: Path.relative_to_cwd(boundary.file),
      position: boundary.line
    )
  end

  defp to_diagnostic_error({:ancestor_with_ignored_checks, boundary, ancestor}) do
    diagnostic("sub-boundary inside a boundary with disabled checks (#{inspect(ancestor.name)})",
      file: Path.relative_to_cwd(boundary.file),
      position: boundary.line
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
