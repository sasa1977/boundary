defmodule Boundary.Definition do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  defmacro generate(opts) do
    quote bind_quoted: [opts: opts, app: Keyword.fetch!(Mix.Project.config(), :app)] do
      @boundary_opts opts
      @env __ENV__
      @app app

      # Definition will be injected in before compile, because we need to check if this module is
      # a protocol, which we can only do right before the module is about to be compiled.
      @before_compile Boundary.Definition
    end
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
    |> normalize!()
    |> expand_exports(boundary)
    |> normalize_deps()
    |> Map.merge(%{file: env.file, line: env.line, app: app})
  end

  defp normalize!(definition) do
    definition = Map.new(definition)

    valid_keys = ~w/deps exports ignore? extra_externals externals_mode/a

    with [_ | _] = invalid_options <- definition |> Map.keys() |> Enum.reject(&(&1 in valid_keys)) do
      error = "Invalid options: #{invalid_options |> Stream.map(&inspect/1) |> Enum.join(", ")}"
      raise ArgumentError, error
    end

    definition = Map.merge(defaults(), definition)

    if definition.ignore? == true do
      if definition.deps != [], do: raise(ArgumentError, message: "deps are not allowed in ignored boundaries")
      if definition.exports != [], do: raise(ArgumentError, message: "exports are not allowed in ignored boundaries")
    end

    if definition.externals_mode not in ~w/strict relaxed/a,
      do: raise(ArgumentError, message: "externals_mode must be :strict or :relaxed ")

    if definition.externals_mode == :strict and definition.extra_externals != [],
      do: raise(ArgumentError, message: "extra externals can't be provided in strict mode")

    definition
  end

  defp defaults do
    %{
      deps: [],
      exports: [],
      ignore?: false,
      externals: [],
      extra_externals: [],
      externals_mode: Mix.Project.config() |> Keyword.get(:boundary, []) |> Keyword.get(:externals_mode, :relaxed)
    }
  end

  defp expand_exports(definition, boundary) do
    with %{ignore?: false} <- definition do
      update_in(
        definition.exports,
        fn exports ->
          expanded_aliases = Enum.map(exports, &Module.concat(boundary, &1))
          [boundary | expanded_aliases]
        end
      )
    end
  end

  defp normalize_deps(definition) do
    with %{ignore?: false} <- definition do
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
  end
end
