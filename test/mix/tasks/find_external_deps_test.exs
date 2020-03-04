defmodule Mix.Tasks.Boundary.FindExternalDepsTest do
  use Boundary.ProjectTestCase, async: true

  test "produces the expected output", context do
    File.write!(
      Path.join([context.project.path, "lib", "source.ex"]),
      """
      defmodule Boundary1 do
        use Boundary

        def fun() do
          require Logger
          Logger.info("foo")
        end
      end

      defmodule Boundary2 do
        use Boundary
      end
      """
    )

    TestProject.compile!(context.project)

    output =
      TestProject.mix!(context.project, ~w/boundary.find_external_deps/)
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.join("\n")

    assert output ==
             """

             #{[IO.ANSI.bright()]}Boundary1#{IO.ANSI.reset()}:
               :logger

             #{[IO.ANSI.bright()]}Boundary2#{IO.ANSI.reset()} - no external deps

             """
  end
end
