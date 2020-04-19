defmodule Boundary do
  @moduledoc """
  Definition of boundaries within the application.

  A boundary is a named group of modules which can export some of its modules, and depend on other
  boundaries.

  Boundary definitions can be used in combination with `Mix.Tasks.Compile.Boundary` to restrain
  cross-module dependencies. A few examples of what you can do with boundary include:

  - Prevent invocations from the context layer to the web layer
  - Prevent invocations from the web layer to internal context modules
  - Prevent usage of Phoenix and Plug in the context layer
  - Limit usage of Ecto in the web layer to only Ecto.Changeset
  - Allow `:mix` modules to be used only at compile time

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

  A boundary is defined via `use Boundary` expression in the root module. For example, the context
  boundary named `MySystem` can be defined as follows:

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

  In addition, it's possible to extract some of the modules from a boundary into another boundary.
  For example:

  ```
  defmodule MySystem do
    use Boundary, opts
  end

  defmodule MySystem.Endpoint do
    use Boundary, opts
  end
  ```

  See the "Nested boundaries" section for details.

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

  ### Mass exports

  It's also possible to mass-export multiple modules with a single export item.

  For example, let's say that we keep Ecto schemas under the `MySystem.Schemas` namespace. Now we
  want to export all of these modules except `MySystem.Schemas.Base` which is a base module `use`-d
  by our schemas. We could list each individual schema in the exports section but that becomes
  tedious, and the `use Boundary` expression might become quite long and noisy. Instead, we can
  export all of these modules with the `exports: [{Schemas, except: [Base]}, ...]`.

  Mass export is not advised in most situations. Prefer explicitly listing exported modules. If
  your export list is long, it's a possible indication of an overly fragmented interface. Consider
  instead consolidating the interface in the main boundary module, which would act as a facade.
  Alternatively, perhaps the boundary needs to be split.

  However, cases such as Ecto schemas present a valid exception, since these modules are typically
  a part of the public context interface, since they are passed back and forth between the
  context and the interface layer (such as web).


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

  When listing deps and exports, a "grouping" syntax can also be used:

  ```
  use Boundary, deps: [Foo.{Bar, Baz}]
  ```

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

  ```
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

  ### Compile-time dependencies

  By default, a dependency allows calls at both, compile time and runtime. In some cases you may want to permit calls to
  some dependency only at compile-time. A typical example are modules from the `:mix` application. These modules are
  not safe to be used at runtime. Limiting their usage to compile-time only can be done as follows:

  ```
  use Boundary, deps: [{Mix, :compile}]
  ```

  With such configuration, the following calls are allowed:

  - Function invocations at compile time (i.e. outside of any function, or in `unquote(...)`).
  - Macro invocations anywhere in the code.
  - Any invocations made from a public macro.

  Note that you might have some modules which will require runtime dependency on mix, such as custom mix tasks. It's
  advised to group such modules under a common boundary, such as `MySystem.Mix`, and allow `mix` as a runtime
  dependency only in that boundary.

  Finally, it's worth noting that it's not possible to permit some dependency only at runtime. If a dependency is
  allowed at runtime, then it can also be used at compile time.

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

  ## Nested boundaries

  It is possible to define boundaries within boundaries. Nested boundaries allow you to further
  control the dependency graph inside the boundary, and make some in-boundary modules private to
  others.

  Let's see this in an example. Suppose that we're building a Phoenix-powered blog engine. Our
  context layer, `BlogEngine`, exposes two modules, `Accounts` and `Articles` (note that
  `BlogEngine.` prefix is omitted for brevity) to the web tier:

  ```
  defmodule BlogEngine do
    use Boundary, exports: [Accounts, Articles]
  end

  defmodule BlogEngineWeb do
    use Boundary, deps: [BlogEngine]
  end
  ```

  But beyond this, we want to further manage the dependencies inside the context. The context tier
  consists of the modules `Repo, `Articles, `Accounts, and `Accounts.Mailer`. We'd like to
  introduce the following constraints:

  - `Articles` can use `Accounts` (but not the other way around).
  - Both `Articles` and `Accounts` can use `Repo`, but `Repo` can't use any other module.
  - Only the `Accounts` module can use the internal `Accounts.Mailer` module.

  Here's how we can do that:

  ```
  defmodule BlogEngine.Repo do
    use Boundary
  end

  defmodule BlogEngine.Articles do
    use Boundary, deps: [BlogEngine.{Accounts, Repo}]
  end

  defmodule BlogEngine.Accounts do
    use Boundary, deps: [BlogEngine.Repo]
  end
  ```

  Conceptually, we've built a boundary sub-tree inside `BlogEngine` which looks as:

  ```text
  BlogEngine
  |
  +----Repo
  |
  +----Articles
  |
  +----Accounts
  ```

  With the following dependencies:

  ```text
  Articles ----> Repo
     |            ^
     v            |
  Accounts -------+
  ```

  ### Root module

  The root module of a sub-boundary plays a special role. This module can be exported by the parent
  boundary, and at the same time it defines its own boundary. This can be seen in the previous
  example, where all three modules, `Articles`, `Accounts`, and `Repo` are exported by
  `BlogEngine`, while at the same time these modules define their own sub-boundaries.

  This demonstrates the main purpose of sub-boundaries. They are a mechanism which allows you to
  control the dependencies within the parent boundary. The parent boundary still gets to decide
  which of these sub-modules will it exports. In this example, `Articles` and `Accounts` are
  exported, while `Repo` isn't. The sub-boundaries decide what will they depend on themselves.

  ### Dependencies

  A boundary may only depend on its direct siblings, its parent, and any dependency of its parent.

  In other words, a boundary inherits all the constraints of its parent, and it can't bring in any
  new deps. However, a boundary doesn't inherit its parent's deps by default. Instead, it has to
  declare these deps explicitly.

  A boundary can't depend on its descendants. However, the modules from the parent boundary are
  implicitly allowed to use the exports of the child sub-boundaries (but not of the descendants).

  #### Cross-app dependencies

  If the external lib defines its own boundaries, you can only depend on the top-level boundaries.
  If implicit boundaries are used (app doesn't define its own boundaries), all such boundaries
  are considered as top-level, and you can depend on any boundary from such app.

  ### Promoting boundaries to top-level

  It's possible to turn a nested boundary into a top-level boundary:

  ```
  defmodule BlogEngine.Application do
    use Boundary, top_level?: true
  end
  ```

  In this case `BlogEngine.Application` is not considered to be a sub-boundary of `BlogEngine`.
  This option is discouraged because it introduces a mismatch between the namespace hierarchy,
  and the logical model. Conceptually, `BlogEngine.Application` is a sibling of `BlogEngine` and
  `BlogEngineWeb`, but in the namespace hierarchy it usually resides under the context namespace
  (courtesy of generators such as `mix new` and `mix phx.new`).

  An alternative is to rename the module to `MySystemApp`:

  ```
  defmodule MySystemApp do
    use Application
    use Boundary, deps: [MySystem, MySystemWeb]
  end
  ```

  That way the namespace hierarchy will match the logical model.
  """

  require Boundary.Definition
  alias Boundary.{Definition, View}

  Code.eval_quoted(Definition.generate(deps: [], exports: []), [], __ENV__)

  @type t :: %{
          name: name,
          ancestors: [name],
          deps: [{name, mode}],
          exports: [module],
          externals: [atom],
          extra_externals: [atom],
          externals_mode: :strict | :regular,
          ignore?: boolean,
          file: String.t(),
          line: pos_integer,
          implicit?: boolean,
          app: atom,
          errors: [term]
        }

  @type view :: map

  @type name :: module
  @type mode :: :compile | :runtime

  @type call :: %{
          callee: mfa,
          callee_module: module,
          caller: mfa,
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

  @doc false
  defmacro __using__(opts), do: Definition.generate(opts)

  @spec view(atom) :: view
  def view(app), do: View.build(app)

  @doc """
  Returns definitions of all boundaries.

  The result will include boundaries from listed externals, as well as implicit boundaries.

  You shouldn't access the data in this result directly, as it may change significantly without warnings. Use exported
  functions of this module to acquire the information you need.
  """
  @spec all(view) :: [t]
  def all(view), do: Map.values(view.classifier.boundaries)

  @doc """
  Returns the names of all boundaries.

  The result will include boundaries from listed externals, as well as implicit boundaries.
  """
  @spec all_names(view) :: [name]
  def all_names(view), do: Map.keys(view.classifier.boundaries)

  @doc "Returns the definition of the given boundary."
  @spec fetch!(view, name) :: t
  def fetch!(view, name), do: Map.fetch!(view.classifier.boundaries, name)

  @doc "Returns the definition of the given boundary."
  @spec fetch(view, name) :: {:ok, t} | :error
  def fetch(view, name), do: Map.fetch(view.classifier.boundaries, name)

  @doc "Returns the definition of the given boundary."
  @spec get(view, name) :: t | nil
  def get(view, name), do: Map.get(view.classifier.boundaries, name)

  @doc "Returns definition of the boundary to which the given module belongs."
  @spec for_module(view, module) :: t | nil
  def for_module(view, module) do
    with boundary when not is_nil(boundary) <- Map.get(view.classifier.modules, module),
         do: fetch!(view, boundary)
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
  def protocol_impl?(module), do: function_exported?(module, :__impl__, 1)

  @doc "Returns the immediate parent of the boundary, or nil if the boundary is a top-level boundary."
  @spec parent(view, t) :: t | nil
  def parent(_view, %{ancestors: []}), do: nil
  def parent(view, %{ancestors: [parent_name | _]}), do: fetch!(view, parent_name)

  defmodule Error do
    defexception [:message, :file, :line]
  end
end
