defmodule Boundary do
  @moduledoc false

  require Boundary.Definition
  Boundary.Definition.generate(deps: [], exports: [Definition, MixCompiler])

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      require Boundary.Definition
      Boundary.Definition.generate(opts)
    end
  end

  def application() do
    calls =
      Mix.Tasks.Xref.calls()
      |> Stream.map(fn %{callee: {mod, _fun, _arg}} = entry -> Map.put(entry, :callee_module, mod) end)
      |> Enum.reject(&(&1.callee_module == &1.caller_module))
      |> resolve_duplicates()

    modules =
      calls
      |> Stream.map(& &1.caller_module)
      |> MapSet.new()

    boundaries =
      modules
      |> Stream.map(&{&1, Boundary.Definition.get(&1)})
      |> Enum.reject(&match?({_module, nil}, &1))
      |> Map.new()

    %{modules: modules, boundaries: boundaries, calls: calls}
  end

  defp resolve_duplicates(calls) do
    # If there is a call from `Foo.Bar`, xref may include two entries, one with `Foo` and another with `Foo.Bar` as the
    # caller. In such case, we'll consider only the call with the "deepest" caller (i.e. `Foo.Bar`).

    calls
    |> Enum.group_by(&{&1.file, &1.line, &1.callee})
    |> Enum.map(fn {_, calls} -> Enum.max_by(calls, &String.length(inspect(&1.caller_module))) end)
  end
end
