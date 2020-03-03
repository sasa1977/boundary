defmodule Boundary.Mix do
  @moduledoc false

  use Boundary, deps: [Boundary]

  @spec app_name :: atom
  def app_name, do: Keyword.fetch!(Mix.Project.config(), :app)

  @spec load_app :: :ok
  def load_app do
    load_app_recursive(app_name())
    load_compile_time_deps()
  end

  defp load_app_recursive(app_name, visited \\ MapSet.new()) do
    if MapSet.member?(visited, app_name) do
      visited
    else
      visited = MapSet.put(visited, app_name)

      visited =
        if Application.load(app_name) in [:ok, {:error, {:already_loaded, app_name}}] do
          Application.spec(app_name, :applications)
          |> Stream.concat(Application.spec(app_name, :included_applications))
          |> Enum.reduce(visited, &load_app_recursive/2)
        else
          visited
        end

      visited
    end
  end

  defp load_compile_time_deps do
    Mix.Project.config()
    |> Keyword.get(:deps, [])
    |> Stream.filter(fn
      spec ->
        spec
        |> Tuple.to_list()
        |> Stream.filter(&is_list/1)
        |> Enum.any?(&(Keyword.get(&1, :runtime) == false))
    end)
    |> Stream.map(fn spec -> elem(spec, 0) end)
    |> Enum.each(&load_app_recursive/1)
  end
end
