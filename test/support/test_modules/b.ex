defmodule TestBoundaries.B do
  @moduledoc false

  use Boundary, deps: [Boundary]
  def some_fun, do: :ok
end
