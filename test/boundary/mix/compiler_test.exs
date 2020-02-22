defmodule Boundary.Mix.CompilerTest do
  use ExUnit.Case, async: true

  defprotocol SomeProtocol do
    def foo(bar)
  end

  describe "check" do
    test "reports no errors on empty app" do
      assert check(modules: [], calls: []) == []
    end

    test "allows valid calls" do
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

    test "disallows call to undeclared dep" do
      assert [error] = check(modules: [{Foo, boundary: []}, {Bar, boundary: []}], calls: [{Foo, Bar}])

      assert error.message <> "\n" ==
               """
               forbidden call to Bar.fun/1
                 (calls from Foo to Bar are not allowed)
                 (call originated from Foo)
               """
    end

    test "disallows call to unexported module" do
      assert [error] =
               check(
                 modules: [{Foo, boundary: [deps: [Bar]]}, {Bar, boundary: []}, Bar.Baz],
                 calls: [{Foo, Bar.Baz}]
               )

      assert error.message <> "\n" ==
               """
               forbidden call to Bar.Baz.fun/1
                 (module Bar.Baz is not exported by its owner boundary Bar)
                 (call originated from Foo)
               """
    end

    test "treats inner boundary as a top-level one" do
      assert [error] =
               check(
                 modules: [{Foo, boundary: [deps: [Baz]]}, {Foo.Bar, boundary: []}, {Baz, boundary: []}],
                 calls: [{Foo.Bar, Baz}]
               )

      assert error.message <> "\n" ==
               """
               forbidden call to Baz.fun/1
                 (calls from Foo.Bar to Baz are not allowed)
                 (call originated from Foo.Bar)
               """
    end

    test "reports unclassified modules" do
      assert [error1, error2] = check(modules: [{Foo, boundary: []}, Bar, Foo.Bar, Baz, Foo.Baz])
      assert error1.message == "Bar is not included in any boundary"
      assert error2.message == "Baz is not included in any boundary"
    end

    test "doesn't report unclassified protocol implementations" do
      assert check(modules: [{Foo, boundary: []}, {Bar, [protocol_impl?: true]}]) == []
    end

    test "reports unknown boundaries in deps" do
      assert [error] = check(modules: [{Foo, boundary: [deps: [Bar]]}])
      assert error.message == "unknown boundary Bar is listed as a dependency"
    end

    test "reports ignored boundaries is deps" do
      assert [error] = check(modules: [{Foo, boundary: [deps: [Bar]]}, {Bar, boundary: [ignore?: true]}])
      assert error.message == "ignored boundary Bar is listed as a dependency"
    end

    test "reports cycles" do
      modules = [
        {Foo, boundary: [deps: [Bar]]},
        {Bar, boundary: [deps: [Baz]]},
        {Baz, boundary: [deps: [Foo]]}
      ]

      assert [error] = check(modules: modules)

      assert error.message ==
               """
               dependency cycle found:
               Foo -> Bar -> Baz -> Foo
               """
    end
  end

  defp check(opts) do
    modules = def_modules(Keyword.get(opts, :modules, []))
    application = Boundary.Definition.boundaries(modules)

    Boundary.Mix.Compiler.check(
      application,
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
