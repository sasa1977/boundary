defmodule Boundary.Mix do
  @moduledoc false

  require Boundary.Definition
  Boundary.Definition.generate(deps: [Boundary], exports: [Xref])

  def app_name(), do: Keyword.fetch!(Mix.Project.config(), :app)
end
