defmodule TestBoundaries.A do
  @moduledoc false

  defstruct [:x]

  use Boundary, deps: [Boundary, TestBoundaries.B]
  def some_fun, do: TestBoundaries.B.some_fun()
end
