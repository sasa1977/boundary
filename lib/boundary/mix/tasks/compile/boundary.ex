defmodule Mix.Tasks.Compile.Boundary do
  # credo:disable-for-this-file Credo.Check.Readability.Specs

  use Boundary, classify_to: Boundary.Mix
  use Mix.Task.Compiler
  alias Boundary.Mix.CompilerState

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
    {opts, _rest, _errors} = OptionParser.parse(argv, strict: [force: :boolean, warnings_as_errors: :boolean])

    CompilerState.start_link(Keyword.take(opts, [:force]))
    Mix.Task.Compiler.after_compiler(:elixir, &after_elixir_compiler/1)
    Mix.Task.Compiler.after_compiler(:app, &after_app_compiler(&1, opts))

    tracers = Code.get_compiler_option(:tracers)
    Code.put_compiler_option(:tracers, [__MODULE__ | tracers])

    {:ok, []}
  end

  @doc false
  def trace({remote, meta, to_module, _name, _arity}, env)
      when remote in ~w/remote_function imported_function remote_macro imported_macro/a do
    mode = if is_nil(env.function) or remote in ~w/remote_macro imported_macro/a, do: :compile, else: :runtime
    record(to_module, meta, env, mode, :call)
  end

  def trace({local, _meta, _to_module, _name, _arity}, env)
      when local in ~w/local_function local_macro/a,
      # We need to initialize module although we're not going to record the call, to correctly remove previously
      # recorded entries when the module is recompiled.
      do: initialize_module(env.module)

  def trace({:struct_expansion, meta, to_module, _keys}, env),
    do: record(to_module, meta, env, :compile, :struct_expansion)

  def trace({:alias_reference, meta, to_module}, env) do
    unless env.function == {:boundary, 1} do
      mode = if is_nil(env.function), do: :compile, else: :runtime
      record(to_module, meta, env, mode, :alias_reference)
    end

    :ok
  end

  def trace({:on_module, _bytecode, _ignore}, env) do
    CompilerState.add_module_meta(env.module, :protocol?, Module.defines?(env.module, {:__impl__, 1}, :def))
    :ok
  end

  def trace(_event, _env), do: :ok

  defp record(to_module, meta, env, mode, type) do
    # We need to initialize module even if we're not going to record the call, to correctly remove previously
    # recorded entries when the module is recompiled.
    initialize_module(env.module)

    unless env.module in [nil, to_module] or system_module?(to_module) or
             not String.starts_with?(Atom.to_string(to_module), "Elixir.") do
      CompilerState.record_references(
        env.module,
        %{
          from_function: env.function,
          to: to_module,
          mode: mode,
          type: type,
          file: Path.relative_to_cwd(env.file),
          line: Keyword.get(meta, :line, env.line)
        }
      )
    end

    :ok
  end

  defp initialize_module(module),
    do: unless(is_nil(module), do: CompilerState.initialize_module(module))

  # Building the list of "system modules", which we'll exclude from the traced data, to reduce the collected data and
  # processing time.
  system_apps = ~w/elixir stdlib kernel/a

  system_apps
  |> Stream.each(&Application.load/1)
  |> Stream.flat_map(&Application.spec(&1, :modules))
  # We'll also include so called preloaded modules (e.g. `:erlang`, `:init`), which are not a part of any app.
  |> Stream.concat(:erlang.pre_loaded())
  |> Enum.each(fn module -> defp system_module?(unquote(module)), do: true end)

  defp system_module?(_module), do: false

  defp after_elixir_compiler(outcome) do
    # Unloading the tracer after Elixir compiler, irrespective of the outcome. This ensures that the tracer is correctly
    # unloaded even if the compilation fails.
    tracers = Enum.reject(Code.get_compiler_option(:tracers), &(&1 == __MODULE__))
    Code.put_compiler_option(:tracers, tracers)
    outcome
  end

  defp after_app_compiler(outcome, opts) do
    # Perform the boundary checks only on a successfully compiled app, to avoid false positives.
    with {status, diagnostics} when status in [:ok, :noop] <- outcome do
      # We're reloading the app to make sure we have the latest version. This fixes potential stale state in ElixirLS.
      Application.unload(Boundary.Mix.app_name())
      Application.load(Boundary.Mix.app_name())

      CompilerState.flush(Application.spec(Boundary.Mix.app_name(), :modules) || [])

      # Caching of the built view for non-user apps. A user app is the main app of the project, and all local deps
      # (in-umbrella and path deps). All other apps are library dependencies, and we're caching the boundary view of such
      # apps, because that view isn't changing, and we want to avoid loading modules of those apps on every compilation,
      # since that's very slow.
      user_apps =
        for {app, [_ | _] = opts} <- Keyword.get(Mix.Project.config(), :deps, []),
            Enum.any?(opts, &(&1 == {:in_umbrella, true} or match?({:path, _}, &1))),
            into: MapSet.new([Boundary.Mix.app_name()]),
            do: app

      view = Boundary.Mix.View.refresh(user_apps, Keyword.take(opts, ~w/force/a))

      errors = check(view, CompilerState.references())
      print_diagnostic_errors(errors)
      {status(errors, opts), diagnostics ++ errors}
    end
  end

  defp status([], _), do: :ok
  defp status([_ | _], opts), do: if(Keyword.get(opts, :warnings_as_errors, false), do: :error, else: :ok)

  defp print_diagnostic_errors(errors) do
    if errors != [], do: Mix.shell().info("")
    Enum.each(errors, &print_diagnostic_error/1)
  end

  defp print_diagnostic_error(error) do
    Mix.shell().info([severity(error.severity), error.message, location(error)])
  end

  defp location(error) do
    if error.file != nil and error.file != "" do
      line = with tuple when is_tuple(tuple) <- error.position, do: elem(tuple, 0)
      pos = if line != nil, do: ":#{line}", else: ""
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
          module = inspect(error.reference.to)
          "(module #{module} is not exported by its owner boundary #{inspect(error.to_boundary)})"

        :invalid_external_dep_call ->
          "(references from #{inspect(error.from_boundary)} to #{inspect(error.to_boundary)} are not allowed)"
      end

    message = "forbidden reference to #{inspect(error.reference.to)}\n  #{reason}"

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

  defp to_diagnostic_error({:unused_dirty_xref, boundary, xref}) do
    diagnostic(
      "module #{inspect(xref)} doesn't need to be included in the `dirty_xrefs` list for the boundary #{inspect(boundary.name)}",
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
    diagnostic =
      %Mix.Task.Compiler.Diagnostic{
        compiler_name: "boundary",
        details: nil,
        file: nil,
        message: message,
        position: 0,
        severity: :warning
      }
      |> Map.merge(Map.new(opts))

    cond do
      diagnostic.file == nil ->
        %{diagnostic | file: "unknown"}

      diagnostic.position == 0 and File.exists?(diagnostic.file) ->
        num_lines =
          diagnostic.file
          |> File.stream!()
          |> Enum.count()

        %{diagnostic | position: {1, 0, num_lines + 1, 0}}

      true ->
        diagnostic
    end
  end
end
