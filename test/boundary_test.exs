defmodule BoundaryTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Boundary.Test.Generator
  alias Boundary.Test.Project

  describe "boundaries.exs errors" do
    property "duplicate deps are reported" do
      check all project <- Generator.generate(),
                {duplicates, project} <- Generator.with_duplicate_boundaries(project),
                expected_errors =
                  Enum.map(
                    duplicates,
                    &Boundary.diagnostic("#{inspect(&1)} is declared as a boundary more than once")
                  ),
                max_runs: 10 do
        assert {:error, errors} = Project.check(project, [])
        assert Enum.sort(errors) == Enum.sort(expected_errors)
      end
    end

    property "invalid deps are reported" do
      check all project <- Generator.generate(),
                {invalid_deps, project} <- Generator.with_invalid_deps(project),
                expected_errors =
                  Enum.map(
                    invalid_deps,
                    &Boundary.diagnostic("#{inspect(&1)} is listed as a dependency but not declared as a boundary")
                  ),
                max_runs: 10 do
        assert {:error, errors} = Project.check(project, [])
        assert Enum.sort(errors) == Enum.sort(expected_errors)
      end
    end

    property "cycles are reported" do
      check all project <- Generator.generate(),
                Project.num_boundaries(project) >= 2,
                {boundaries_in_cycle, project} <- Generator.with_cycle(project),
                max_runs: 10 do
        assert {:error, errors} = Project.check(project, [])
        assert cycle_error = Enum.find(errors, &String.starts_with?(&1.message, "dependency cycles found"))

        reported_cycle_boundaries =
          cycle_error.message
          |> String.replace("dependency cycles found:\n", "")
          |> String.trim()
          |> String.split(" -> ")
          |> Enum.map(&Module.concat([&1]))
          |> MapSet.new()

        assert reported_cycle_boundaries == MapSet.new(boundaries_in_cycle)
      end
    end

    property "unclassified modules are reported" do
      check all project <- Generator.generate(),
                {unclassified_modules, project} <- Generator.with_unclassified_modules(project),
                expected_errors =
                  Enum.map(
                    unclassified_modules,
                    # Note: passing file: "" option, because module doesn't exist, so it's file can't be determined
                    &Boundary.diagnostic("#{inspect(&1)} is not included in any boundary", file: "")
                  ),
                max_runs: 10 do
        assert {:error, errors} = Project.check(project, [])
        assert Enum.sort(errors) == Enum.sort(expected_errors)
      end
    end

    property "empty boundaries are reported" do
      check all project <- Generator.generate(),
                {empty_boundaries, project} <- Generator.with_empty_boundaries(project),
                expected_errors =
                  Enum.map(
                    empty_boundaries,
                    &Boundary.diagnostic("boundary #{inspect(&1)} doesn't include any module")
                  ),
                max_runs: 10 do
        assert {:error, errors} = Project.check(project, [])
        assert Enum.sort(errors) == Enum.sort(expected_errors)
      end
    end
  end

  describe "project validation" do
    test "empty project with no calls is valid" do
      project = Project.empty()
      assert Project.check(project, []) == :ok
    end

    property "valid project passes the check" do
      check all project <- Generator.generate(),
                Project.num_boundaries(project) >= 2,
                {calls, project} <- Generator.with_valid_calls(project) do
        assert Project.check(project, calls) == :ok
      end
    end

    property "all forbidden calls are reported" do
      check all project <- Generator.generate(),
                Project.num_boundaries(project) >= 2,
                {valid_calls, project} <- Generator.with_valid_calls(project),
                {invalid_calls, expected_errors} <- Generator.with_invalid_calls(project),
                all_calls = Enum.shuffle(valid_calls ++ invalid_calls) do
        assert {:error, errors} = Project.check(project, all_calls)
        assert errors == expected_errors
      end
    end
  end
end
