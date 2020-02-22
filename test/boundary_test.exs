defmodule BoundaryTest do
  use ExUnit.Case, async: true

  alias TestBoundaries.{A, B}

  test "classification" do
    modules = Boundary.spec(current_app_name()).modules

    assert Map.fetch(modules.classified, A) == {:ok, A}
    assert Map.fetch(modules.classified, B) == {:ok, B}
    assert Map.fetch(modules.classified, String.Chars.TestBoundaries.A) == {:ok, A}
    assert Enum.member?(modules.unclassified, %{name: Inspect.TestBoundaries.A, protocol_impl?: true})
  end

  test "boundaries" do
    boundaries = Boundary.spec(current_app_name()).boundaries

    assert Enum.any?(boundaries, &match?({A, %{deps: [Boundary, B], exports: [A], ignore?: false}}, &1))
    assert Enum.any?(boundaries, &match?({B, %{deps: [Boundary], exports: [B], ignore?: false}}, &1))
  end

  defp current_app_name do
    app = Keyword.fetch!(Mix.Project.config(), :app)
    Application.load(app)
    app
  end
end
