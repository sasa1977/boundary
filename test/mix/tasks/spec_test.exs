defmodule Mix.Tasks.Boundary.SpecTest do
  use Boundary.ProjectTestCaseTemplate, async: true

  test "produces the expected output", context do
    File.write!(
      Path.join([context.project_path, "lib", "source.ex"]),
      """
      defmodule Boundary1 do
        use Boundary, deps: [Boundary2, Boundary3], exports: [Foo, Bar]

        defmodule Foo do end
        defmodule Bar do end
      end

      defmodule Boundary2 do
        use Boundary, deps: [], exports: [], externals: [logger: {:only, [Logger]}]
      end

      defmodule Boundary3 do
        use Boundary, deps: [], exports: []
      end

      defmodule Ignored do
        use Boundary, ignore?: true
      end
      """
    )

    mix!(context.project_path, ~w/compile/)

    output =
      mix!(context.project_path, ~w/boundary.spec/)
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.join("\n")

    assert output ==
             """

             Boundary1
               deps: Boundary2, Boundary3
               exports: Bar, Foo
               externals: unrestricted

             Boundary2
               deps:
               exports:
               externals:
                 logger: only Elixir.Logger

             Boundary3
               deps:
               exports:
               externals: unrestricted

             Ignored (ignored)

             """
  end
end
