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

        {_boundary, opts} ->
          if decoded.protocol? or decoded.mix_task? do
            nil
          else
            IO.warn(
              ":classify_to can only be provided in protocol implementations and mix tasks",
              Macro.Env.stacktrace(decoded.env)
            )

            normalize(decoded.app, boundary, opts, decoded.env)
          end
      end
    end
  end

  def classified_to(module) do
    with decoded when not is_nil(decoded) <- decode(module) do
      case Keyword.pop(decoded.opts, :classify_to, nil) do
        {nil, _opts} ->
          nil

        {boundary, opts} ->
          unless Enum.empty?(opts),
            do: IO.warn("no other option is allowed if :classify_to is provided", Macro.Env.stacktrace(decoded.env))

          if decoded.protocol? or decoded.mix_task?,
            do: %{boundary: boundary, file: decoded.env.file, line: decoded.env.line}
      end
    end
  end

  defp decode(boundary) do
    with [definition] <- Keyword.get(boundary.__info__(:attributes), Boundary) do
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
    |> normalize_exports(boundary)
    |> normalize_deps()
  end

  defp normalize!(user_opts, app, env) do
    defaults()
    |> Map.merge(%{file: env.file, line: env.line, app: app})
    |> merge_user_opts(user_opts)
    |> validate(&if &1.ignore? and &1.deps != [], do: :dep_in_ignored_boundary)
    |> validate(&if &1.ignore? and &1.exports != [], do: :export_in_ignored_boundary)
    |> validate(&if &1.externals_mode not in ~w/strict relaxed/a, do: :invalid_externals_mode)
    |> validate(&if &1.externals_mode == :strict and &1.check_apps != [], do: :check_apps_in_strict_mode)
  end

  defp merge_user_opts(definition, user_opts) do
    user_opts = Map.new(user_opts)
    valid_keys = ~w/deps exports ignore? check_apps externals_mode top_level?/a

    definition
    |> Map.merge(Map.take(user_opts, valid_keys))
    |> add_errors(user_opts |> Map.drop(valid_keys) |> Map.keys() |> Enum.map(&{:unknown_option, name: &1}))
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
      ignore?: false,
      externals: [],
      check_apps: [],
      externals_mode: Mix.Project.config() |> Keyword.get(:boundary, []) |> Keyword.get(:externals_mode, :relaxed),
      errors: [],
      top_level?: false
    }
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
