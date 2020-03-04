defmodule Mix.Tasks.Compile.BoundaryTest do
  use Boundary.CompilerCase, async: true
  import Boundary.ProjectTestCase

  setup_all do
    lib_with_boundaries = lib_with_boundaries()
    lib_without_boundaries = lib_without_boundaries()

    project =
      TestProject.create(
        mix_opts: [
          deps: [
            {:"#{lib_with_boundaries.name}", path: "#{Path.absname(lib_with_boundaries.path)}"},
            {:"#{lib_without_boundaries.name}", path: "#{Path.absname(lib_without_boundaries.path)}"}
          ]
        ]
      )

    context = compile_project(project)
    {:ok, context}
  end

  module1 = unique_module_name()

  module_test "in-boundary calls are allowed",
              """
              defmodule #{module1} do
                use Boundary

                defmodule Foo do def fun(), do: Foo.fun() end
                defmodule Bar do def fun(), do: Bar.fun() end
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "top-level dependency module is exported by default",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module2}]
                def fun(), do: #{module2}.fun()
              end

              defmodule #{module2} do
                use Boundary
                def fun(), do: :ok
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "inner module can call a dependency",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module2}]
                defmodule InnerBoundary do
                  def fun(), do: #{module2}.fun()
                end
              end

              defmodule #{module2} do
                use Boundary
                def fun(), do: :ok
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "calls to exported module are allowed",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module2}]
                def fun(), do: #{module2}.Exported.fun()

                defmodule InnerBoundary do def fun(), do: #{module2}.Exported.fun() end
              end

              defmodule #{module2} do
                use Boundary, exports: [Exported]
                defmodule Exported do def fun(), do: :ok end
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test ".{} syntax can be used to specify exports",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module2}]
                def fun1(), do: #{module2}.Inner.Exported1.fun()
                def fun2(), do: #{module2}.Inner.Exported2.fun()
              end

              defmodule #{module2} do
                use Boundary, exports: [Inner.{Exported1, Exported2}]

                defmodule Inner do
                  defmodule Exported1 do def fun(), do: :ok end
                  defmodule Exported2 do def fun(), do: :ok end
                end
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test ".{} syntax can be used to specify deps",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module2}.{Module1, Module2}]
                def fun1(), do: #{module2}.Module1.fun()
                def fun2(), do: #{module2}.Module2.fun()
              end

              defmodule #{module2}.Module1 do
                use Boundary
                def fun(), do: :ok
              end

              defmodule #{module2}.Module2 do
                use Boundary
                def fun(), do: :ok
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "ignored boundary can call anyone",
              """
              defmodule #{module1} do
                use Boundary, ignore?: true
                def fun1(), do: #{module2}.fun()
              end

              defmodule #{module2} do
                use Boundary
                def fun(), do: :ok
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "ignored boundary can be called by anyone",
              """
              defmodule #{module1} do
                use Boundary
                def fun1(), do: #{module2}.fun()
              end

              defmodule #{module2} do
                use Boundary, ignore?: true
                def fun(), do: :ok
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "protocol implementation is by default ignored",
              """
              defmodule #{module1} do
                use Boundary
                defprotocol SomeProtocol do def foo(bar) end
              end

              defmodule #{module2} do
                use Boundary
                def fun(), do: :ok
              end

              defimpl #{module1}.SomeProtocol, for: Any do def foo(), do: #{module2}.fun() end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "protocol implementation can be classified",
              """
              defmodule #{module1} do
                use Boundary
                defprotocol SomeProtocol do def foo(bar) end
              end

              defmodule #{module2} do
                use Boundary
                def fun(), do: :ok
              end

              defimpl #{module1}.SomeProtocol, for: Any do
                use Boundary, classify_to: #{module2}
                def foo(), do: #{module1}.fun()
              end
              """ do
    assert [warning] = warnings
    assert warning.message == "forbidden call to #{unquote(module1)}.fun/0"
    assert warning.explanation == "(calls from #{unquote(module2)} to #{unquote(module1)} are not allowed)"
  end

  module1 = unique_module_name()

  module_test "all boundaries must be classified",
              """
              defmodule #{module1} do end
              """ do
    assert [warning] = warnings
    assert warning.message == "#{unquote(module1)} is not included in any boundary"
  end

  module1 = unique_module_name()

  module_test "dep must be a known boundary",
              """
              defmodule #{module1} do use Boundary, deps: [NoSuchBoundary] end
              """ do
    assert warnings == [%{line: 1, message: "unknown boundary NoSuchBoundary is listed as a dependency"}]
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "dep can't be an ignored boundary",
              """
              defmodule #{module1} do use Boundary, deps: [#{module2}] end
              defmodule #{module2} do use Boundary, ignore?: true end
              """ do
    assert warnings == [%{line: 1, message: "ignored boundary #{unquote(module2)} is listed as a dependency"}]
  end

  module1 = unique_module_name()
  module2 = unique_module_name()
  module3 = unique_module_name()

  module_test "dep cycles are not allowed",
              """
              defmodule #{module1} do use Boundary, deps: [#{module2}] end
              defmodule #{module2} do use Boundary, deps: [#{module3}] end
              defmodule #{module3} do use Boundary, deps: [#{module1}] end
              """,
              context do
    # we're not verifying the actual printed cycle, because the displayed order is not stable
    assert context.output =~ "dependency cycle found"
  end

  module1 = unique_module_name()

  module_test "export must be an existing module",
              """
              defmodule #{module1} do use Boundary, exports: [NoSuchModule] end
              """ do
    assert warnings == [%{line: 1, message: "unknown module #{unquote(module1)}.NoSuchModule is listed as an export"}]
  end

  module1 = unique_module_name()

  module_test "export can't be from another boundary",
              """
              defmodule #{module1} do
                use Boundary, exports: [Inner]
                defmodule Inner do use Boundary end
              end
              """ do
    assert warnings == [
             %{
               line: 2,
               message: "module #{unquote(module1)}.Inner can't be exported because it's not a part of this boundary"
             }
           ]
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "can't depend on an undeclared dep",
              """
              defmodule #{module1} do
                use Boundary
                def fun(), do: #{module2}.fun()
              end

              defmodule #{module2} do
                use Boundary
                def fun(), do: :ok
              end
              """ do
    assert [warning] = warnings
    assert warning.message == "forbidden call to #{unquote(module2)}.fun/0"
    assert warning.explanation == "(calls from #{unquote(module1)} to #{unquote(module2)} are not allowed)"
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "can't use unexported module",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module2}]
                def fun(), do: #{module2}.Inner.fun()
              end

              defmodule #{module2} do
                use Boundary
                defmodule Inner do def fun(), do: :ok end
              end
              """ do
    assert [warning] = warnings
    assert warning.message == "forbidden call to #{unquote(module2)}.Inner.fun/0"

    assert warning.explanation ==
             "(module #{unquote(module2)}.Inner is not exported by its owner boundary #{unquote(module2)})"
  end

  module1 = unique_module_name()

  module_test "inner boundary is treated as a top-level one",
              """
              defmodule #{module1} do
                use Boundary
                def fun(), do: #{module1}.Inner.fun()

                defmodule Inner do
                  use Boundary
                  def fun(), do: :ok
                end
              end
              """ do
    assert [warning] = warnings
    assert warning.message == "forbidden call to #{unquote(module1)}.Inner.fun/0"
    assert warning.explanation == "(calls from #{unquote(module1)} to #{unquote(module1)}.Inner are not allowed)"
  end

  module1 = unique_module_name()

  module_test "if no dep from external is used, all calls to that external are permitted",
              """
              defmodule #{module1} do
                use Boundary, deps: []
                def fun1(), do: LibWithBoundaries.Boundary1.fun()
                def fun2(), do: LibWithoutBoundaries.Module1.fun()
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()

  module_test "calls to undeclared external deps are not allowed in strict mode",
              """
              defmodule #{module1} do
                use Boundary, deps: [], externals_mode: :strict
                def fun1(), do: LibWithBoundaries.Boundary1.fun()
                def fun2(), do: LibWithoutBoundaries.Module1.fun()
              end
              """ do
    assert [warning1, warning2] = warnings

    assert warning1.message == "forbidden call to LibWithBoundaries.Boundary1.fun/0"
    assert warning1.explanation == "(calls from #{unquote(module1)} to LibWithBoundaries.Boundary1 are not allowed)"

    assert warning2.message == "forbidden call to LibWithoutBoundaries.Module1.fun/0"
    assert warning2.explanation == "(calls from #{unquote(module1)} to LibWithoutBoundaries.Module1 are not allowed)"
  end

  module1 = unique_module_name()

  module_test "can depend on a boundary from an external",
              """
              defmodule #{module1} do
                use Boundary, deps: [LibWithBoundaries.Boundary1, LibWithoutBoundaries.Module1]
                def fun1(), do: LibWithBoundaries.Boundary1.fun()
                def fun2(), do: LibWithoutBoundaries.Module1.fun()
                def fun3(), do: LibWithoutBoundaries.Module1.Module2.fun()
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()

  module_test "when depending on an external boundary, calls to other boundaries from that external are not permitted",
              """
              defmodule #{module1} do
                use Boundary, deps: [LibWithBoundaries.Boundary1, LibWithoutBoundaries.Module1]
                def fun1(), do: LibWithBoundaries.Boundary2.fun()
                def fun2(), do: LibWithoutBoundaries.Module4.fun()
              end
              """ do
    assert [warning1, warning2] = warnings

    assert warning1.message == "forbidden call to LibWithBoundaries.Boundary2.fun/0"
    assert warning1.explanation == "(calls from #{unquote(module1)} to LibWithBoundaries.Boundary2 are not allowed)"

    assert warning2.message == "forbidden call to LibWithoutBoundaries.Module4.fun/0"
    assert warning2.explanation == "(calls from #{unquote(module1)} to LibWithoutBoundaries.Module4 are not allowed)"
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "implicit boundaries are built from all deps of this project boundaries",
              """
              defmodule #{module1} do
                use Boundary, deps: [LibWithoutBoundaries.Module1]
                def fun(), do: LibWithoutBoundaries.Module1.Module2.Module3.fun()
              end

              defmodule #{module2} do
                use Boundary, deps: [LibWithoutBoundaries.Module1.Module2.Module3]
              end
              """ do
    assert [warning] = warnings

    assert warning.message == "forbidden call to LibWithoutBoundaries.Module1.Module2.Module3.fun/0"

    assert warning.explanation ==
             "(calls from #{unquote(module1)} to LibWithoutBoundaries.Module1.Module2.Module3 are not allowed)"
  end

  module1 = unique_module_name()

  module_test "compile-time dependencies are allowed at compile time, but not at runtime",
              """
              defmodule #{module1} do
                use Boundary, deps: [{LibWithBoundaries.Boundary2, :compile}]
                require LibWithBoundaries.Boundary2

                LibWithBoundaries.Boundary2.fun()
                def fun() do
                  LibWithBoundaries.Boundary2.macro()
                  LibWithBoundaries.Boundary2.fun()
                end
              end
              """ do
    assert [warning] = warnings
    assert warning.message == "forbidden call to LibWithBoundaries.Boundary2.fun/0"
    assert warning.explanation == "(calls from #{unquote(module1)} to LibWithBoundaries.Boundary2 are not allowed)"
    assert warning.line == 8
  end

  defp lib_with_boundaries do
    lib = TestProject.create()

    File.write!(
      Path.join([lib.path, "lib", "code.ex"]),
      """
      defmodule LibWithBoundaries.Boundary1 do
        use Boundary, deps: [], exports: []
        def fun(), do: :ok

        defmodule Submodule do def fun(), do: :ok end
      end

      defmodule LibWithBoundaries.Boundary2 do
        use Boundary, deps: [], exports: []
        def fun(), do: :ok
        defmacro macro(), do: :ok
      end
      """
    )

    lib
  end

  defp lib_without_boundaries do
    lib = TestProject.create(mix_opts: [deps: [], compilers: []])

    File.write!(
      Path.join([lib.path, "lib", "code.ex"]),
      """
      defmodule LibWithoutBoundaries.Module1 do
        def fun(), do: :ok

        defmodule Module2 do
          def fun(), do: :ok

          defmodule Module3 do
            def fun(), do: :ok
          end
        end
      end

      defmodule LibWithoutBoundaries.Module4 do
        def fun(), do: :ok
      end
      """
    )

    lib
  end
end
