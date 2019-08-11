defmodule MySystemWeb.UserController do
  def some_action() do
    MySystem.User.auth()
  end
end
