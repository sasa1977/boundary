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

  ### Mix tasks

  By convention, mix tasks have to reside in the `Mix.Tasks` namespace, which makes it harder to
  put them under the same boundary. To assist with this, boundary supports manual reclassification
  of such modules.

  The advised approach is to introduce the `MySystem.Mix` boundary which can hold helper functions
  required by the mix tasks. With such boundary in place, you can manually classify mix tasks as:

  ```
  defmodule Mix.Tasks.SomeTask do
    use Boundary, classify_to: MySystem.Mix
    use Mix.Task
  end

  defmodule Mix.Tasks.AnotherTask do
    use Boundary, classify_to: MySystem.Mix
    use Mix.Task
  end
  ```

  This way, both modules will be considered as a part of the `MySystem.Mix` boundary.

  Note that manual classification is allowed only for mix tasks and protocol implementations (see
  the following section).

  ### Protocol implementation

  Consider the following protocol implementation:

  ```
  defimpl String.Chars, for: MySchema, do: # ...
  ```

  This code will generate the module `String.Chars.MySchema`. Therefore, the module sits in a
  completely different "namespace". In addition, the desired boundary of such module can vary from
  one case to another. In some cases, a protocol implementation might be a UI concern, while in
  others, it might be a domain concern.

  For these reasons, protocol implementations are treated in a special way. A protocol
  implementation is by default unclassified (it doesn't belong to any boundary). However, the
  boundary checker will not emit a warning for unclassified protocol implementations.

  However, you can manually classify the protocol implementation, as demonstrated in the following
  example:

  ```
  defimpl String.Chars, for: MySchema do
    use Boundary, classify_to: MySystem
    # ...
  end
  ```

  Note that `:classify_to` option is only allowed for protocol implementations and mix tasks.
  Other modules can't be manually classified.

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

  ### External dependencies

  By default, all dependencies on 3rd party modules (modules from other OTP applications) are permitted. However, you
  can restrain such dependencies using the `:externals` option. For example, let's say you want to prevent using
  `Ecto` in the Web tier, except for `Ecto.Changeset`. This can be specified as follows:

  ```
  defmodule MySystemWeb do
    use Boundary, externals: [ecto: {:only, [Ecto.Changeset]}]
  end
  ```

  The `:externals` option has the shape of `[{app_name, {:only | :except, boundaries}]`, where `boundaries` is a list of
  modules which can be referenced.

  Each module is treated as a boundary, which means that listing a module will also include "submodules". For example,
  if `Ecto.Query` is in the boundaries list, `Ecto.Query.API` and `Ecto.Query.WindowAPI` are also included. To
  completely disallow some external app to be used by a boundary, you can provide `app_name: {:only, []}`.

  If an app is not included in the externals list, all the calls to its modules are permitted. In other words, the
  `:externals` option works as an opt-in. You only list the apps which you want to restrain.

  `:stdlib`, `:kernel`, and `:elixir` are considered as core applications which can't be configured. Providing these
  applications in the `:externals` list won't have any effects.

  You can use the `Mix.Tasks.Boundary.FindExternalDeps` mix task to explore external dependencies of your boundaries.

  ## Ignored boundaries

  It is possible to exclude some modules from cross-boundary checks by defining an __ignored__ boundary:

  ```
  defmodule MySystem do
    use Boundary, ignore?: true
  end
  ```

  When a boundary is ignored, all modules belonging to it can use any other module, and can be used
  by any other module.

  The purpose of this option is to support relaxing rules in some parts of your code. For example,
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
  @opaque spec :: %{
            boundaries: %{name => definition},
            modules: %{classified: %{module => name}, unclassified: MapSet.t(module)},
            module_to_app: %{module => atom}
          }

  @type name :: module

  @type definition :: %{
          name: name,
          deps: [name],
          exports: [module],
          externals: %{atom => {:only | :except, [name]}},
          ignore?: boolean,
          file: String.t(),
          line: pos_integer
        }

  @type call :: %{
          callee: mfa,
          callee_module: module,
          caller_module: module,
          file: String.t(),
          line: pos_integer,
          mode: :compile | :runtime
        }

  @type error ::
          {:unknown_dep, dep_error}
          | {:ignored_dep, dep_error}
          | {:cycle, [Boundary.name()]}
          | {:unclassified_module, [module]}
          | {:invalid_call, [Boundary.call()]}

  @type dep_error :: %{name: Boundary.name(), file: String.t(), line: pos_integer}

  require Boundary.Definition
  Boundary.Definition.generate(deps: [], exports: [])

  alias Boundary.Definition

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      require Boundary.Definition
      Boundary.Definition.generate(opts)
    end
  end

  @doc "Builds the boundary-specific view of the given application."
  @spec spec(atom) :: spec
  def spec(app_name) do
    app_name
    |> Application.spec(:modules)
    |> build_spec()
  end

  @doc "Returns definitions of all boundaries."
  @spec all(spec) :: [definition]
  def all(spec), do: Map.values(spec.boundaries)

  @doc "Returns the names of all boundaries."
  @spec all_names(spec) :: [name]
  def all_names(spec), do: Map.keys(spec.boundaries)

  @doc "Returns definition of the boundary to which the given module belongs."
  @spec get(spec, module) :: definition | nil
  def get(spec, module) do
    with boundary_name when not is_nil(boundary_name) <- Map.get(spec.modules.classified, module),
         do: Map.fetch!(spec.boundaries, boundary_name)
  end

  @doc "Returns the application of the given module."
  @spec app(spec, module) :: atom | nil
  def app(spec, module), do: Map.get(spec.module_to_app, module)

  @doc "Returns the collection of unclassified modules."
  @spec unclassified_modules(spec) :: MapSet.t(module)
  def unclassified_modules(spec), do: spec.modules.unclassified

  @doc "Returns all boundary errors."
  @spec errors(spec(), Enumerable.t()) :: [error]
  def errors(spec, calls), do: Boundary.Checker.errors(spec, calls)

  @doc false
  def build_spec(modules) do
    boundaries = load_boundaries(modules)

    %{
      modules: classify_modules(boundaries, modules),
      boundaries: boundaries,
      module_to_app: module_to_app()
    }
  end

  defp module_to_app do
    for {app, _description, _vsn} <- Application.loaded_applications(),
        module <- Application.spec(app, :modules),
        into: %{erlang: :erlang},
        do: {module, app}
  end

  defp load_boundaries(modules) do
    for module <- modules,
        boundary_spec = Definition.get(module),
        not is_nil(boundary_spec),
        into: %{},
        do: {module, Map.put(boundary_spec, :name, module)}
  end

  defp classify_modules(boundaries, modules) do
    boundaries_search_space =
      boundaries
      |> Map.keys()
      |> Enum.sort(&>=/2)
      |> Enum.map(&%{name: &1, parts: Module.split(&1)})

    Enum.reduce(
      modules,
      %{classified: %{}, unclassified: MapSet.new()},
      fn module, modules ->
        case target_boundary(module, boundaries_search_space, boundaries) do
          nil ->
            if protocol_impl?(module),
              do: modules,
              else: update_in(modules.unclassified, &MapSet.put(&1, module))

          boundary ->
            put_in(modules.classified[module], boundary)
        end
      end
    )
  end

  defp target_boundary(module, boundaries_search_space, boundaries) do
    case Definition.classified_to(module) do
      nil ->
        parts = Module.split(module)

        with boundary when not is_nil(boundary) <-
               Enum.find(boundaries_search_space, &List.starts_with?(parts, &1.parts)),
             do: boundary.name

      classified_to ->
        unless Map.has_key?(boundaries, classified_to.boundary) do
          message = "invalid boundary #{classified_to.boundary}"
          raise Boundary.Error, message: message, file: classified_to.file, line: classified_to.line
        end

        classified_to.boundary
    end
  end

  defp protocol_impl?(module) do
    # Not sure why, but sometimes the protocol implementation isn't loaded.
    Code.ensure_loaded(module)

    function_exported?(module, :__impl__, 1)
  end

  defmodule Error do
    defexception [:message, :file, :line]
  end
end
