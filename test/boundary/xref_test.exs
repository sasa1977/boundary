defmodule Boundary.XrefTest do
  use ExUnit.Case, async: true
  alias Boundary.Xref

  setup_all do
    File.rm_rf("tmp")
    File.mkdir_p!("tmp")
    on_exit(fn -> File.rm_rf("tmp") end)
  end

  test "records all stored calls" do
    db_path = new_path()
    on_exit(fn -> File.rm_rf(db_path) end)
    Xref.start_link(db_path)

    add_calls([
      {Foo, call({Bar, :fun1, 0})},
      {Foo, call({Baz, :fun2, 0})},
      {Bar, call({Qux, :fun3, 0})}
    ])

    assert [call1, call2, call3] = Xref.calls()

    assert %{caller_module: Foo, callee: {Bar, :fun1, 0}} = call1
    assert %{caller_module: Foo, callee: {Baz, :fun2, 0}} = call2
    assert %{caller_module: Bar, callee: {Qux, :fun3, 0}} = call3
  end

  test "after restart, previous calls are preserved unless the module is rescanned" do
    db_path = new_path()
    on_exit(fn -> File.rm_rf(db_path) end)
    Xref.start_link(db_path)

    add_calls([
      {Foo, call({Bar, :fun1, 0})},
      {Foo, call({Baz, :fun2, 0})},
      {Bar, call({Qux, :fun3, 0})}
    ])

    Xref.flush(db_path, [Foo, Bar, Baz, Qux])
    Xref.stop()
    Xref.start_link(db_path)

    add_calls([{Foo, call({Bar, :fun4, 0})}])
    assert [call1, call2] = Xref.calls()

    assert %{caller_module: Foo, callee: {Bar, :fun4, 0}} = call1
    assert %{caller_module: Bar, callee: {Qux, :fun3, 0}} = call2
  end

  defp call(callee), do: %{callee: callee, file: "nofile", line: 1}

  defp add_calls(calls), do: Enum.each(calls, fn {caller, call} -> Xref.add_call(caller, call) end)

  defp new_path, do: Path.join("tmp", "db_#{:erlang.unique_integer([:positive, :monotonic])}")
end
