defmodule BoundaryTest do
  use ExUnit.Case, async: true

  alias TestBoundaries.{A, B}

  describe "application/0" do
    test "modules" do
      application = Boundary.application()

      assert Enum.member?(application.modules, A)
      assert Enum.member?(application.modules, B)
    end

    test "calls" do
      application = Boundary.application()

      test_calls =
        application.calls
        |> Stream.filter(&String.starts_with?(inspect(&1.caller_module), "TestBoundaries"))
        |> Stream.filter(&String.starts_with?(inspect(&1.callee_module), "TestBoundaries"))
        |> Enum.map(&{&1.caller_module, &1.callee_module})

      assert MapSet.new(test_calls) == MapSet.new([{A, B}])
    end

    test "boundaries" do
      boundaries = Boundary.application().boundaries

      assert Enum.member?(boundaries, {A, %{deps: [Boundary, B], exports: [A]}})
      assert Enum.member?(boundaries, {B, %{deps: [Boundary], exports: [B]}})
    end
  end
end
