defmodule Boundary.CompilerTester do
  @moduledoc """
  This is a special helper made for the purpose of compiler tests.

  The challenge of compiler test is that we want to perform many mix compilations, which makes the tests very slow. To
  address this, this module provides a special `module_test` macro which allows us to define multiple tests that will
  evaluate the output of a single compilation.

  This approach has its set of problems, as can be seen from the `Mix.Tasks.Compile.BoundaryTest` code, but it gives us
  a solid compromise, allowing us to test the full feature, while keeping the test execution time fairly low.
  """

  # credo:disable-for-this-file Credo.Check.Readability.Specs
  alias Boundary.TestProject

  defmacro __using__(_opts) do
    quote do
      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :tests, accumulate: true, persist: true)
      import unquote(__MODULE__)
      alias Boundary.TestProject
    end
  end

  defmacro __before_compile__(_) do
    quote do
      defp __tests__, do: @tests
    end
  end

  defmacro compile_project(project) do
    quote do
      project = unquote(project)
      for {file, code} <- __tests__(), do: File.write!(Path.join([project.path, "lib", file]), code)

      TestProject.compile()
    end
  end

  defmacro module_test(desc, code, context \\ quote(do: _), do: block) do
    file = "file_#{:erlang.unique_integer([:positive, :monotonic])}.ex"

    quote do
      @tests {unquote(file), unquote(code)}

      test unquote(desc), unquote(context) = context do
        var!(warnings) =
          context.warnings
          |> Enum.filter(&(&1.file == "lib/#{unquote(file)}"))
          |> Enum.map(&Map.delete(&1, :file))
          |> Enum.map(&%{&1 | message: &1.message})

        # dummy expression to suppress warnings if `warnings` is not used
        _ = var!(warnings)

        unquote(block)
      end
    end
  end

  def unique_module_name, do: "Module#{:erlang.unique_integer([:positive, :monotonic])}"
end
