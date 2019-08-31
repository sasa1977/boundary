defmodule Boundary.Definition do
  @moduledoc false

  defmacro generate(opts) do
    quote bind_quoted: [opts: opts] do
      Module.register_attribute(__MODULE__, Boundary, persist: true, accumulate: false)
      Module.put_attribute(__MODULE__, Boundary, Boundary.Definition.normalize(__MODULE__, opts))
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

  def normalize(boundary, definition), do: Map.merge(defaults(boundary), normalize_opts(boundary, definition))

  defp defaults(boundary), do: %{deps: [], exports: [boundary]}

  defp normalize_opts(boundary, definition) do
    definition
    |> Map.new()
    |> Map.take([:deps, :exports])
    |> update_in(
      [:exports],
      fn
        nil -> [boundary]
        exports -> [boundary | Enum.map(exports, &Module.concat(boundary, &1))]
      end
    )
  end
end
