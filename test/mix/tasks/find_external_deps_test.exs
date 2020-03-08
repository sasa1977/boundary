defmodule Mix.Tasks.Boundary.FindExternalDepsTest do
  use ExUnit.Case, async: false
  alias Boundary.TestProject

  test "produces the expected output" do
    Mix.shell(Mix.Shell.Process)
    Logger.disable(self())

    TestProject.in_project(fn project ->
      File.write!(
        Path.join([project.path, "lib", "source.ex"]),
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

      output =
        TestProject.run_task("boundary.find_external_deps").output
        |> String.split("\n")
        |> Enum.map(&String.trim_trailing/1)
        |> Enum.join("\n")

      assert output =~
               """
               #{[IO.ANSI.bright()]}Boundary1#{IO.ANSI.reset()}:
                 :logger

               #{[IO.ANSI.bright()]}Boundary2#{IO.ANSI.reset()} - no external deps
               """
    end)
  end
end
