defmodule Boundary.CheckerTest do
  use ExUnit.Case, async: true

  alias TestBoundaries.{A, B}

  test "calls" do
    test_calls =
      Boundary.Checker.calls()
      |> Stream.filter(&String.starts_with?(inspect(&1.caller_module), "TestBoundaries"))
      |> Stream.filter(&String.starts_with?(inspect(&1.callee_module), "TestBoundaries"))
      |> Enum.map(&{&1.caller_module, &1.callee_module})

    assert MapSet.new(test_calls) == MapSet.new([{A, B}])
  end
end
