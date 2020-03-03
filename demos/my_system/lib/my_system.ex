defmodule MySystem do
  use Boundary,
    exports: [User],
    deps: [Ecto, {Mix, :compile}],
    externals_mode: :strict

  Mix.env()

  def foo() do
    Mix.env()
  end
end
