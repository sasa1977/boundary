defmodule Mix.Tasks.Boundary.Spec do
  @shortdoc "Prints information about all boundaries in the application."
  @moduledoc "Prints information about all boundaries in the application."

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  use Boundary, deps: [Boundary]
  use Mix.Task

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("compile")
    Boundary.Mix.load_app()

    boundary_spec = Boundary.spec(Boundary.Mix.app_name())

    msg =
      boundary_spec.boundaries
      |> Enum.sort()
      |> Stream.map(&boundary_info/1)
      |> Enum.join("\n")

    Mix.shell().info("\n" <> msg)
  end

  defp boundary_info({boundary_name, %{ignore?: false} = spec}) do
    """
    #{inspect(boundary_name)}
      deps: #{spec.deps |> Enum.sort() |> Stream.map(&inspect/1) |> Enum.join(", ")}
      exports: #{exports(boundary_name, spec)}
      externals: #{externals(spec)}
    """
  end

  defp boundary_info({boundary_name, %{ignore?: true}}) do
    """
    #{inspect(boundary_name)} (ignored)
    """
  end

  defp exports(boundary_name, spec) do
    spec.exports
    |> Stream.map(&normalize_export(boundary_name, &1))
    |> Stream.reject(&is_nil/1)
    |> Enum.sort()
    |> Enum.join(", ")
  end

  defp normalize_export(boundary_name, boundary_name), do: nil

  defp normalize_export(boundary_name, exported_module) do
    parts = relative_to(Module.split(exported_module), Module.split(boundary_name))
    inspect(Module.concat(parts))
  end

  defp relative_to([head | tail1], [head | tail2]), do: relative_to(tail1, tail2)
  defp relative_to(list, _), do: list

  defp externals(%{externals: externals}) when map_size(externals) == 0, do: "unrestricted"

  defp externals(%{externals: externals}) do
    "\n" <>
      (externals
       |> Enum.map(fn {app, {type, modules}} -> "    #{app}: #{type} #{modules |> Enum.sort() |> Enum.join(", ")}" end)
       |> Enum.join("\n"))
  end
end
