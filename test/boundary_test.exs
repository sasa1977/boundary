defmodule BoundaryTest do
  use ExUnit.Case, async: true

  alias TestBoundaries.{A, B}

  describe "application/0" do
    test "modules" do
      modules = Boundary.application(current_app_name()).modules.classified

      assert Map.fetch(modules, A) == {:ok, A}
      assert Map.fetch(modules, B) == {:ok, B}
    end

    test "boundaries" do
      boundaries = Boundary.application(current_app_name()).boundaries

      assert Enum.any?(boundaries, &match?({TestBoundaries, %{deps: [], exports: [], ignore?: true}}, &1))
      assert Enum.any?(boundaries, &match?({A, %{deps: [Boundary, B], exports: [A], ignore?: false}}, &1))
      assert Enum.any?(boundaries, &match?({B, %{deps: [Boundary], exports: [B], ignore?: false}}, &1))
    end
  end

  defp current_app_name do
    app = Keyword.fetch!(Mix.Project.config(), :app)
    Application.load(app)
    app
  end
end
