defmodule MySystem do
  use Boundary,
    exports: [User],
    deps: []

  Mix.env()

  def foo() do
    Mix.env()
  end
end
