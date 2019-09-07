defmodule SomeTopLevelModule do
  use Boundary, ignore?: true

  def foo do
    MySystemWeb.Endpoint.url()
    MySystem.User.auth()
  end
end
