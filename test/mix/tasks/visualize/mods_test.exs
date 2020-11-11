defmodule Mix.Tasks.Boundary.Visualize.ModsTest do
  use ExUnit.Case, async: false
  alias Boundary.TestProject

  test "produces the expected output" do
    Mix.shell(Mix.Shell.Quiet)
    Logger.disable(self())

    TestProject.in_project(fn project ->
      File.write!(
        Path.join([project.path, "lib", "source.ex"]),
        """
        defmodule Foo do
          use Boundary, deps: [Bar]

          def fun1, do: Bar.Mod.fun()

          def fun2, do: :ok

          defmodule Mod1 do
            def fun, do: Mod2.fun()
          end

          defmodule Mod2 do
            def fun, do: :ok
          end
        end

        defmodule Bar do
          use Boundary, exports: [Mod]

          defmodule Mod do
            def fun, do: :ok
          end
        end
        """
      )

      TestProject.run_task("compile")
      Mix.shell(Mix.Shell.Process)

      assert TestProject.run_task("boundary.visualize.mods", ~w/Foo Bar/).output ==
               """
               digraph {
                 label="";
                 labelloc=top;
                 rankdir=LR;

                 "Foo" -> "Bar.Mod";

                 subgraph cluster_0 {
                   label="Boundary Bar";
                   labelloc=top;
                   rankdir=LR;

                   "Bar.Mod" [shape=box, label=Mod];
                 }

                 subgraph cluster_1 {
                   label="Boundary Foo";
                   labelloc=top;
                   rankdir=LR;

                   "Foo" [shape=box, label=Foo];
                 }
               }
               """
    end)
  end
end
