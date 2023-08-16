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
          use Boundary, deps: [Boundary2], exports: [Foo, Bar]

          defmodule Foo do end
          defmodule Bar do end
        end

        defmodule Boundary2 do
          use Boundary, deps: [], exports: [], check: [apps: [:logger]]
        end

        defmodule Ignored do
          use Boundary, check: [out: false, in: false]
        end
        """
      )

      output =
        TestProject.run_task("boundary.spec").output
        |> String.split("\n")
        |> Enum.map_join("\n", &String.trim_trailing/1)

      assert output =~
               """
               Boundary1
                 exports: Bar, Foo
                 deps: Boundary2

               Boundary2
                 exports:
                 deps:

               Ignored
                 exports: not checked
                 deps: not checked
               """
    end)
  end
end
