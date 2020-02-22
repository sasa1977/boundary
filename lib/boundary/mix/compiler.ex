defmodule Boundary.Mix.Compiler do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  def check(application, calls) do
    Boundary.errors(application, calls)
    |> Stream.map(&to_diagnostic_error/1)
    |> Enum.sort_by(&{&1.file, &1.position})
  rescue
    e in Boundary.Definition.Error ->
      [diagnostic(e.message, file: e.file, position: e.line)]
  end

  defp to_diagnostic_error({:unclassified_module, module}),
    do: diagnostic("#{inspect(module)} is not included in any boundary", file: module_source(module))

  defp to_diagnostic_error({:unknown_dep, dep}) do
    diagnostic("unknown boundary #{inspect(dep.name)} is listed as a dependency", file: dep.file, position: dep.line)
  end

  defp to_diagnostic_error({:ignored_dep, dep}) do
    diagnostic("ignored boundary #{inspect(dep.name)} is listed as a dependency", file: dep.file, position: dep.line)
  end

  defp to_diagnostic_error({:cycle, cycle}) do
    cycle = cycle |> Stream.map(&inspect/1) |> Enum.join(" -> ")
    diagnostic("dependency cycle found:\n#{cycle}\n")
  end

  defp to_diagnostic_error({:invalid_call, %{type: :invalid_cross_boundary_call} = error}) do
    {m, f, a} = error.callee

    message =
      "forbidden call to #{Exception.format_mfa(m, f, a)}\n" <>
        "  (calls from #{inspect(error.from_boundary)} to #{inspect(error.to_boundary)} are not allowed)\n" <>
        "  (call originated from #{inspect(error.caller)})"

    diagnostic(message, file: error.file, position: error.line)
  end

  defp to_diagnostic_error({:invalid_call, %{type: :not_exported} = error}) do
    {m, f, a} = error.callee

    message =
      "forbidden call to #{Exception.format_mfa(m, f, a)}\n" <>
        "  (module #{inspect(m)} is not exported by its owner boundary #{inspect(error.boundary)})\n" <>
        "  (call originated from #{inspect(error.caller)})"

    diagnostic(message, file: error.file, position: error.line)
  end

  defp module_source(module) do
    module.module_info(:compile)
    |> Keyword.fetch!(:source)
    |> to_string()
    |> Path.relative_to_cwd()
  catch
    _, _ -> ""
  end

  def diagnostic(message, opts \\ []) do
    %Mix.Task.Compiler.Diagnostic{
      compiler_name: "boundary",
      details: nil,
      file: "unknown",
      message: message,
      position: nil,
      severity: :warning
    }
    |> Map.merge(Map.new(opts))
  end
end
