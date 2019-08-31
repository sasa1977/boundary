defmodule Boundary.MixCompilerTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Boundary.Test.Application
  alias Boundary.Test.Generator

  property "unknown boundaries as deps are reported" do
    check all app <- Generator.app(),
              {invalid_deps, app} <- Generator.with_unknown_deps(app),
              expected_errors =
                Enum.map(
                  invalid_deps,
                  &Boundary.MixCompiler.diagnostic("unknown boundary #{inspect(&1)} is listed as a dependency")
                ),
              max_runs: 10 do
      assert {:error, errors} = Application.check(app, [])
      assert Enum.sort(errors) == Enum.sort(expected_errors)
    end
  end

  property "ignored boundaries as deps are reported" do
    check all app <- Generator.app(),
              {invalid_deps, app} <- Generator.with_ignored_deps(app),
              expected_errors =
                Enum.map(
                  invalid_deps,
                  &Boundary.MixCompiler.diagnostic("ignored boundary #{inspect(&1)} is listed as a dependency")
                ),
              max_runs: 10 do
      assert {:error, errors} = Application.check(app, [])
      assert Enum.sort(errors) == Enum.sort(expected_errors)
    end
  end

  property "cycles are reported" do
    check all app <- Generator.app(),
              Application.num_boundaries(app) >= 2,
              {boundaries_in_cycle, app} <- Generator.with_cycle(app),
              max_runs: 10 do
      assert {:error, errors} = Application.check(app, [])
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
    check all app <- Generator.app(),
              {unclassified_modules, app} <- Generator.with_unclassified_modules(app),
              expected_errors =
                Enum.map(
                  unclassified_modules,
                  # Note: passing file: "" option, because module doesn't exist, so it's file can't be determined
                  &Boundary.MixCompiler.diagnostic("#{inspect(&1)} is not included in any boundary", file: "")
                ),
              max_runs: 10 do
      assert {:error, errors} = Application.check(app, [])
      assert Enum.sort(errors) == Enum.sort(expected_errors)
    end
  end

  property "ignored boundaries are not reported as unclassified" do
    check all app <- Generator.app(),
              {unclassified_modules, app} <- Generator.with_unclassified_modules(app),
              app = Enum.reduce(unclassified_modules, app, &Application.add_boundary(&2, &1, ignore?: true)),
              max_runs: 10 do
      assert :ok = Application.check(app, [])
    end
  end

  property "empty boundaries are reported" do
    check all app <- Generator.app(),
              {empty_boundaries, app} <- Generator.with_empty_boundaries(app),
              expected_errors =
                Enum.map(
                  empty_boundaries,
                  &Boundary.MixCompiler.diagnostic("boundary #{inspect(&1)} doesn't include any module")
                ),
              max_runs: 10 do
      assert {:error, errors} = Application.check(app, [])
      assert Enum.sort(errors) == Enum.sort(expected_errors)
    end
  end

  test "empty app with no calls is valid" do
    app = Application.empty()
    assert Application.check(app, []) == :ok
  end

  property "valid app passes the check" do
    check all app <- Generator.app(),
              Application.num_boundaries(app) >= 2,
              {calls, app} <- Generator.with_valid_calls(app) do
      assert Application.check(app, calls) == :ok
    end
  end

  property "all forbidden calls are reported" do
    check all app <- Generator.app(),
              Application.num_boundaries(app) >= 2,
              {valid_calls, app} <- Generator.with_valid_calls(app),
              {invalid_calls, expected_errors} <- Generator.with_invalid_calls(app),
              all_calls = Enum.shuffle(valid_calls ++ invalid_calls) do
      assert {:error, errors} = Application.check(app, all_calls)
      assert errors == expected_errors
    end
  end

  property "forbidden calls are not reported on ignored boundaries" do
    check all app <- Generator.app(),
              Application.num_boundaries(app) >= 2,
              {valid_calls, app} <- Generator.with_valid_calls(app),
              {invalid_calls, _expected_errors} <- Generator.with_invalid_calls(app),
              all_calls = Enum.shuffle(valid_calls ++ invalid_calls),
              app = Enum.reduce(invalid_calls, app, &ignore_call_boundaries(&2, &1)) do
      assert Application.check(app, all_calls) == :ok
    end
  end

  defp ignore_call_boundaries(app, call),
    do: app |> ignore_boundary(call.callee_module) |> ignore_boundary(call.caller_module)

  defp ignore_boundary(app, module), do: Application.ignore_boundary(app, Application.module_boundary(app, module))
end
