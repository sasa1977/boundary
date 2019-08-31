defmodule Boundary.Definition do
  @moduledoc false

  defmacro generate(opts) do
    quote bind_quoted: [opts: opts] do
      Module.register_attribute(__MODULE__, Boundary, persist: true, accumulate: false)
      Module.put_attribute(__MODULE__, Boundary, Boundary.Definition.normalize(__MODULE__, opts))
    end
  end

  def get(boundary) do
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
