defmodule MySystem.User do
  def auth do
    MySystemWeb.Endpoint.url()
  end
end
