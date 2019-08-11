defmodule MySystemWeb.Router do
  use MySystemWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MySystemWeb do
    pipe_through :api
  end
end
