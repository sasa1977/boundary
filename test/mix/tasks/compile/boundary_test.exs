defmodule Mix.Tasks.Compile.BoundaryTest do
  use ExUnit.Case, async: true

  setup_all do
    mix!(~w/deps.get/)
    :ok
  end

  setup do
    File.rm_rf(tmp_folder())
    :ok
  end

  test "reports all warnings" do
    File.mkdir_p(tmp_folder())

    File.write!(
      Path.join(tmp_folder(), "source.ex"),
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
      """
    )

    {output, _code} = mix(~w/compile/)
    warnings = warnings(output)

    IO.inspect(warnings)

    assert Enum.member?(warnings, %{
             location: "lib/tmp/source.ex",
             warning: "Boundary1 is not included in any boundary"
           })

    assert Enum.member?(warnings, %{
             location: "/projects/me/boundaries/test_project/lib/tmp/source.ex:5",
             warning: "unknown boundary UnknownBoundary is listed as a dependency"
           })

    assert Enum.member?(warnings, %{
             location: "/projects/me/boundaries/test_project/lib/tmp/source.ex:5",
             warning: "ignored boundary Boundary4 is listed as a dependency"
           })

    assert Enum.member?(warnings, %{
             location: "lib/tmp/source.ex:7",
             warning: "forbidden call to Boundary3.fun/0",
             explanation: "(calls from Boundary2 to Boundary3 are not allowed)",
             callee: "(call originated from Boundary2)"
           })

    assert Enum.member?(warnings, %{
             location: "lib/tmp/source.ex:17",
             warning: "forbidden call to Boundary2.Internal.fun/0",
             explanation: "(module Boundary2.Internal is not exported by its owner boundary Boundary2)",
             callee: "(call originated from Boundary3)"
           })

    assert Enum.member?(warnings, %{
             warning: "dependency cycle found:",
             location: "Boundary6 -> Boundary5 -> Boundary6"
           })
  end

  defp mix!(args) do
    {output, 0} = mix(args)
    output
  end

  defp mix(args),
    do: System.cmd("mix", args, stderr_to_stdout: true, cd: project_folder())

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

  defp project_folder, do: "test_project"
  defp tmp_folder, do: Path.join(~w/test_project lib tmp/)
end
