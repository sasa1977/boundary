defmodule Boundary do
  @moduledoc false

  require Boundary.Definition
  Boundary.Definition.generate(deps: [], exports: [Definition, MixCompiler])

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      require Boundary.Definition
      Boundary.Definition.generate(opts)
    end
  end

  def application(app) do
    app
    |> Application.spec(:modules)
    |> Boundary.Definition.boundaries()
  end
end
