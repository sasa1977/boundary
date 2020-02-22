defmodule MySystemWeb do
  use Boundary,
    exports: [Endpoint],
    deps: [MySystem],
    externals: [ecto: [Ecto.Changeset]]

  def controller do
    quote do
      use Phoenix.Controller, namespace: MySystemWeb

      import Plug.Conn
      import MySystemWeb.Gettext
      alias MySystemWeb.Router.Helpers, as: Routes
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/my_system_web/templates",
        namespace: MySystemWeb

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_flash: 1, get_flash: 2, view_module: 1]

      import MySystemWeb.ErrorHelpers
      import MySystemWeb.Gettext
      alias MySystemWeb.Router.Helpers, as: Routes
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      import MySystemWeb.Gettext
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
