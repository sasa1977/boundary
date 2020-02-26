defmodule Mix.Tasks.Boundary.FindExternalDeps do
  @shortdoc "Prints information about external dependencies of all application boundaries."

  @moduledoc """
  Prints information about external dependencies of all application boundaries.

  Note that `:stdlib`, `:kernel', `:elixir`, and `:boundary` will not be included in the output.
  """

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  use Boundary, classify_to: Boundary.Mix
  use Mix.Task
  alias Boundary.Mix.Xref

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("compile")
    Boundary.Mix.load_app()

    message =
      Boundary.Mix.app_name()
      |> Boundary.spec()
      |> find_external_deps()
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

  defp find_external_deps(boundary_spec) do
    Xref.start_link()

    for call <- Xref.calls(),
        boundary = Boundary.get(boundary_spec, call.caller_module),
        not boundary.ignore?,
        app = Boundary.app(boundary_spec, call.callee_module),
        app not in [:boundary, Boundary.Mix.app_name(), nil],
        reduce: Enum.into(Boundary.all_names(boundary_spec), %{}, &{&1, MapSet.new()}) do
      acc ->
        Map.update(acc, boundary.name, MapSet.new([app]), &MapSet.put(&1, app))
    end
  end
end
