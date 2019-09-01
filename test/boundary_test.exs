defmodule BoundaryTest do
  use ExUnit.Case, async: true

  alias TestBoundaries.{A, B}

  test "classified modules" do
    modules = Boundary.application(current_app_name()).modules.classified

    assert Map.fetch(modules, A) == {:ok, A}
    assert Map.fetch(modules, B) == {:ok, B}
  end

  test "unclassified modules" do
    assert Enum.member?(
             Boundary.application(current_app_name()).modules.unclassified,
             %{name: Inspect.TestBoundaries.A, protocol_impl?: true}
           )
  end

  test "boundaries" do
    boundaries = Boundary.application(current_app_name()).boundaries

    assert Enum.any?(boundaries, &match?({A, %{deps: [Boundary, B], exports: [A], ignore?: false}}, &1))
    assert Enum.any?(boundaries, &match?({B, %{deps: [Boundary], exports: [B], ignore?: false}}, &1))
  end

  defp current_app_name do
    app = Keyword.fetch!(Mix.Project.config(), :app)
    Application.load(app)
    app
  end
end
