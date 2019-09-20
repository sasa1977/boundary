defmodule Mix.Tasks.Compile.Boundary do
  # credo:disable-for-this-file Credo.Check.Readability.Specs

  use Boundary, deps: [Boundary]
  use Mix.Task.Compiler

  @moduledoc """
  Verifies cross-module function calls according to defined boundaries.

  This compiler reports all cross-boundary function calls which are not permitted, according to
  the current definition of boundaries. For details on defining boundaries, see the docs for the
  `Boundary` module.

  ## Usage

  Once you have configured the boundaries, you need to include the compiler in `mix.exs`:

  ```
  defmodule MySystem.MixProject do
    # ...

    def project do
      [
        compilers: Mix.compilers() ++ [:boundary],
        # ...
      ]
    end

    # ...
  end
  ```

  When developing a library, it's advised to use this compiler only in `:dev` and `:test`
  environments:

  ```
  defmodule Boundary.MixProject do
    # ...

    def project do
      [
        compilers: Mix.compilers() ++ extra_compilers(Mix.env()),
        # ...
      ]
    end

    # ...

    defp extra_compilers(:prod), do: []
    defp extra_compilers(_env), do: [:boundaries]
  end
  ```

  ## Warnings

  Every invalid cross-boundary call is reported as a compiler warning. Consider the following example:

  ```
  defmodule MySystem.User do
    def auth() do
      MySystemWeb.Endpoint.url()
    end
  end
  ```

  Assuming that calls from `MySystem` to `MySystemWeb` are not allowed, you'll get the following warning:

  ```
  $ mix compile

  warning: forbidden call to MySystemWeb.Endpoint.url/0
    (calls from MySystem to MySystemWeb are not allowed)
    (call originated from MySystem.User)
    lib/my_system/user.ex:3
  ```

  Since the compiler emits warnings, `mix compile` will still succeed, and you can normally start
  your system, even if some boundary rules are violated. The compiler doesn't force you to immediately
  fix these violations, which is a deliberate decision made to avoid disrupting the development flow.

  At the same time, it's worth enforcing boundaries on the CI. This can easily be done by providing
  the `--warnings-as-errors` option to `mix compile`.
  """

  @recursive true

  @impl Mix.Task.Compiler
  def run(argv) do
    errors = Boundary.MixCompiler.check()
    print_diagnostic_errors(errors)
    {status(errors, argv), errors}
  end

  defp status([], _), do: :ok
  defp status([_ | _], argv), do: if(warnings_as_errors?(argv), do: :error, else: :ok)

  defp warnings_as_errors?(argv) do
    {parsed, _argv, _errors} = OptionParser.parse(argv, strict: [warnings_as_errors: :boolean])
    Keyword.get(parsed, :warnings_as_errors, false)
  end

  defp print_diagnostic_errors(errors) do
    if errors != [], do: IO.puts("")
    Enum.each(errors, &print_diagnostic_error/1)
  end

  defp print_diagnostic_error(error) do
    Mix.shell().info([severity(error.severity), error.message, location(error)])
  end

  defp location(error) do
    if error.file != nil and error.file != "" do
      pos = if error.position != nil, do: ":#{error.position}", else: ""
      "\n  #{error.file}#{pos}\n"
    else
      "\n"
    end
  end

  defp severity(severity), do: [:bright, color(severity), "#{severity}: ", :reset]
  defp color(:error), do: :red
  defp color(:warning), do: :yellow
end
