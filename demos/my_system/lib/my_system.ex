defmodule MySystem do
  use Boundary,
    exports: [User],
    deps: [Ecto, {Mix, :compile}]

  Mix.env()

  def foo() do
    Mix.env()
  end
end
