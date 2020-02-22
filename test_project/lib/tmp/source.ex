defmodule Boundary1 do
end

defmodule Boundary2 do
  use Boundary, deps: [Boundary4, UnknownBoundary], exports: []

  def fun(), do: Boundary3.fun()

  defmodule Internal do
    def fun(), do: :ok
  end
end

defmodule Boundary3 do
  use Boundary, deps: [Boundary2], exports: []

  def fun(), do: Boundary2.Internal.fun()
end

defmodule Boundary4 do
  use Boundary, ignore?: true
end

defmodule Boundary5 do
  use Boundary, deps: [Boundary6], exports: []

  def fun(), do: :ok
end

defmodule Boundary6 do
  use Boundary, deps: [Boundary5], exports: []

  def fun(), do: :ok
end
