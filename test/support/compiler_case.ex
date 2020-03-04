defmodule Boundary.CompilerCase do
  @moduledoc """
  This is a special case template made for the purpose of compiler tests.

  The challenge of compiler test is that we want to perform many mix compilations, which makes the tests very slow. To
  address this, this case template takes a somewhat different approach, which allows us to define multiple tests which,
  use custom Elixir code, while the mix compilation is executed only once for all of the tests.

  This approach has its set of problems, as can be seen from the `Mix.Tasks.Compile.BoundaryTest` code, but it gives us
  a solid compromise, allowing us to test the full feature, while keeping the test execution time fairly low.
  """

  # credo:disable-for-this-file Credo.Check.Readability.Specs
  use ExUnit.CaseTemplate
  alias Boundary.TestProject

  using do
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

      case TestProject.compile(project) do
        {:ok, output} -> %{warnings: unquote(__MODULE__).warnings(output), output: output}
        {:error, output} -> raise ExUnit.AssertionError, message: output
      end
    end
  end

  defmacro module_test(desc, code, context \\ quote(do: _), do: block) do
    file = "file_#{:erlang.unique_integer([:positive, :monotonic])}.ex"

    quote do
      @tests {unquote(file), unquote(code)}

      test unquote(desc), unquote(context) = context do
        var!(warnings) =
          context.warnings
          |> Enum.filter(&(&1.file == unquote(file)))
          |> Enum.map(&Map.delete(&1, :file))

        # dummy expression to suppress warnings if `warnings` is not used
        _ = var!(warnings)

        unquote(block)
      end
    end
  end

  def unique_module_name, do: "Module#{:erlang.unique_integer([:positive, :monotonic])}"

  @doc false
  def warnings(output) do
    output
    |> String.split(~r/\n|\r/)
    |> Stream.map(&String.trim/1)
    |> Stream.chunk_every(4, 1)
    |> Stream.filter(&match?("warning: " <> _, hd(&1)))
    |> Enum.map(fn ["warning: " <> warning, line_2, line_3, line_4] ->
      if(String.starts_with?(line_2, "("),
        do: Map.merge(%{explanation: line_2, callee: line_3}, location(line_4)),
        else: location(line_2)
      )
      |> Map.put(:message, String.trim(warning))
    end)
  end

  defp location(location) do
    case String.split(location, ":") do
      [file] -> %{file: Path.basename(file), line: nil}
      [file, line] -> %{file: Path.basename(file), line: String.to_integer(line)}
      _ -> %{file: nil, line: nil}
    end
  end
end
