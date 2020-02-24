defmodule Mix.Tasks.Boundary.FindExternalDeps do
  @shortdoc "Prints information about external dependencies of all application boundaries."

  @moduledoc """
  Prints information about external dependencies of all application boundaries.

  Note that `:stdlib`, `:kernel', `:elixir`, and `:boundary` will not be included in the output.
  """

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  use Boundary, deps: [Boundary]
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
        boundary = Map.get(boundary_spec.modules.classified, call.caller_module),
        not is_nil(boundary),
        not Map.fetch!(boundary_spec.boundaries, boundary).ignore?,
        app = Map.get(boundary_spec.module_to_app, call.callee_module),
        app not in [:boundary, Boundary.Mix.app_name(), nil],
        reduce: Enum.into(Map.keys(boundary_spec.boundaries), %{}, &{&1, MapSet.new()}) do
      acc ->
        Map.update(acc, boundary, MapSet.new([app]), &MapSet.put(&1, app))
    end
  end
end
