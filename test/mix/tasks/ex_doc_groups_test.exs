defmodule Mix.Tasks.Boundary.ExDocGroupsTest do
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
          use Boundary, deps: [], exports: []

          defmodule Foo do
            defmodule Bar do end
          end
          defmodule Bar do end
          defmodule Baz do end
        end

        defmodule Boundary2 do
          use Boundary, deps: [], exports: []

          defmodule Foo do end
        end

        defmodule Boundary3 do
          use Boundary, deps: [], exports: []

          defmodule Foo do end
          defmodule Bar do end
        end

        defmodule Boundary3.InnerBoundary do
          use Boundary, deps: [], exports: []

          defmodule Foo do end
        end

        defmodule Ignored do
          use Boundary, ignore?: true
        end
        """
      )

      assert TestProject.run_task("boundary.ex_doc_groups").output =~ "* creating boundary.exs"

      {groups, _} = Code.eval_file("boundary.exs")

      assert [
                "Boundary1": [Boundary1, Boundary1.Bar, Boundary1.Baz, Boundary1.Foo, Boundary1.Foo.Bar],
                "Boundary2": [Boundary2, Boundary2.Foo],
                "Boundary3": [Boundary3, Boundary3.Bar, Boundary3.Foo],
                "Boundary3.InnerBoundary": [Boundary3.InnerBoundary, Boundary3.InnerBoundary.Foo]
              ] = groups
    end)
  end
end
