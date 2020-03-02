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
