defmodule Boundary.MixCompiler do
  @moduledoc false

  def check(application \\ Boundary.application()) do
    with {:error, error} <- Boundary.Checker.check(application),
         do: {:error, diagnostic_errors(error)}
  end

  defp diagnostic_errors(error) when is_binary(error), do: raise(error)
  defp diagnostic_errors(error), do: Enum.sort_by(to_diagnostic_errors(error), &{&1.file, &1.position})

  defp to_diagnostic_errors({:duplicate_boundaries, boundaries}),
    do: Enum.map(boundaries, &diagnostic("#{inspect(&1)} is declared as a boundary more than once"))

  defp to_diagnostic_errors({:unclassified_modules, modules}),
    do: Enum.map(modules, &diagnostic("#{inspect(&1)} is not included in any boundary", file: module_source(&1)))

  defp to_diagnostic_errors({:invalid_deps, boundaries}),
    do: Enum.map(boundaries, &diagnostic("#{inspect(&1)} is listed as a dependency but not declared as a boundary"))

  defp to_diagnostic_errors({:unused_boundaries, boundaries}),
    do: Enum.map(boundaries, &diagnostic("boundary #{inspect(&1)} doesn't include any module"))

  defp to_diagnostic_errors({:cycles, cycles}) do
    cycles =
      cycles
      |> Stream.map(fn cycle -> cycle |> Stream.map(&inspect/1) |> Enum.join(" -> ") end)
      |> Stream.map(&"  #{&1}")
      |> Enum.join("\n")

    [diagnostic("dependency cycles found:\n#{cycles}\n")]
  end

  defp to_diagnostic_errors({:invalid_calls, calls}), do: Enum.map(calls, &invalid_call_error/1)

  defp invalid_call_error(%{type: :invalid_cross_boundary_call} = error) do
    {m, f, a} = error.callee

    message =
      "forbidden call to #{Exception.format_mfa(m, f, a)}\n" <>
        "  (calls from #{inspect(error.from_boundary)} to #{inspect(error.to_boundary)} are not allowed)"

    diagnostic(message, file: error.file, position: error.line)
  end

  defp invalid_call_error(%{type: :not_exported} = error) do
    {m, f, a} = error.callee

    message =
      "forbidden call to #{Exception.format_mfa(m, f, a)}\n" <>
        "  (module #{inspect(m)} is not exported by its owner boundary #{inspect(error.boundary)})"

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
      file: "boundaries.exs",
      message: message,
      position: nil,
      severity: :warning
    }
    |> Map.merge(Map.new(opts))
  end
end
