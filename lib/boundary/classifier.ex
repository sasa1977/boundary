defmodule Boundary.Classifier do
  @moduledoc false

  @type t :: %{boundaries: %{Boundary.name() => Boundary.t()}, modules: %{module() => Boundary.name()}}

  @spec new :: t
  def new, do: %{boundaries: %{}, modules: %{}}

  @spec classify(t, [module], [Boundary.t()]) :: t
  def classify(classifier, modules, boundaries) do
    trie = build_trie(boundaries)

    boundaries = Enum.reduce(boundaries, classifier.boundaries, &Map.put_new(&2, &1.name, &1))
    classifier = %{classifier | boundaries: boundaries}

    for module <- modules,
        boundary = find_boundary(trie, module),
        reduce: classifier do
      classifier -> Map.update!(classifier, :modules, &Map.put(&1, module, boundary.name))
    end
  end

  defp build_trie(boundaries), do: Enum.reduce(boundaries, new_trie(), &add_boundary(&2, &1))

  defp new_trie, do: %{boundary: nil, children: %{}}

  defp find_boundary(trie, module) when is_atom(module) do
    case Boundary.Definition.classified_to(module) do
      nil ->
        find_boundary(trie, Module.split(module))

      classified_to ->
        boundary = find_boundary(trie, classified_to.boundary)

        unless boundary do
          message = "invalid boundary #{inspect(classified_to.boundary)}"
          raise Boundary.Error, message: message, file: classified_to.file, line: classified_to.line
        end

        boundary
    end
  end

  defp find_boundary(_trie, []), do: nil

  defp find_boundary(trie, [part | rest]) do
    case Map.fetch(trie.children, part) do
      {:ok, child_trie} -> find_boundary(child_trie, rest) || child_trie.boundary
      :error -> nil
    end
  end

  defp add_boundary(trie, boundary),
    do: add_boundary(trie, Module.split(boundary.name), boundary)

  defp add_boundary(trie, [], boundary), do: %{trie | boundary: boundary}

  defp add_boundary(trie, [part | rest], boundary) do
    Map.update!(
      trie,
      :children,
      fn children ->
        children
        |> Map.put_new_lazy(part, &new_trie/0)
        |> Map.update!(part, &add_boundary(&1, rest, boundary))
      end
    )
  end
end
