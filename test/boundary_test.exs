defmodule BoundaryTest do
  # credo:disable-for-this-file Credo.Check.Readability.Specs

  use ExUnit.Case, async: true

  defprotocol SomeProtocol do
    def foo(bar)
  end

  describe "errors" do
    test "returns empty list on empty app" do
      assert check(modules: [], calls: []) == []
    end

    test "doesn't include in-boundary calls" do
      assert check(
               modules: [{Foo, boundary: []}, Foo.Bar, Foo.Baz],
               calls: [{Foo, Foo, Bar}, {Foo.Bar, Foo}, {Foo.Bar, Foo.Baz}]
             ) == []
    end

    test "doesn't include call to top-level dependency module" do
      assert check(
               modules: [{Foo, boundary: [deps: [Bar]]}, {Bar, boundary: []}],
               calls: [{Foo, Bar}]
             ) == []
    end

    test "doesn't include call from an inner module to dependency module" do
      assert check(
               modules: [{Foo, boundary: [deps: [Baz]]}, Foo.Bar, {Baz, boundary: []}],
               calls: [{Foo.Bar, Baz}]
             ) == []
    end

    test "doesn't include call to exported dependency module" do
      assert check(
               modules: [{Foo, boundary: [deps: [Bar]]}, {Bar, boundary: [exports: [Baz]]}, Bar.Baz],
               calls: [{Foo, Bar.Baz}]
             ) == []
    end

    test "doesn't include call to non-listed external" do
      assert check(modules: [{Foo, boundary: []}], calls: [{Foo, Mix}]) == []
    end

    test "doesn't include call to allowed external" do
      assert check(
               modules: [{Foo, boundary: [deps: [Mix]]}],
               calls: [{Foo, Mix}, {Foo, Mix.Project}]
             ) == []
    end

    test "doesn't include call to an ignored boundary" do
      assert check(
               modules: [{Foo, boundary: []}, {Bar, boundary: [ignore?: true]}],
               calls: [{Foo, Bar}]
             ) == []
    end

    test "doesn't include call from an ignored boundary" do
      assert check(
               modules: [{Foo, boundary: []}, {Bar, boundary: [ignore?: true]}],
               calls: [{Bar, Foo}]
             ) == []
    end

    test "doesn't include call from an unclassified protocol implementation" do
      assert check(
               modules: [{Foo, boundary: []}, {Bar, protocol_impl?: true}],
               calls: [{BoundaryTest.SomeProtocol.Bar, Foo}]
             ) == []
    end

    test "doesn't include call from a classified protocol implementation" do
      assert check(
               modules: [{Foo, boundary: []}, {Bar, protocol_impl?: true, boundary: [classify_to: Foo]}],
               calls: [{BoundaryTest.SomeProtocol.Bar, Foo}]
             ) == []
    end

    test "includes call to undeclared dep" do
      assert [{:invalid_call, error}] =
               check(
                 modules: [{Foo, boundary: []}, {Bar, boundary: []}],
                 calls: [{Foo, Bar}]
               )

      assert %{
               from_boundary: Foo,
               to_boundary: Bar,
               caller: Foo,
               callee: {Bar, :fun, 1},
               type: :invalid_cross_boundary_call
             } = error
    end

    test "includes call to unexported module" do
      assert [{:invalid_call, error}] =
               check(
                 modules: [{Foo, boundary: [deps: [Bar]]}, {Bar, boundary: []}, Bar.Baz],
                 calls: [{Foo, Bar.Baz}]
               )

      assert %{
               from_boundary: Foo,
               to_boundary: Bar,
               caller: Foo,
               callee: {Bar.Baz, :fun, 1},
               type: :not_exported
             } = error
    end

    test "includes invalid call from a classified protocol implementation" do
      assert [{:invalid_call, error}] =
               check(
                 modules: [
                   {Foo, boundary: []},
                   {Bar, boundary: []},
                   {Baz, protocol_impl?: true, boundary: [classify_to: Bar]}
                 ],
                 calls: [{BoundaryTest.SomeProtocol.Baz, Foo}]
               )

      assert %{
               from_boundary: Bar,
               to_boundary: Foo,
               caller: BoundaryTest.SomeProtocol.Baz,
               callee: {Foo, :fun, 1},
               type: :invalid_cross_boundary_call
             } = error
    end

    test "includes call to forbidden external" do
      assert [{:invalid_call, error}] =
               check(
                 modules: [{Foo, boundary: [deps: [Mix.Config]]}],
                 calls: [{Foo, Mix.Project, :config}]
               )

      assert %{
               from_boundary: Foo,
               to_boundary: Mix.Project,
               caller: Foo,
               callee: {Mix.Project, :config, 1},
               type: :invalid_external_dep_call
             } = error
    end

    test "includes call to forbidden external via extra_external" do
      assert [{:invalid_call, error}] =
               check(
                 modules: [{Foo, boundary: [extra_externals: [:elixir]]}],
                 calls: [{Foo, IO, :inspect}]
               )

      assert %{
               from_boundary: Foo,
               to_boundary: IO,
               caller: Foo,
               callee: {IO, :inspect, 1},
               type: :invalid_external_dep_call
             } = error
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

    test "includes empty boundaries in deps" do
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
    view = Boundary.build_view(:boundary, modules)

    Boundary.errors(
      view,
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

  defp call({from, to}), do: call({from, to, :fun})

  defp call({from, to, fun}) do
    %{
      callee: {to, fun, 1},
      callee_module: to,
      caller_module: from,
      file: "nofile",
      line: 1
    }
  end
end
