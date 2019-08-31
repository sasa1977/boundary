defmodule Boundary do
  @type application :: %{
          boundaries: %{name => definition},
          modules: %{
            classified: %{module => name},
            unclassified: [module]
          }
        }

  @type name :: module
  @type definition :: %{deps: [name], exports: [module]}

  require Boundary.Definition
  Boundary.Definition.generate(deps: [], exports: [Definition, MixCompiler])

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      require Boundary.Definition
      Boundary.Definition.generate(opts)
    end
  end

  @spec application(atom) :: application
  def application(app_name) do
    app_name
    |> Application.spec(:modules)
    |> Boundary.Definition.boundaries()
  end
end
