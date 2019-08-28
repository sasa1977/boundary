defmodule BoundaryTest do
  use ExUnit.Case, async: true

  describe "application/0" do
    test "loads modules" do
      application = Boundary.application()

      assert Enum.member?(application.modules, Boundary.TestModules.Foo)
      assert Enum.member?(application.modules, Boundary.TestModules.Bar)
    end

    test "loads calls" do
      application = Boundary.application()

      test_calls =
        application.calls
        |> Stream.filter(&String.starts_with?(inspect(&1.caller_module), "Boundary.TestModules"))
        |> Stream.filter(&String.starts_with?(inspect(&1.callee_module), "Boundary.TestModules"))
        |> Enum.map(&{&1.caller_module, &1.callee_module})

      expected_calls = [
        {Boundary.TestModules.Foo, Boundary.TestModules.Bar},
        {Boundary.TestModules.Bar, Boundary.TestModules.Foo}
      ]

      assert MapSet.new(test_calls) == MapSet.new(expected_calls)
    end
  end
end
