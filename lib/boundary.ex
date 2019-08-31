defmodule Boundary do
  @moduledoc """
  Definition of boundaries within the application.

  A boundary is a named group of modules which can export some of its modules, and depend on other
  boundaries.

  Boundary definitions can be used in combination with `Mix.Tasks.Compile.Boundary` to restrain
  cross-module dependencies. For example, you can use boundaries to prevent invocations
  from the context layer (e.g. `MySystem`) to the UI layer (e.g. `MySystemWeb`).

  ## Quick example

  The following code defines boundaries for a typical Phoenix based project generated with
  `mix phx.new`.

  ```
  defmodule MySystem do
    use Boundary, deps: [], exports: []
    # ...
  end

  defmodule MySystemWeb do
    use Boundary, deps: [MySystem], exports: [Endpoint]
    # ...
  end

  defmodule MySystem.Application do
    use Boundary, deps: [MySystem, MySystemWeb]
    # ...
  end
  ```

  These boundaries specify the allowed cross-boundary usage:

    - Modules from `MySystemWeb` may use the `MySystem` module, but not other `MySystem.*` modules.
    - `MySystem.Application` code may use `MySystem`, `MySystemWeb`, and `MySystemWeb.Endpoint`
      modules.


  ## Defining a boundary

  A boundary is defined via `use Boundary` expression in the top-level (aka root) module. For example,
  the context boundary named `MySystem` can be defined as follows:

  ```
  defmodule MySystem do
    use Boundary, opts
    # ...
  end
  ```

  ## Module classification

  Based on the existing definitions, modules are classified into boundaries. Each module can
  belong to at most one boundary. A module doesn't need to belong to a boundary, in which case we
  say that the module is unclassified.

  Boundary membership is determined from the module name. In the previous example, we defined a
  single boundary, called `MySystem`. This boundary will contain the root module (`MySystem`),
  as well as all modules whose name starts with `MySystem.`.

  In addition, it's possible to extract some of the modules from a boundary into its own boundary.
  For example:

  ```
  defmodule MySystem do
    use Boundary, opts
  end

  defmodule MySystem.Endpoint do
    use Boundary, opts
  end
  ```

  Here, modules from `MySystem.Endpoint` namespace are promoted into its own boundary. It's
  worth noting that `MySystem.Endpoint` is considered as a peer boundary of `MySystem`, not its
  child. At the moment, nesting of boundaries (defining internal boundaries within other
  boundaries) is not supported by this library.

  ## Exports

  Exports are boundary modules which can be used by modules from other boundaries. A boundary
  always exports its root module, and it may additionally export other modules, which can be
  configured with the `:exports` option:

  ```
  defmodule MySystem do
    use Boundary, exports: [User]
  end
  ```

  In this example, we're defining the `MySystem` boundary which exports the modules `MySystem`
  and `MySystem.User`. All other modules of this boundary are considered to be internal, and
  they may not be used by modules from other boundaries.

  ## Dependencies

  Each boundary may depend on other boundaries. These dependencies are used to defined allowed
  cross-boundary module usage. A module from another boundary may only be used if:

    - The callee boundary is a direct dependency of the caller boundary.
    - The callee boundary exports the used module.

  For example:

  ```
  defmodule MySystem do
    use Boundary, exports: [User], deps: []
  end

  defmodule MySystemWeb do
    use Boundary, exports: [], deps: [MySystem]
  end
  ```

  In this example we specify the following rules:

    - Code from the `MySystem` boundary can't use any module from other boundaries.
    - Code from the `MySystemWeb` boundary may use exports of the `MySystem` boundary
      (`MySystem` and `MySystem.User`).

  Of course, in-boundary cross-module dependencies are always allowed (any module may use all
  other modules from the same boundary).

  ## Ignored boundaries

  It is possible to exclude some modules from cross-boundary checks by defining an __ignored__ boundary:

  ```
  defmodule MySystem do
    use Boundary, ignore?: true
  end
  ```

  When a boundary is ignored, all modules belonging to it can use any other module, and can be used
  by any other module.

  The purpose of this options is to support relaxing rules in some parts of your code. For example,
  you may wish to ignore boundary constraints for your test support modules. By introducing a
  top-level boundary for such modules (e.g. `MySystemTest`), and marking this boundary as ignored,
  you can easily achieve that.

  Another scenario is when introducing boundaries in an existing, possibly large project, which
  has many complex dependencies that can't be untangled trivially. In such case, ignored
  boundaries provide a mechanism for gradually introducing boundaries into the project.

  For example, you could first define ignored boundaries which encompass the entire system:

  ```
  defmodule MySystem do
    use Boundary, ignore?: true
  end

  defmodule MySystemWeb do
    use Boundary, ignore?: true
  end
  ```

  Now, you can pick smaller parts of your code where you can clean up the dependencies:

  ```
  defmodule MySystem.Context1 do
    use Boundary, exports: [...], deps: []
  end

  defmodule MySystemWeb.Controller1 do
    use Boundary, exports: [], deps: [MySystem.Context1]
  end
  ```

  Going further, you can gradually expand the parts of your code covered by non-ignored boundaries.
  Once you're properly covering the entire system, you can remove the intermediate finer-grained
  boundaries, and specify the rules at the higher-level:

  ```
  defmodule MySystem do
    use Boundary, exports: [...], deps: []
  end

  defmodule MySystemWeb do
    use Boundary, exports: [Endpoint], deps: [...]
  end
  ```
  """
  @type application :: %{
          boundaries: %{name => definition},
          modules: %{
            classified: %{module => name},
            unclassified: [module]
          }
        }

  @type name :: module
  @type definition :: %{deps: [name], exports: [module], ignore?: boolean, file: String.t(), line: pos_integer}

  require Boundary.Definition
  Boundary.Definition.generate(deps: [], exports: [Definition, MixCompiler])

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      require Boundary.Definition
      Boundary.Definition.generate(opts)
    end
  end

  @doc "Returns the boundary-specific view of the given application."
  @spec application(atom) :: application
  def application(app_name) do
    app_name
    |> Application.spec(:modules)
    |> Boundary.Definition.boundaries()
  end
end
