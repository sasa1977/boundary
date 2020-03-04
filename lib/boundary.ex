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

  By default, all dependencies on modules from other OTP applications are permitted. However, you can restrain such
  dependencies by including boundaries from the external application. For example, let's say you want to limit the ecto
  usage in the web tier to only `Ecto.Changeset`. This can be specified as follows:

  ```
  defmodule MySystemWeb do
    use Boundary, deps: [Ecto.Changeset]
  end
  ```

  Boundary is able to use boundary definitions from an external application, if such exists. If an external application
  doesn't define any boundary, you can still reference application modules. In such case, you're creating an _implicit
  boundary_. This is exactly what we're doing in the previous example. Ecto doesn't define its own boundaries, but we
  can still include `Ecto.Changeset` in the deps list. This will create an implicit boundary of the same name which will
  include all of the submodules like `Ecto.Changeset.Foo`, or `Ecto.Changeset.Bar.Baz`. An implicit boundary exports all
  of its submodules. Note that you can't define implicit boundaries in applications which define their own boundaries.

  The implicit boundaries are collected based on all deps of all boundaries in your application. For example, if one
  boundary specifies `Ecto.Query` as a dependency, while another references `Ecto.Query.API`, then two boundaries are
  defined, and the latter will not be a part of the former.

  In some cases you may want to completely prohibit the usage of some library. However, bare in mind that by default
  calls to an external application are restricted only if the client boundary references at least one dep boundary from
  that application. To force boundary to always restrict calls to some application, you can include the application in
  the `:extra_externals` list:

  ```
  defmodule MySystem do
    use Boundary, extra_externals: [:plug], deps: []
  end
  ```

  The `:extra_externals` list contains additional applications which are always considered. Any calls to given
  applications must be explicitly allowed via the `:deps` option. In the example above, we're including `:plug` in the
  list of external applications, but we're not including any boundary from this library in depssi, the context layer
  is not allowed to use plug functions.

  In addition, a strict external mode is supported via the `:externals_mode` option:

  ```
  defmodule MySystem do
    use Boundary, externals_mode: :strict
  end
  ```

  In this mode, boundary will report all calls to all external applications which are not explicitly allowed via the
  `:dep` option. You can also configure the strict mode globally in your mix.exs:

  ```elixir
  defmodule MySystem.MixProject do
    use Mix.Project

    def project do
      [
        # ...
        boundary: [externals_mode: :strict]
      ]
    end

    # ...
  end
  ```

  At this point, all boundaries will be checked with the strict mode. If you want to override this for some boundaries,
  you can do it with `use Boundary, externals_mode: :relaxed`.

  Note that restraining calls to the `:elixir`, `:boundary`, and pure Erlang applications, such as
  `:crypto` or `:cowboy`, is currently not possible.

  If you want to discover which external applications are used by your boundaries, you can use the helper mix task
  `Mix.Tasks.Boundary.FindExternalDeps`.

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

  require Boundary.Definition
  Boundary.Definition.generate(deps: [], exports: [])

  alias Boundary.Classifier

  @type t :: %{
          name: name,
          deps: [{name, mode}],
          exports: [module],
          externals: [atom],
          extra_externals: [atom],
          externals_mode: :strict | :regular,
          ignore?: boolean,
          file: String.t(),
          line: pos_integer,
          implicit?: boolean,
          app: atom
        }

  @opaque view :: %{
            boundaries: %{name => t},
            classified_modules: %{module => name()},
            unclassified_modules: MapSet.t(module),
            module_to_app: %{module => atom}
          }

  @type name :: module
  @type mode :: :compile | :runtime

  @type call :: %{
          callee: mfa,
          callee_module: module,
          caller_module: module,
          file: String.t(),
          line: pos_integer,
          mode: mode
        }

  @type error ::
          {:empty_boundary, dep_error}
          | {:ignored_dep, dep_error}
          | {:cycle, [Boundary.name()]}
          | {:unclassified_module, [module]}
          | {:invalid_call, [Boundary.call()]}

  @type dep_error :: %{name: Boundary.name(), file: String.t(), line: pos_integer}

  defmacro __using__(opts) do
    opts =
      Enum.map(
        opts,
        fn
          {key, references} when key in ~w/deps exports/a -> {key, normalize_references(references)}
          other -> other
        end
      )

    quote do
      require Boundary.Definition
      Boundary.Definition.generate(unquote(opts))
    end
  end

  @doc "Builds the boundary-specific view of the given application."
  @spec view(atom) :: view
  def view(app), do: build_view(app)

  @doc """
  Returns definitions of all boundaries.

  The result will include boundaries from listed externals, as well as implicit boundaries.
  """
  @spec all(view) :: [t]
  def all(view), do: Map.values(view.boundaries)

  @doc """
  Returns the names of all boundaries.

  The result will include boundaries from listed externals, as well as implicit boundaries.
  """
  @spec all_names(view) :: [name]
  def all_names(view), do: Map.keys(view.boundaries)

  @doc "Returns the definition of the given boundary."
  @spec fetch!(view, name) :: t
  def fetch!(view, name), do: Map.fetch!(view.boundaries, name)

  @doc "Returns the definition of the given boundary."
  @spec fetch(view, name) :: {:ok, t} | :error
  def fetch(view, name), do: Map.fetch(view.boundaries, name)

  @doc "Returns the definition of the given boundary."
  @spec get(view, name) :: t | nil
  def get(view, name), do: Map.get(view.boundaries, name)

  @doc "Returns definition of the boundary to which the given module belongs."
  @spec for_module(view, module) :: t | nil
  def for_module(view, module) do
    with boundary when not is_nil(boundary) <- Map.get(view.classified_modules, module),
         do: Map.fetch!(view.boundaries, boundary)
  end

  @doc "Returns the collection of unclassified modules."
  @spec unclassified_modules(view) :: MapSet.t(module)
  def unclassified_modules(view), do: view.unclassified_modules

  @doc "Returns all boundary errors."
  @spec errors(view, Enumerable.t()) :: [error]
  def errors(view, calls), do: Boundary.Checker.errors(view, calls)

  @doc "Returns the application of the given module."
  @spec app(view, module) :: atom | nil
  def app(view, module), do: Map.get(view.module_to_app, module)

  @doc "Returns true if the module is an implementation of some protocol."
  @spec protocol_impl?(module) :: boolean
  def protocol_impl?(module) do
    # Not sure why, but sometimes the protocol implementation isn't loaded.
    Code.ensure_loaded(module)
    function_exported?(module, :__impl__, 1)
  end

  defp build_view(main_app) do
    main_app_modules = app_modules(main_app)

    module_to_app =
      for {app, _description, _vsn} <- Application.loaded_applications(),
          module <- app_modules(app),
          into: %{},
          do: {module, app}

    %{boundaries: boundaries, modules: classified_modules} =
      main_app
      |> load_apps_and_boundaries(main_app_modules, module_to_app)
      |> Enum.reduce(Classifier.new(), &Classifier.classify(&2, &1.modules, &1.boundaries))

    %{
      boundaries: boundaries,
      classified_modules: classified_modules,
      unclassified_modules: unclassified_modules(main_app_modules, classified_modules),
      module_to_app: module_to_app
    }
  end

  defp load_apps_and_boundaries(main_app, main_app_modules, module_to_app) do
    # fetch boundaries of this app
    app_boundaries = load_app_boundaries(main_app, main_app_modules, module_to_app)

    # fetch and index all deps
    all_deps =
      for user_boundary <- app_boundaries,
          {dep, _type} <- user_boundary.deps,
          into: %{},
          do: {dep, user_boundary}

    # create app -> [boundary] mapping which will be used to determine implicit boundaries
    implicit_boundaries =
      for {dep, user_boundary} <- all_deps,
          boundary_app = Map.get(module_to_app, dep),
          reduce: %{} do
        acc -> Map.update(acc, boundary_app, [{dep, user_boundary}], &[{dep, user_boundary} | &1])
      end

    external_boundaries =
      Enum.map(
        for(boundary <- app_boundaries, app <- boundary.externals, into: MapSet.new(), do: app),
        fn app ->
          modules = app_modules(app)

          boundaries =
            with [] <- load_app_boundaries(app, modules, module_to_app) do
              # app defines no boundaries -> we'll use implicit boundaries from all deps pointing to modules of this app
              implicit_boundaries
              |> Map.get(app, [])
              |> Enum.map(fn
                {dep, user_boundary} ->
                  app
                  |> Boundary.Definition.normalize(dep, [], user_boundary)
                  |> Map.merge(%{name: dep, implicit?: true})
              end)
            end

          %{modules: modules, boundaries: boundaries}
        end
      )

    [%{modules: main_app_modules, boundaries: app_boundaries} | external_boundaries]
  end

  defp load_app_boundaries(app_name, modules, module_to_app) do
    for module <- modules, boundary = Boundary.Definition.get(module) do
      externals =
        boundary.deps
        |> Stream.map(fn {dep, _} -> Map.get(module_to_app, dep) end)
        |> Stream.reject(&is_nil/1)
        |> Stream.reject(&(&1 == app_name))
        |> Stream.concat(boundary.extra_externals)
        |> Enum.uniq()

      Map.merge(boundary, %{name: module, implicit?: false, modules: [], externals: externals})
    end
  end

  defp unclassified_modules(main_app_modules, classified_modules) do
    # gather unclassified modules of this app
    for module <- main_app_modules,
        not Map.has_key?(classified_modules, module),
        not protocol_impl?(module),
        into: MapSet.new(),
        do: module
  end

  defp app_modules(app),
    # we're currently supporting only Elixir modules
    do: Enum.filter(Application.spec(app, :modules), &String.starts_with?(Atom.to_string(&1), "Elixir."))

  defp normalize_references(references) do
    Enum.flat_map(
      references,
      fn
        reference ->
          case Macro.decompose_call(reference) do
            {parent, :{}, children} -> Enum.map(children, &quote(do: Module.concat(unquote([parent, &1]))))
            _ -> [reference]
          end
      end
    )
  end

  defmodule Error do
    defexception [:message, :file, :line]
  end
end
