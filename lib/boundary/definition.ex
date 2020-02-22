defmodule Boundary.Definition do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  defmodule Error do
    defexception [:message, :file, :line]
  end

  defmacro generate(opts) do
    quote bind_quoted: [opts: opts] do
      @boundary_opts opts
      @env __ENV__
      @before_compile Boundary.Definition
    end
  end

  defmacro __before_compile__(_) do
    quote do
      case Keyword.pop(@boundary_opts, :classify_to, nil) do
        {nil, opts} ->
          Module.register_attribute(__MODULE__, Boundary, persist: true, accumulate: false)
          Module.put_attribute(__MODULE__, Boundary, Boundary.Definition.normalize(__MODULE__, opts, @env))

        {boundary, opts} ->
          unless Module.defines?(__MODULE__, {:__impl__, 1}, :def),
            do: raise(":classify_to can only be provided in protocol implementations")

          if opts != [],
            do: raise("no other option is allowed with :classify_to")

          Module.register_attribute(__MODULE__, Boundary.Target, persist: true, accumulate: false)
          Module.put_attribute(__MODULE__, Boundary.Target, %{boundary: boundary, file: @env.file, line: @env.line})
      end
    end
  end

  def spec(module_names) do
    modules = Enum.map(module_names, &%{name: &1, protocol_impl?: protocol_impl?(&1), classify_to: classify_to(&1)})
    boundaries = load_boundaries(module_names)
    %{modules: classify_modules(boundaries, modules), boundaries: boundaries}
  end

  defp protocol_impl?(module) do
    # Not sure why, but sometimes the protocol implementation isn't loaded.
    Code.ensure_loaded(module)

    function_exported?(module, :__impl__, 1)
  end

  defp classify_to(module) do
    case Keyword.get(module.__info__(:attributes), Boundary.Target) do
      [classify_to] -> classify_to
      nil -> nil
    end
  end

  @doc false
  def classify_modules(boundaries, modules) do
    boundaries_search_space =
      boundaries
      |> Map.keys()
      |> Enum.sort(&>=/2)
      |> Enum.map(&%{name: &1, parts: Module.split(&1)})

    Enum.reduce(
      modules,
      %{classified: %{}, unclassified: MapSet.new()},
      fn module, modules ->
        case target_boundary(module, boundaries_search_space, boundaries) do
          nil -> update_in(modules.unclassified, &MapSet.put(&1, Map.take(module, ~w/name protocol_impl?/a)))
          boundary -> put_in(modules.classified[module.name], boundary)
        end
      end
    )
  end

  defp target_boundary(module, boundaries_search_space, boundaries) do
    case module.classify_to do
      nil ->
        parts = Module.split(module.name)

        with boundary when not is_nil(boundary) <-
               Enum.find(boundaries_search_space, &List.starts_with?(parts, &1.parts)),
             do: boundary.name

      classify_to ->
        unless Map.has_key?(boundaries, classify_to.boundary) do
          message = "invalid boundary #{classify_to.boundary}"
          raise Error, message: message, file: classify_to.file, line: classify_to.line
        end

        classify_to.boundary
    end
  end

  defp load_boundaries(modules) do
    modules
    |> Stream.map(&{&1, get(&1)})
    |> Enum.reject(&match?({_module, nil}, &1))
    |> Map.new()
  end

  defp get(boundary) do
    case Keyword.get(boundary.__info__(:attributes), Boundary) do
      [definition] -> definition
      nil -> nil
    end
  end

  def normalize(boundary, definition, env) do
    defaults()
    |> Map.merge(Map.new(definition))
    |> validate!()
    |> expand_exports(boundary)
    |> Map.merge(%{file: env.file, line: env.line})
  end

  defp defaults, do: %{deps: [], exports: [], ignore?: false}

  defp validate!(definition) do
    valid_keys = ~w/deps exports ignore?/a

    with [_ | _] = invalid_options <- definition |> Map.keys() |> Enum.reject(&(&1 in valid_keys)) do
      error = "Invalid options: #{invalid_options |> Stream.map(&inspect/1) |> Enum.join(", ")}"
      raise ArgumentError, error
    end

    if definition.ignore? do
      if definition.deps != [], do: raise(ArgumentError, message: "deps are not allowed in ignored boundaries")
      if definition.exports != [], do: raise(ArgumentError, message: "exports are not allowed in ignored boundaries")
    end

    definition
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
end
