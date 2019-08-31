defmodule TestBoundaries do
  @moduledoc false

  use Boundary, deps: [Boundary]

  defmodule A do
    @moduledoc false

    use Boundary, deps: [Boundary, TestBoundaries.B]
    def some_fun, do: TestBoundaries.B.some_fun()
  end

  defmodule B do
    @moduledoc false

    use Boundary, deps: [Boundary]
    def some_fun, do: :ok
  end
end
