defmodule MySystem do
  use Boundary, deps: [Ecto], exports: [User], externals_mode: :strict
end
