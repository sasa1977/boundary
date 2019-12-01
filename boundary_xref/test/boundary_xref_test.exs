defmodule BoundaryXrefTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  setup_all do
    File.rm_rf("tmp")
    File.mkdir_p!("tmp")
    on_exit(fn -> File.rm_rf("tmp") end)
  end

  property "properly reports all stored calls" do
    check all callees <- uniq_list_of(atom(:alias)),
              original_callers <- uniq_list_of(atom(:alias)),
              deleted_modules <- uniq_list_of(atom(:alias)),
              callers = original_callers ++ deleted_modules,
              Enum.empty?(MapSet.intersection(MapSet.new(callers), MapSet.new(callees))),
              initial_calls <- calls(callers, callees),
              modified_calls <- calls(original_callers, callees) do
      db_path = new_path()
      on_exit(fn -> File.rm_rf(db_path) end)

      BoundaryXref.start_link(db_path)
      add_calls(initial_calls)

      BoundaryXref.finalize(callers ++ callees)
      recorded_calls = BoundaryXref.calls(db_path)
      assert Enum.sort(recorded_calls) == Enum.sort(initial_calls)

      BoundaryXref.start_link(db_path)
      add_calls(modified_calls)
      BoundaryXref.finalize(original_callers)
      recorded_calls = BoundaryXref.calls(db_path)

      changed_modules =
        modified_calls
        |> Stream.map(fn {caller, _call} -> caller end)
        |> Stream.concat(deleted_modules)
        |> MapSet.new()

      expected_calls =
        initial_calls
        |> Stream.reject(fn {caller, _call} -> MapSet.member?(changed_modules, caller) end)
        |> Enum.concat(modified_calls)

      assert Enum.sort(recorded_calls) == Enum.sort(expected_calls)
    end
  end

  defp calls(callers, callees) do
    if Enum.empty?(callers) or Enum.empty?(callees),
      do: constant([]),
      else: list_of(call(callers, callees))
  end

  defp call(callers, callees) do
    gen all caller <- member_of(callers),
            callee <- member_of(callees),
            caller != callee,
            function <- atom(:alphanumeric),
            arity <- positive_integer(),
            line <- positive_integer() do
      file = "#{Macro.underscore(caller)}"
      call = %{callee: callee, function: function, arity: arity, file: file, line: line}
      {caller, call}
    end
  end

  defp add_calls(calls), do: Enum.each(calls, fn {caller, call} -> BoundaryXref.add_call(caller, call) end)

  defp new_path(), do: Path.join("tmp", "db_#{:erlang.unique_integer([:positive, :monotonic])}")
end
