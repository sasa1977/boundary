defmodule Boundary.Mix do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  require Boundary.Definition
  Boundary.Definition.generate(deps: [Boundary], exports: [Xref])

  def app_name, do: Keyword.fetch!(Mix.Project.config(), :app)
end
