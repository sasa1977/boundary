defmodule Boundary.Mix do
  @moduledoc false

  require Boundary.Definition
  Boundary.Definition.generate(deps: [Boundary], exports: [Xref])
end
