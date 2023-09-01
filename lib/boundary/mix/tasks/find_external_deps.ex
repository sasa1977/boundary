defmodule Mix.Tasks.Boundary.FindExternalDeps do
  @shortdoc "Prints information about external dependencies of all application boundaries."

  @moduledoc """
  Prints information about external dependencies of all application boundaries.

  Note that `:stdlib`, `:kernel`, `:elixir`, and `:boundary` will not be included in the output.
  """

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  use Boundary, classify_to: Boundary.Mix
  use Mix.Task

  alias Boundary.Mix.CompilerState

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("compile")
    Boundary.Mix.load_app()

    view = Boundary.Mix.View.build()

    message =
      view
      |> find_external_deps()
      |> Enum.filter(fn {name, _external_deps} -> Boundary.fetch!(view, name).app == Boundary.Mix.app_name() end)
      |> Enum.sort()
      |> Stream.map(&message/1)
      |> Enum.join("\n")

    Mix.shell().info("\n" <> message)
  end

  defp message({boundary_name, external_deps}) do
    header = "#{[IO.ANSI.bright()]}#{inspect(boundary_name)}#{IO.ANSI.reset()}"

    if Enum.empty?(external_deps) do
      header <> " - no external deps\n"
    else
      """
      #{header}:
        #{external_deps |> Enum.sort() |> Stream.map(&inspect/1) |> Enum.join(", ")}
      """
    end
  end

  defp find_external_deps(boundary_view) do
    CompilerState.start_link()

    for reference <- CompilerState.references(),
        boundary = Boundary.for_module(boundary_view, reference.from),
        boundary.check.out,
        app = Boundary.app(boundary_view, reference.to),
        app not in [:boundary, Boundary.Mix.app_name(), nil],
        reduce: Enum.into(Boundary.all(boundary_view), %{}, &{&1.name, MapSet.new()}) do
      acc ->
        Map.update(acc, boundary.name, MapSet.new([app]), &MapSet.put(&1, app))
    end
  end
end
