defmodule Mix.Tasks.Compile.BoundaryTest do
  use Boundary.ProjectTestCaseTemplate, async: true

  test "reports all warnings", context do
    File.write!(
      Path.join([context.project.path, "lib", "source.ex"]),
      """
      defmodule Boundary1 do
      end

      defmodule Boundary2 do
        use Boundary, deps: [Boundary4, UnknownBoundary], exports: []

        def fun(), do: Boundary3.fun()

        defmodule Internal do
          def fun(), do: :ok
        end
      end

      defmodule Boundary3 do
        use Boundary, deps: [Boundary2], exports: []

        def fun(), do: Boundary2.Internal.fun()
      end

      defmodule Boundary4 do
        use Boundary, ignore?: true
      end

      defmodule Boundary5 do
        use Boundary, deps: [Boundary6], exports: []

        def fun(), do: :ok
      end

      defmodule Boundary6 do
        use Boundary, deps: [Boundary5], exports: []

        def fun(), do: :ok
      end

      defmodule Boundary7 do
        use Boundary, deps: [], extra_externals: [:logger]
        require Logger

        def fun(), do: Logger.info("foo")
      end
      """
    )

    output = mix!(context.project.path, ~w/compile/)
    warnings = warnings(output)

    assert Enum.member?(warnings, %{
             location: "lib/source.ex",
             warning: "Boundary1 is not included in any boundary"
           })

    assert Enum.member?(warnings, %{
             location: "lib/source.ex:5",
             warning: "unknown boundary UnknownBoundary is listed as a dependency"
           })

    assert Enum.member?(warnings, %{
             location: "lib/source.ex:5",
             warning: "ignored boundary Boundary4 is listed as a dependency"
           })

    assert Enum.member?(warnings, %{
             location: "lib/source.ex:7",
             warning: "forbidden call to Boundary3.fun/0",
             explanation: "(calls from Boundary2 to Boundary3 are not allowed)",
             callee: "(call originated from Boundary2)"
           })

    assert Enum.member?(warnings, %{
             location: "lib/source.ex:17",
             warning: "forbidden call to Boundary2.Internal.fun/0",
             explanation: "(module Boundary2.Internal is not exported by its owner boundary Boundary2)",
             callee: "(call originated from Boundary3)"
           })

    assert Enum.member?(warnings, %{
             warning: "dependency cycle found:",
             location: "Boundary6 -> Boundary5 -> Boundary6"
           })

    assert Enum.member?(warnings, %{
             location: "lib/source.ex:40",
             warning: "forbidden call to Logger.info/1",
             explanation: "(calls from Boundary7 to Logger are not allowed)",
             callee: "(call originated from Boundary7)"
           })
  end

  test "reports warnings if recompilation doesn't happen", context do
    File.write!(
      Path.join([context.project.path, "lib", "boundary1.ex"]),
      """
      defmodule Boundary1 do
        use Boundary, deps: [], exports: []
        def fun(), do: Boundary2.fun()
      end
      """
    )

    File.write!(
      Path.join([context.project.path, "lib", "boundary2.ex"]),
      """
      defmodule Boundary2 do
        use Boundary, deps: [], exports: []
        def fun(), do: :ok
      end
      """
    )

    # We're deliberatly compiling twice. The first compilation will collect data through the tracer, while the second
    # compilation will actually not compile anything (since there are no code changes). By doing this, we want to verify
    # that tracing data has been preserved, and all the warnings will still be reported.
    mix!(context.project.path, ~w/compile/)
    output = mix!(context.project.path, ~w/compile/)

    warnings = warnings(output)

    assert Enum.member?(warnings, %{
             location: "lib/boundary1.ex:3",
             warning: "forbidden call to Boundary2.fun/0",
             explanation: "(calls from Boundary1 to Boundary2 are not allowed)",
             callee: "(call originated from Boundary1)"
           })
  end

  test "records new warnings on code change", context do
    File.write!(
      Path.join([context.project.path, "lib", "boundary1.ex"]),
      """
      defmodule Boundary1 do
        use Boundary, deps: [], exports: []
        def fun(), do: Boundary2.fun()
      end
      """
    )

    File.write!(
      Path.join([context.project.path, "lib", "boundary2.ex"]),
      """
      defmodule Boundary2 do
        use Boundary, deps: [], exports: []
        def fun(), do: :ok
        def another_fun(), do: :ok
      end
      """
    )

    mix!(context.project.path, ~w/compile/)

    File.write!(
      Path.join([context.project.path, "lib", "boundary1.ex"]),
      """
      defmodule Boundary1 do
        use Boundary, deps: [], exports: []
        def fun(), do: Boundary2.another_fun()
      end
      """
    )

    output = mix!(context.project.path, ~w/compile/)

    warnings = warnings(output)

    assert Enum.member?(warnings, %{
             location: "lib/boundary1.ex:3",
             warning: "forbidden call to Boundary2.another_fun/0",
             explanation: "(calls from Boundary1 to Boundary2 are not allowed)",
             callee: "(call originated from Boundary1)"
           })
  end

  test "external which defines boundaries", context do
    lib = new_project()

    File.write!(
      Path.join([lib.path, "lib", "code.ex"]),
      """
      defmodule Boundary1 do
        use Boundary, deps: [], exports: []

        def fun(), do: :ok

        defmodule Submodule do
          def fun(), do: :ok
        end
      end

      defmodule Boundary2 do
        use Boundary, deps: [], exports: []

        def fun(), do: :ok
      end
      """
    )

    File.write!(
      Path.join(context.project.path, "mix.exs"),
      mix_exs(context.project.name, deps: [{:"#{lib.name}", path: "#{Path.absname(lib.path)}"}])
    )

    File.write!(
      Path.join([context.project.path, "lib", "code.ex"]),
      """
      defmodule Client1 do
        use Boundary, deps: [Boundary1.{Submodule, Submodule2}]
      end

      defmodule Client2 do
        use Boundary, deps: [Boundary1]

        def fun1(), do: Boundary1.Submodule.fun()
        def fun2(), do: Boundary2.fun()
      end
      """
    )

    output = mix!(context.project.path, ~w/compile/)
    warnings = warnings(output)

    assert Enum.member?(warnings, %{
             location: "lib/code.ex:2",
             warning: "unknown boundary Boundary1.Submodule is listed as a dependency"
           })

    assert Enum.member?(warnings, %{
             location: "lib/code.ex:2",
             warning: "unknown boundary Boundary1.Submodule2 is listed as a dependency"
           })

    assert Enum.member?(warnings, %{
             location: "lib/code.ex:8",
             warning: "forbidden call to Boundary1.Submodule.fun/0",
             explanation: "(module Boundary1.Submodule is not exported by its owner boundary Boundary1)",
             callee: "(call originated from Client2)"
           })

    assert Enum.member?(warnings, %{
             location: "lib/code.ex:9",
             warning: "forbidden call to Boundary2.fun/0",
             explanation: "(calls from Client2 to Boundary2 are not allowed)",
             callee: "(call originated from Client2)"
           })
  end

  test "external with implicit boundaries", context do
    lib = new_project(mix_opts: [deps: [], compilers: []])

    File.write!(
      Path.join([lib.path, "lib", "code.ex"]),
      """
      defmodule Boundary1 do
        def fun(), do: :ok

        defmodule Boundary2 do
          def fun(), do: :ok

          defmodule Boundary3 do
            def fun(), do: :ok
          end
        end
      end

      defmodule Boundary4 do
        def fun(), do: :ok
      end
      """
    )

    File.write!(
      Path.join(context.project.path, "mix.exs"),
      mix_exs(context.project.name,
        deps: [
          {:boundary, path: "../.."},
          {:"#{lib.name}", path: "#{Path.absname(lib.path)}"}
        ],
        compilers: [:boundary]
      )
    )

    File.write!(
      Path.join([context.project.path, "lib", "code.ex"]),
      """
      defmodule Client1 do
        use Boundary, deps: [Boundary1]

        def fun1(), do: Boundary1.Boundary2.Boundary3.fun()
        def fun2(), do: Boundary4.fun()
      end

      defmodule Client2 do
        use Boundary, deps: [Boundary1.Boundary2.Boundary3]

        def fun(), do: Boundary1.fun()
      end
      """
    )

    output = mix!(context.project.path, ~w/compile/)
    warnings = warnings(output)

    assert Enum.member?(warnings, %{
             location: "lib/code.ex:4",
             warning: "forbidden call to Boundary1.Boundary2.Boundary3.fun/0",
             callee: "(call originated from Client1)",
             explanation: "(calls from Client1 to Boundary1.Boundary2.Boundary3 are not allowed)"
           })

    assert Enum.member?(warnings, %{
             location: "lib/code.ex:5",
             warning: "forbidden call to Boundary4.fun/0",
             callee: "(call originated from Client1)",
             explanation: "(calls from Client1 to Boundary4 are not allowed)"
           })

    assert Enum.member?(warnings, %{
             location: "lib/code.ex:11",
             warning: "forbidden call to Boundary1.fun/0",
             callee: "(call originated from Client2)",
             explanation: "(calls from Client2 to Boundary1 are not allowed)"
           })
  end

  test "global externals", context do
    lib = new_project()

    File.write!(
      Path.join([lib.path, "lib", "code.ex"]),
      """
      defmodule Boundary1 do
        use Boundary, deps: [], exports: []

        def fun(), do: :ok
      end
      """
    )

    File.write!(
      Path.join(context.project.path, "mix.exs"),
      mix_exs(context.project.name,
        project_opts: [boundary: [externals_mode: :strict]],
        deps: [{:"#{lib.name}", path: "#{Path.absname(lib.path)}"}]
      )
    )

    File.write!(
      Path.join([context.project.path, "lib", "code.ex"]),
      """
      defmodule Client1 do
        use Boundary, deps: []

        def fun(), do: Boundary1.fun()
      end
      """
    )

    output = mix!(context.project.path, ~w/compile/)
    warnings = warnings(output)

    assert Enum.member?(warnings, %{
             location: "lib/code.ex:4",
             warning: "forbidden call to Boundary1.fun/0",
             callee: "(call originated from Client1)",
             explanation: "(calls from Client1 to Boundary1 are not allowed)"
           })
  end

  defp warnings(output) do
    output
    |> String.split(~r/\n|\r/)
    |> Stream.map(&String.trim/1)
    |> Stream.chunk_every(4, 1)
    |> Stream.filter(&match?("warning: " <> _, hd(&1)))
    |> Enum.map(fn ["warning: " <> warning, line_2, line_3, line_4] ->
      if(String.starts_with?(line_2, "("),
        do: %{explanation: line_2, callee: line_3, location: line_4},
        else: %{location: line_2}
      )
      |> Map.put(:warning, String.trim(warning))
    end)
  end
end
