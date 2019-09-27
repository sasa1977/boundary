defmodule Boundary.IntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  setup_all do
    mix!("my_system", ~w/deps.get/)
    mix!("my_system", ~w/compile/)
    :ok
  end

  test "reports expected warnings" do
    {output, _code} = mix("my_system", ~w/compile/)

    warnings = warnings(output)
    assert length(warnings) == 2

    assert Enum.member?(warnings, %{
             explanation: "(calls from MySystem to MySystemWeb are not allowed)",
             callee: "(call originated from MySystem.User)",
             location: "lib/my_system/user.ex:3",
             warning: "forbidden call to MySystemWeb.Endpoint.url/0"
           })

    assert Enum.member?(warnings, %{
             explanation: "(calls from MySystemWeb to MySystem.Application are not allowed)",
             callee: "(call originated from MySystemWeb.ErrorView)",
             location: "lib/my_system_web/templates/error/index.html.eex:1",
             warning: "forbidden call to MySystem.Application.foo/0"
           })
  end

  test "ignored boundaries are not reported" do
    {output, _code} = mix("my_system", ~w/compile/)
    refute String.contains?(output, "SomeTopLevelModule")
  end

  test "exit code is zero with default options" do
    {_output, code} = mix("my_system", ~w/compile/)
    assert code == 0
  end

  test "exit code is non-zero with --warnings-as-errors" do
    {_output, code} = mix("my_system", ~w/compile --warnings-as-errors/)
    assert code == 1
  end

  defp mix!(project_name, args) do
    {output, 0} = mix(project_name, args)
    output
  end

  defp mix(project_name, args),
    do: System.cmd("mix", args, stderr_to_stdout: true, cd: Path.join(~w/demos #{project_name}/))

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
