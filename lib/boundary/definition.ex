# credo:disable-for-this-file Credo.Check.Readability.Specs

defmodule Boundary.Definition do
  @moduledoc false

  def generate(opts, env) do
    opts =
      opts
      # This ensures that alias references passed to `use Boundary` (e.g. deps, exports) are not
      # treated as dependencies (neither compile-time nor runtime) by the Elixir compiler.
      #
      # For example, invoking `use Boundary, deps: [MySystem]` in `MySystemWeb` won't add a
      # dependency from `MySystemWeb` to `MySystem`. We can do this safely here since we're not
      # injecting any calls to the modules referenced in `opts`.
      |> Macro.prewalk(fn term ->
        with {:__aliases__, _, _} <- term,
             do: Macro.expand(term, %{env | function: {:boundary, 1}, lexical_tracker: nil})
      end)
      |> Enum.map(fn opt ->
        with {key, references} when key in ~w/deps exports dirty_xrefs/a and is_list(references) <- opt,
             do: {key, expand_references(references)}
      end)

    pos = Macro.escape(%{file: env.file, line: env.line})

    quote bind_quoted: [opts: opts, app: Keyword.fetch!(Mix.Project.config(), :app), pos: pos] do
      @opts opts
      @pos pos
      @app app

      # Definition will be injected before compile, because we need to check if this module is
      # a protocol, which we can only do right before the module is about to be compiled.
      @before_compile Boundary.Definition
    end
  end

  defp expand_references(references) do
    Enum.flat_map(
      references,
      fn
        reference ->
          case Macro.decompose_call(reference) do
            {parent, :{}, children} -> Enum.map(children, &Module.concat(parent, &1))
            _ -> [reference]
          end
      end
    )
  end

  @doc false
  defmacro __before_compile__(_) do
    quote do
      Module.register_attribute(__MODULE__, Boundary, persist: true, accumulate: false)

      protocol? = Module.defines?(__MODULE__, {:__impl__, 1}, :def)
      mix_task? = String.starts_with?(inspect(__MODULE__), "Mix.Tasks.")

      data = %{opts: @opts, pos: @pos, app: @app, protocol?: protocol?, mix_task?: mix_task?}

      Boundary.Mix.CompilerState.add_module_meta(__MODULE__, :boundary_def, data)
      Module.put_attribute(__MODULE__, Boundary, data)
    end
  end

  def get(boundary, defs) do
    with definition when not is_nil(definition) <- definition(boundary, defs) do
      case Keyword.pop(definition.opts, :classify_to, nil) do
        {nil, opts} ->
          normalize(definition.app, boundary, opts, definition.pos)

        {classify_to, opts} ->
          target_definition = definition(classify_to, defs)

          cond do
            is_nil(target_definition) or Keyword.get(target_definition.opts, :classify_to) != nil ->
              normalize(definition.app, boundary, opts, definition.pos)
              |> add_errors([
                {:unknown_boundary, name: classify_to, file: definition.pos.file, line: definition.pos.line}
              ])

            not definition.protocol? and not definition.mix_task? ->
              normalize(definition.app, boundary, opts, definition.pos)
              |> add_errors([{:cant_reclassify, name: boundary, file: definition.pos.file, line: definition.pos.line}])

            true ->
              nil
          end
      end
    end
  end

  def classified_to(module, defs) do
    with definition when not is_nil(definition) <- definition(module, defs),
         {:ok, boundary} <- Keyword.fetch(definition.opts, :classify_to),
         true <- definition.protocol? or definition.mix_task? do
      %{boundary: boundary, file: definition.pos.file, line: definition.pos.line}
    else
      _ -> nil
    end
  end

  defp definition(boundary, nil) do
    with true <- :code.get_object_code(boundary) != :error,
         [definition] <- Keyword.get(boundary.__info__(:attributes), Boundary),
         do: definition,
         else: (_ -> nil)
  end

  defp definition(boundary, defs), do: Map.get(defs, boundary)

  @doc false
  def normalize(app, boundary, definition, pos \\ %{file: nil, line: nil}) do
    definition
    |> normalize!(app, pos)
    |> normalize_check()
    |> normalize_exports(boundary)
    |> normalize_deps()
    |> Map.update!(:dirty_xrefs, &MapSet.new/1)
  end

  defp normalize!(user_opts, app, pos) do
    defaults()
    |> Map.merge(project_defaults(user_opts))
    |> Map.merge(%{file: pos.file, line: pos.line, app: app})
    |> merge_user_opts(user_opts)
    |> validate(&if &1.type not in ~w/strict relaxed/a, do: :invalid_type)
  end

  defp merge_user_opts(definition, user_opts) do
    user_opts =
      case Keyword.get(user_opts, :ignore?) do
        nil -> user_opts
        value -> Config.Reader.merge([check: [in: not value, out: not value]], user_opts)
      end

    user_opts = Map.new(user_opts)
    valid_keys = ~w/deps exports dirty_xrefs check type top_level?/a

    definition
    |> Map.merge(Map.take(user_opts, valid_keys))
    |> add_errors(
      user_opts
      |> Map.drop(valid_keys)
      |> Enum.map(fn {key, value} -> {:unknown_option, name: key, value: value} end)
    )
  end

  defp normalize_exports(%{exports: :all} = definition, boundary),
    do: normalize_exports(%{definition | exports: {:all, []}}, boundary)

  defp normalize_exports(%{exports: {:all, opts}} = definition, boundary),
    do: %{definition | exports: [{boundary, opts}]}

  defp normalize_exports(definition, boundary) do
    update_in(
      definition.exports,
      fn exports -> Enum.map(exports, &normalize_export(boundary, &1)) end
    )
  end

  defp normalize_export(boundary, export) when is_atom(export), do: Module.concat(boundary, export)
  defp normalize_export(boundary, {export, opts}), do: {Module.concat(boundary, export), opts}

  defp normalize_check(definition) do
    definition.check
    |> update_in(&Map.new(Keyword.merge([in: true, out: true, aliases: false, apps: []], &1)))
    |> update_in([:check, :apps], &normalize_check_apps/1)
    |> validate(&if not &1.check.in and &1.exports != [], do: :exports_in_check_in_false)
    |> validate(&if not &1.check.out and &1.deps != [], do: :deps_in_check_out_false)
    |> validate(&if not &1.check.out and &1.check.apps != [], do: :apps_in_check_out_false)
  end

  defp normalize_check_apps(apps) do
    Enum.flat_map(apps, fn
      {_app, _type} = entry -> [entry]
      app when is_atom(app) -> [{app, :runtime}, {app, :compile}]
    end)
  end

  defp normalize_deps(definition) do
    update_in(
      definition.deps,
      &Enum.map(
        &1,
        fn
          {_dep, _type} = dep -> dep
          dep when is_atom(dep) -> {dep, :runtime}
        end
      )
    )
  end

  defp defaults do
    %{
      deps: [],
      exports: [],
      dirty_xrefs: [],
      check: [],
      type: :relaxed,
      errors: [],
      top_level?: false
    }
  end

  defp project_defaults(user_opts) do
    if user_opts[:check][:out] == false do
      %{}
    else
      (Mix.Project.config()[:boundary][:default] || [])
      |> Keyword.take(~w/type check/a)
      |> Map.new()
    end
  end

  defp add_errors(definition, errors) do
    errors = Enum.map(errors, &full_error(&1, definition))
    update_in(definition.errors, &Enum.concat(&1, errors))
  end

  defp full_error(tag, definition) when is_atom(tag), do: full_error({tag, []}, definition)

  defp full_error({tag, data}, definition),
    do: {tag, data |> Map.new() |> Map.merge(Map.take(definition, ~w/file line/a))}

  defp validate(definition, check) do
    case check.(definition) do
      nil -> definition
      error -> add_errors(definition, [error])
    end
  end
end
