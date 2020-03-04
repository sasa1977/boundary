defmodule Boundary.ProjectTestCase do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Readability.Specs
  use ExUnit.CaseTemplate
  alias Boundary.TestProject

  using do
    quote do
      import unquote(__MODULE__)
      alias Boundary.TestProject
    end
  end

  setup_all do
    {:ok, %{project: TestProject.create()}}
  end

  setup context do
    TestProject.reinitialize(context.project)
  end
end
