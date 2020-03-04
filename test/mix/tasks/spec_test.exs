defmodule Mix.Tasks.Boundary.SpecTest do
  use Boundary.ProjectTestCase, async: true

  test "produces the expected output", context do
    File.write!(
      Path.join([context.project.path, "lib", "source.ex"]),
      """
      defmodule Boundary1 do
        use Boundary, deps: [Boundary2, Boundary3], exports: [Foo, Bar]

        defmodule Foo do end
        defmodule Bar do end
      end

      defmodule Boundary2 do
        use Boundary, deps: [], exports: [], extra_externals: [:logger]
      end

      defmodule Boundary3 do
        use Boundary, deps: [], exports: []
      end

      defmodule Ignored do
        use Boundary, ignore?: true
      end
      """
    )

    TestProject.compile!(context.project)

    output =
      TestProject.mix!(context.project, ~w/boundary.spec/)
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.join("\n")

    assert output ==
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
  end
end
