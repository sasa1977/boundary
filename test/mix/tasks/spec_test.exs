defmodule Mix.Tasks.Boundary.SpecTest do
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
          use Boundary, deps: [Boundary2, Boundary3], exports: [Foo, Bar]

          defmodule Foo do end
          defmodule Bar do end
        end

        defmodule Boundary2 do
          use Boundary, deps: [], exports: [], check_apps: [:logger]
        end

        defmodule Boundary3 do
          use Boundary, deps: [], exports: []
        end

        defmodule Ignored do
          use Boundary, ignore?: true
        end
        """
      )

      output =
        TestProject.run_task("boundary.spec").output
        |> String.split("\n")
        |> Enum.map(&String.trim_trailing/1)
        |> Enum.join("\n")

      assert output =~
               """
               Boundary1
                 deps: Boundary2, Boundary3
                 exports: Bar, Foo
                 externals:

               Boundary2
                 deps:
                 exports:
                 externals: :logger

               Boundary3
                 deps:
                 exports:
                 externals:

               Ignored (ignored)
               """
    end)
  end
end
