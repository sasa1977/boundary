defmodule Mix.Tasks.Boundary.Spec do
  @shortdoc "Prints information about all boundaries in the application."
  @moduledoc "Prints information about all boundaries in the application."

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  use Boundary, classify_to: Boundary.Mix
  use Mix.Task

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("compile")
    Boundary.Mix.load_app()

    msg =
      Boundary.Mix.app_name()
      |> Boundary.view()
      |> Boundary.all()
      |> Stream.filter(&(&1.app == Boundary.Mix.app_name()))
      |> Enum.sort_by(& &1.name)
      |> Stream.map(&boundary_info/1)
      |> Enum.join("\n")

    Mix.shell().info("\n" <> msg)
  end

  defp boundary_info(%{ignore?: false} = boundary) do
    """
    #{inspect(boundary.name)}
      deps: #{deps(boundary)}
      exports: #{exports(boundary)}
      externals: #{boundary.externals |> Enum.map(&inspect/1) |> Enum.join(", ")}
    """
  end

  defp boundary_info(%{ignore?: true} = boundary) do
    """
    #{inspect(boundary.name)} (ignored)
    """
  end

  defp deps(boundary) do
    boundary.deps
    |> Enum.sort()
    |> Stream.map(fn
      {dep, :runtime} -> inspect(dep)
      {dep, :compile} -> "#{inspect(dep)} (compile only)"
    end)
    |> Enum.join(", ")
  end

  defp exports(boundary) do
    boundary.exports
    |> Stream.map(&normalize_export(boundary.name, &1))
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
end
