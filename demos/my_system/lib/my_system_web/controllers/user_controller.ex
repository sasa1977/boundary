defmodule MySystemWeb.UserController do
  import Ecto.Query

  def some_action() do
    Ecto.Changeset.cast(%{}, %{}, [])
    from(s in "foo", select: "bar")
    MySystem.User.auth()
  end
end
