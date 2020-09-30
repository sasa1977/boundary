defmodule SomeTopLevelModule do
  use Boundary, check: [in: false, out: false]

  def foo do
    MySystemWeb.Endpoint.url()
    MySystem.User.auth()
  end
end
