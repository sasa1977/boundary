defmodule Boundary do
  @moduledoc false

  def application() do
    calls =
      Mix.Tasks.Xref.calls()
      |> Stream.map(fn %{callee: {mod, _fun, _arg}} = entry -> Map.put(entry, :callee_module, mod) end)
      |> Enum.reject(&(&1.callee_module == &1.caller_module))

    modules =
      calls
      |> Stream.map(& &1.caller_module)
      |> MapSet.new()

    %{modules: modules, boundaries: load_boundaries!(), calls: calls}
  end

  defp load_boundaries!() do
    with {:ok, config_string} <- config_string(),
         {:ok, boundaries} <- from_string(config_string) do
      boundaries
    else
      {:error, reason} -> Mix.raise(reason)
    end
  end

  defp config_string() do
    with {:error, _reason} <- File.read("boundaries.exs"),
         do: {:error, "could not open `boundaries.exs`"}
  end

  @doc false
  def from_string(string) do
    {boundaries, _} = Code.eval_string(string)

    if is_list(boundaries),
      do: {:ok, Enum.map(boundaries, &normalize_boundary/1)},
      else: {:error, "boundaries must be provided as a list"}
  end

  defp normalize_boundary(mod) when is_atom(mod), do: {mod, defaults(mod)}
  defp normalize_boundary({mod, opts}), do: {mod, Map.merge(defaults(mod), normalize_opts(mod, opts))}
  defp normalize_boundary(other), do: Mix.raise("Invalid boundary definition: #{inspect(other)}")

  defp normalize_opts(mod, opts) do
    opts
    |> Map.new()
    |> Map.take([:deps, :exports])
    |> update_in(
      [:exports],
      fn
        nil -> []
        exports -> Enum.map(exports, &Module.concat(mod, &1))
      end
    )
  end

  defp defaults(mod), do: %{deps: [], exports: [mod]}
end
