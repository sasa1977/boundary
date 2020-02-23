# Boundary

[![hex.pm](https://img.shields.io/hexpm/v/boundary.svg?style=flat-square)](https://hex.pm/packages/boundary)
[![hexdocs.pm](https://img.shields.io/badge/docs-latest-green.svg?style=flat-square)](https://hexdocs.pm/boundary/)
[![Build Status](https://travis-ci.org/sasa1977/boundary.svg?branch=master)](https://travis-ci.org/sasa1977/boundary)

Boundary is a library which helps managing and restraining cross-module dependencies in Elixir projects.

## Warning

This library is experimental, untested, and unstable. Interface might change significantly in the future versions. The code is not well tested or optimized, so you might experience crashes, or significant slowdowns during compilation, especially in larger projects. In addition, be aware that Boundary loads the application and all of its dependencies (recursively) during compilation.

## Documentation

For a detailed reference see docs for [Boundary module](https://hexdocs.pm/boundary/Boundary.html) and [mix compiler](https://hexdocs.pm/boundary/Mix.Tasks.Compile.Boundary.html).

## Basic usage

To use this library, you first need to define the boundaries of your project. A __boundary__ is a named group of one or more modules. Each boundary exports some (but not all!) of its modules, and can depend on other boundaries. During compilation, the boundary compiler will find and report all cross-module function calls which are not permitted according to the boundary configuration.

### Example

The following code defines boundaries for a typical Phoenix based project generated with `mix phx.new`.

```elixir
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

The configuration above defines three boundaries: `MySystem`, `MySystemWeb`, and `MySystem.Application`.

Boundary modules are determined automatically from the boundary name. For example, the `MySystem` boundary contains the `MySystem` module, as well as any module whose name starts with `MySystem.` (e.g. `MySystem.User`, `MySystem.User.Schema`, ...).

The configuration specifies the following rules:

  - Modules residing in the `MySystemWeb` boundary are allowed to invoke functions from modules exported by the `MySystem` boundary.
  - Modules residing in the `MySystem.Application` namespace are allowed to invoke functions from modules exported by `MySystem` and `MySystemWeb` boundaries.

All other cross-boundary calls are not permitted.

Next, you need to add the mix compiler:

```elixir
defmodule MySystem.MixProject do
  use Mix.Project

  def project do
    [
      compilers: [:boundary, :phoenix, :gettext] ++ Mix.compilers(),
      # ...
    ]
  end

  # ...
end
```

Boundary rules are validated during compilation. For example, if we have the following code:

```elixir
defmodule MySystem.User do
  def auth do
    MySystemWeb.Endpoint.url()
  end
end

```

The compiler will emit a warning:

```
$ mix compile

warning: forbidden call to MySystemWeb.Endpoint.url/0
  (calls from MySystem to MySystemWeb are not allowed)
  (call originated from MySystem.User)
  lib/my_system/user.ex:3
```

The complete working example is available [here](demos/my_system).

Because `boundary` is implemented as a mix compiler, it integrates seamlessly with editors which can work with mix compiler. For example, in VS Code with [Elixir LS](https://github.com/JakeBecker/vscode-elixir-ls):

![VS Code warning 1](images/vscode_warning_1.png)

![VS Code warning 2](images/vscode_warning_2.png)

## Roadmap

- [ ] support nested boundaries (defining internal boundaries within a boundary)
- [ ] validate calls to external deps (e.g. preventing `Ecto` usage from `MySystemWeb`, or `Plug` usage from `MySystem`)
- [ ] support Erlang modules

## License

[MIT](LICENSE)
