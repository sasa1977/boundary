defmodule BoundaryTest do
  use ExUnit.Case, async: true

  defprotocol SomeProtocol do
    def foo(bar)
  end

  describe "errors" do
    test "returns empty list on empty app" do
      assert check(modules: [], calls: []) == []
    end

    test "returns empty list if all calls are valid" do
      assert check(
               modules: [
                 {Foo, boundary: [deps: [Baz]]},
                 Foo.Bar,
                 {Baz, boundary: [exports: [Qux]]},
                 Baz.Qux,
                 {Ignored, boundary: [ignore?: true]},
                 {Classified, protocol_impl?: true, boundary: [classify_to: Foo]},
                 {ProtocolImpl, protocol_impl?: true}
               ],
               calls: [
                 {Foo, Baz},
                 {Foo.Bar, Baz},
                 {Foo, Baz.Qux},
                 {Ignored, Foo},
                 {Enumerable.Classified, Baz},
                 {Enumerable.ProtocolImpl, Foo}
               ]
             ) == []
    end

    test "includes call to undeclared dep" do
      assert [error] = check(modules: [{Foo, boundary: []}, {Bar, boundary: []}], calls: [{Foo, Bar}])

      assert {:invalid_call,
              %{
                from_boundary: Foo,
                to_boundary: Bar,
                caller: Foo,
                callee: {Bar, :fun, 1},
                type: :invalid_cross_boundary_call
              }} = error
    end

    test "includes call to unexported module" do
      assert [error] =
               check(
                 modules: [{Foo, boundary: [deps: [Bar]]}, {Bar, boundary: []}, Bar.Baz],
                 calls: [{Foo, Bar.Baz}]
               )

      assert {:invalid_call,
              %{
                from_boundary: Foo,
                to_boundary: Bar,
                caller: Foo,
                callee: {Bar.Baz, :fun, 1},
                type: :not_exported
              }} = error
    end

    test "treats inner boundary as a top-level one" do
      assert [error] =
               check(
                 modules: [{Foo, boundary: [deps: [Baz]]}, {Foo.Bar, boundary: []}, {Baz, boundary: []}],
                 calls: [{Foo.Bar, Baz}]
               )

      assert {:invalid_call, %{from_boundary: Foo.Bar, to_boundary: Baz}} = error
    end

    test "includes unclassified modules" do
      assert [error1, error2] = check(modules: [{Foo, boundary: []}, Bar, Foo.Bar, Baz, Foo.Baz])
      assert error1 == {:unclassified_module, Bar}
      assert error2 == {:unclassified_module, Baz}
    end

    test "doesn't include unclassified protocol implementations" do
      assert check(modules: [{Foo, boundary: []}, {Bar, [protocol_impl?: true]}]) == []
    end

    test "includes unknown boundaries in deps" do
      assert [error] = check(modules: [{Foo, boundary: [deps: [Bar]]}])
      assert {:unknown_dep, %{name: Bar}} = error
    end

    test "includes ignored boundaries in deps" do
      assert [error] = check(modules: [{Foo, boundary: [deps: [Bar]]}, {Bar, boundary: [ignore?: true]}])
      assert {:ignored_dep, %{name: Bar}} = error
    end

    test "includes cycles" do
      modules = [
        {Foo, boundary: [deps: [Bar]]},
        {Bar, boundary: [deps: [Baz]]},
        {Baz, boundary: [deps: [Foo]]}
      ]

      assert check(modules: modules) == [{:cycle, [Foo, Bar, Baz, Foo]}]
    end
  end

  defp check(opts) do
    modules = def_modules(Keyword.get(opts, :modules, []))
    spec = Boundary.Definition.spec(modules)

    Boundary.errors(
      spec,
      opts |> Keyword.get(:calls, []) |> Enum.map(&call/1)
    )
  end

  defp def_modules(modules), do: Enum.map(modules, &define_module/1)

  defp define_module(module) when is_atom(module), do: define_module({module, []})

  defp define_module({module, opts}) do
    boundary_opts = Keyword.get(opts, :boundary)

    quoted =
      if Keyword.get(opts, :protocol_impl?) do
        quote bind_quoted: [module: module, boundary_opts: boundary_opts] do
          defimpl SomeProtocol, for: module do
            if not is_nil(boundary_opts), do: use(Boundary, boundary_opts)
            def foo(_), do: :ok
          end
        end
      else
        quote bind_quoted: [module: module, boundary_opts: boundary_opts] do
          defmodule module do
            if not is_nil(boundary_opts), do: use(Boundary, boundary_opts)
          end
        end
      end

    {{:module, module, _code, _}, _bindings} = Code.eval_quoted(quoted)

    on_exit(fn ->
      :code.delete(module)
      :code.purge(module)
    end)

    module
  end

  defp call({from, to}) do
    %{
      callee: {to, :fun, 1},
      callee_module: to,
      caller_module: from,
      file: "nofile",
      line: 1
    }
  end
end
