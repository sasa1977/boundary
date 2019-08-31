defmodule Boundary.Definition do
  @moduledoc false
  # credo:disable-for-this-file Credo.Check.Readability.Specs

  defmacro generate(opts) do
    quote bind_quoted: [opts: opts] do
      Module.register_attribute(__MODULE__, Boundary, persist: true, accumulate: false)
      Module.put_attribute(__MODULE__, Boundary, Boundary.Definition.normalize(__MODULE__, opts, __ENV__))
    end
  end

  def boundaries(modules) do
    modules = MapSet.new(modules)
    boundaries = load_boundaries(modules)
    %{modules: classify_modules(boundaries, modules), boundaries: boundaries}
  end

  @doc false
  def classify_modules(boundaries, modules) do
    boundaries_search_space =
      boundaries
      |> Map.keys()
      |> Enum.sort(&>=/2)
      |> Enum.map(&%{name: &1, parts: Module.split(&1)})

    {classified, unclassified} =
      Enum.reduce(
        modules,
        {%{}, MapSet.new()},
        fn module, {classified, unclassified} ->
          parts = Module.split(module)

          case Enum.find(boundaries_search_space, &List.starts_with?(parts, &1.parts)) do
            nil -> {classified, MapSet.put(unclassified, module)}
            boundary -> {Map.put(classified, module, boundary.name), unclassified}
          end
        end
      )

    %{classified: classified, unclassified: MapSet.to_list(unclassified)}
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
