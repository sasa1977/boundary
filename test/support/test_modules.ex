defmodule Boundary.TestModules.Foo do
  def some_fun(), do: Boundary.TestModules.Bar.some_fun()
end

defmodule Boundary.TestModules.Bar do
  def some_fun(), do: Boundary.TestModules.Foo.some_fun()
end
