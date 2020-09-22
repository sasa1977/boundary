# credo:disable-for-this-file Credo.Check.Readability.Specs

defmodule Boundary.Definition do
  @moduledoc false

  def generate(opts) do
    # We'll store the definition as an encoded binary. This will avoid adding any runtime or
    # compile time dependencies to referenced modules (deps and exports).
    opts = :erlang.term_to_binary(opts)

    quote bind_quoted: [opts: opts, app: Keyword.fetch!(Mix.Project.config(), :app)] do
      @opts opts
      @env __ENV__
      @app app

      # Definition will be injected before compile, because we need to check if this module is
      # a protocol, which we can only do right before the module is about to be compiled.
      @before_compile Boundary.Definition
    end
  end

  @doc false
  defmacro __before_compile__(_) do
    quote do
      Module.register_attribute(__MODULE__, Boundary, persist: true, accumulate: false)

      protocol? = Module.defines?(__MODULE__, {:__impl__, 1}, :def)
      mix_task? = String.starts_with?(inspect(__MODULE__), "Mix.Tasks.")

      Module.put_attribute(
        __MODULE__,
        Boundary,
        %{
          opts: @opts,
          env: @env,
          app: @app,
          protocol?: protocol?,
          mix_task?: mix_task?
        }
      )
    end
  end

  def get(boundary) do
    with decoded when not is_nil(decoded) <- decode(boundary) do
      case Keyword.pop(decoded.opts, :classify_to, nil) do
        {nil, opts} ->
          normalize(decoded.app, boundary, opts, decoded.env)

        {classify_to, opts} ->
          decoded_target = decode(classify_to)

          cond do
            is_nil(decoded_target) or Keyword.get(decoded_target.opts, :classify_to) != nil ->
              normalize(decoded.app, boundary, opts, decoded.env)
              |> add_errors([{:unknown_boundary, name: classify_to, file: decoded.env.file, line: decoded.env.line}])

            not decoded.protocol? and not decoded.mix_task? ->
              normalize(decoded.app, boundary, opts, decoded.env)
              |> add_errors([{:cant_reclassify, name: boundary, file: decoded.env.file, line: decoded.env.line}])

            true ->
              nil
          end
      end
    end
  end

  def classified_to(module) do
    with decoded when not is_nil(decoded) <- decode(module),
         {:ok, boundary} <- Keyword.fetch(decoded.opts, :classify_to),
         true <- decoded.protocol? or decoded.mix_task? do
      %{boundary: boundary, file: decoded.env.file, line: decoded.env.line}
    else
      _ -> nil
    end
  end

  defp decode(boundary) do
    with true <- :code.get_object_code(boundary) != :error,
         [definition] <- Keyword.get(boundary.__info__(:attributes), Boundary) do
      Map.update!(
        definition,
        :opts,
        fn encoded ->
          {decoded, _} =
            encoded
            |> :erlang.binary_to_term()
            |> Enum.map(fn
              {key, references} when key in ~w/deps exports/a -> {key, expand_references(references, definition.env)}
              other -> other
            end)
            |> Code.eval_quoted([], definition.env)

          decoded
        end
      )
    else
      _ -> nil
    end
  end

  defp expand_references(references, env) do
    Enum.flat_map(
      references,
      fn
        reference ->
          case Macro.decompose_call(reference) do
            {parent, :{}, children} ->
              parent = expand_as_runtime_dep(parent, env)
              Enum.map(children, &Module.concat(parent, expand_as_runtime_dep(&1, env)))

            _ ->
              [expand_as_runtime_dep(reference, env)]
          end
      end
    )
  end

  defp expand_as_runtime_dep(reference, env),
    # This ensures that dependency to the reference is treated by the compiler as a runtime dep.
    # Strictly speaking this is not needed, since this function runs after the compilation.
    # However, we'll still do it because it's not dangerous, and it might reduce compilation time
    # in stateful compilers, such as ElixirLS.
    do: Macro.expand(reference, %{env | function: {:boundary, 1}})

  @doc false
  def normalize(app, boundary, definition, env) do
    definition
    |> normalize!(app, env)
    |> normalize_check()
    |> normalize_exports(boundary)
    |> normalize_deps()
  end

  defp normalize!(user_opts, app, env) do
    defaults()
    |> Map.merge(project_defaults(user_opts))
    |> Map.merge(%{file: env.file, line: env.line, app: app})
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
    valid_keys = ~w/deps exports check type top_level?/a

    definition
    |> Map.merge(Map.take(user_opts, valid_keys))
    |> add_errors(
      user_opts
      |> Map.drop(valid_keys)
      |> Enum.map(fn {key, value} -> {:unknown_option, name: key, value: value} end)
    )
  end

  defp normalize_exports(definition, boundary) do
    update_in(
      definition.exports,
      fn exports ->
        normalized_exports = Enum.map(exports, &normalize_export(boundary, &1))
        [{boundary, []} | normalized_exports]
      end
    )
  end

  defp normalize_export(boundary, export) when is_atom(export), do: normalize_export(boundary, {export, []})
  defp normalize_export(boundary, {export, opts}), do: {Module.concat(boundary, export), opts}

  defp normalize_check(definition) do
    definition.check
    |> update_in(&Map.new(Keyword.merge([in: true, out: true, apps: []], &1)))
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
      externals: [],
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
