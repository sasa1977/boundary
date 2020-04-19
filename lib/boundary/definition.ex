defmodule Boundary.Definition do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  defmacro generate(opts), do: generate(__CALLER__, opts)

  def generate(caller, opts) do
    opts =
      Enum.map(
        opts,
        fn
          {key, references} when key in ~w/deps exports/a -> {key, normalize_references(references, caller)}
          other -> other
        end
      )

    quote bind_quoted: [opts: opts, app: Keyword.fetch!(Mix.Project.config(), :app)] do
      @boundary_opts opts
      @env __ENV__
      @app app

      # Definition will be injected in before compile, because we need to check if this module is
      # a protocol, which we can only do right before the module is about to be compiled.
      @before_compile Boundary.Definition
    end
  end

  defp normalize_references(references, caller) do
    Enum.flat_map(
      references,
      fn
        reference ->
          references =
            case Macro.decompose_call(reference) do
              {parent, :{}, children} -> Enum.map(children, &quote(do: Module.concat(unquote([parent, &1]))))
              _ -> [reference]
            end

          Enum.map(references, &Macro.expand(&1, %{caller | function: {:boundary, 1}}))
      end
    )
  end

  @doc false
  defmacro __before_compile__(_) do
    quote do
      case Keyword.pop(@boundary_opts, :classify_to, nil) do
        {nil, opts} ->
          Module.register_attribute(__MODULE__, Boundary, persist: true, accumulate: false)

          Module.put_attribute(
            __MODULE__,
            Boundary,
            Boundary.Definition.normalize(@app, __MODULE__, opts, @env)
          )

        {boundary, opts} ->
          protocol? = Module.defines?(__MODULE__, {:__impl__, 1}, :def)
          mix_task? = String.starts_with?(inspect(__MODULE__), "Mix.Tasks.")

          unless protocol? or mix_task?,
            do: raise(":classify_to can only be provided in protocol implementations and mix tasks")

          if opts != [],
            do: raise("no other option is allowed with :classify_to")

          Module.register_attribute(__MODULE__, Boundary.Target, persist: true, accumulate: false)
          Module.put_attribute(__MODULE__, Boundary.Target, %{boundary: boundary, file: @env.file, line: @env.line})
      end
    end
  end

  def get(boundary) do
    case Keyword.get(boundary.__info__(:attributes), Boundary) do
      [definition] -> definition
      nil -> nil
    end
  end

  def classified_to(module) do
    case Keyword.get(module.__info__(:attributes), Boundary.Target) do
      [classify_to] -> classify_to
      nil -> nil
    end
  end

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
    |> validate(&if &1.externals_mode == :strict and &1.extra_externals != [], do: :extra_externals_in_strict_mode)
  end

  defp merge_user_opts(definition, user_opts) do
    user_opts = Map.new(user_opts)
    valid_keys = ~w/deps exports ignore? extra_externals externals_mode top_level?/a

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
      extra_externals: [],
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
