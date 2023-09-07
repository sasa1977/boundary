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
      Boundary.Mix.View.build()
      |> Boundary.all()
      |> Enum.sort_by(& &1.name)
      |> Stream.map(&boundary_info/1)
      |> Enum.join("\n")

    Mix.shell().info("\n" <> msg)
  end

  defp boundary_info(boundary) do
    """
    #{inspect(boundary.name)}
      exports: #{exports(boundary)}
      deps: #{deps(boundary)}
    """
  end

  defp deps(%{check: %{out: false}}), do: "not checked"

  defp deps(boundary) do
    boundary.deps
    |> Enum.sort()
    |> Stream.map(fn
      {dep, :runtime} -> inspect(dep)
      {dep, :compile} -> "#{inspect(dep)} (compile only)"
    end)
    |> Enum.join(", ")
  end

  defp exports(%{check: %{in: false}}), do: "not checked"

  defp exports(boundary) do
    boundary.exports
    |> Stream.map(&inspect/1)
    |> Enum.sort()
    |> Enum.join(", ")
    |> String.replace("#{inspect(boundary.name)}.", "")
  end
end
