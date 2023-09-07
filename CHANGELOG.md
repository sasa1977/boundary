# 0.10.1

- Improved compiler performance. On a large project (7k+ files, 480k LOC), the running time is reduced from about 50 seconds to about 1 second.

# 0.10.0

- Added the support for ignoring "dirty" xrefs via the `dirty_xrefs` option. See `Boundary` module docs for details.

# 0.9.4

- Properly unload the tracer on compilation error. Fixes crashes in ElixirLS.

# 0.9.3

- Fix inconsistent behaviour in umbrella/poncho projects.

# 0.9.2

- Properly handle sub-boundary exports on mass export
- Improve tracer performance

# 0.9.1

- Remove unwanted cross-module deps

# 0.9.0

- Support exporting modules of sub-boundaries.

## Bugfixes

- Properly handle `:strict` scope in sub-boundaries.
- Remove compilation warnings when the recompiled module has no external calls
- Allow references to protocol implementations from externals
- Fix a compilation crash

# 0.8.0

- Reports forbidden struct expansions (`%Foo{...}`)
- Optionally reports alias references (e.g. `Foo`, `apply(Foo, ...)`). This check is by default disabled, but can be enabled globally or per-boundary with the option `check: [aliases: true]`.

# 0.7.1

- fixes a bug which prevented the project from compiling on a named node

# 0.7.0

## New

- added two mix task `boundary.visualize.mods` and `boundary.visualize.funs` that can help visualizing cross-module and in-module dependencies.

# 0.6.1

- relax Elixir requirement

# 0.6.0

## Breaking

- The `:externals_mode` option is renamed to `type`.
- The `:extra_externals` option is dropped, use `check: [apps: list_of_apps]` instead.
- Global boundary options are now specified via `boundary: [default: default_opts]` in mix project config.
- Diagrams produces by `mix boundary.visualize` won't include boundaries from external apps.
- Non-strict sub-boundaries implicitly inherit ancestors deps.

## Deprecated

- `ignore?: true` is deprecated in favour of `check: [in: false, out: false]`.

## New

- Added `boundary.ex_doc_groups` mix task for generating ex_doc groups for defined boundaries.
- Better support for finer-grained ignoring with `check: [in: boolean, out: boolean]`.
- Support for global default externals checks with `boundary: [default: [check: [apps: apps]]]`.

# 0.5.0

- Support sub-boundaries ([docs](https://hexdocs.pm/boundary/Boundary.html#module-nested-boundaries))
- Support mass export ([docs](https://hexdocs.pm/boundary/Boundary.html#module-mass-exports))
- New boundary.visualize mix task which generates a graphiviz dot file for each non-empty boundary
- Eliminated compile-time dependencies to deps and exports.

# 0.4.4

- Fixed app config bug related to unloading

# 0.4.3

- Fixed a few bugs which were noticed in ElixirLS
- Expanded cache to further reduce check time

# 0.4.2

- Remote calls from macro are treated as compile-time calls.

# 0.4.1

- Fixes false positive report of an unknown external boundary.

# 0.4.0

- Support for permitting dep to be used only at compile time via `deps: [{SomeDep, :compile}]`.
- Support for alias-like grouping (e.g. `deps: [Ecto.{Changeset, Query}]`)
- The boundary compiler now caches boundaries from external dependencies, which significantly reduces check duration in the cases where the client app doesn't need to be fully recompiled.

# 0.3.2

- Eliminates duplicate warnings

# 0.3.1

- Fixed app loading bug which led to some dependencies being missed.

# 0.3.0

- Added support for controlling the usage of external deps. If external dep defines boundaries, the client app can refer to those boundaries. Otherwise, the client app can define implicit boundaries. See [docs](https://hexdocs.pm/boundary/Boundary.html#module-external-dependencies) for details.
- Added `boundary.spec` and `boundary.find_external_deps` mix tasks.
- Manual classification via the `:classify_to` option is now also allowed for mix tasks.
- Stabilized memory usage, reduced disk usage and analysis time. Boundary is still not thoroughly optimized, but it should behave better in larger projects.
- Boundary database files are now stored in the [manifest path](https://hexdocs.pm/mix/Mix.Project.html#manifest_path/1). Previously they were stored in apps `ebin` which means they would be also included in the OTP release.

# 0.2.0

- **[Breaking]** Requires Elixir 1.10 or higher
- **[Breaking]** The `:boundary` compiler should be listed first
- Uses [compilation tracers](https://hexdocs.pm/elixir/Code.html#module-compilation-tracers) instead of mix xref to collect usage

# 0.1.0
