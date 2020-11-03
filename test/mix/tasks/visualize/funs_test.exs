defmodule Mix.Tasks.Boundary.Visualize.FunsTest do
  use ExUnit.Case, async: false
  alias Boundary.TestProject

  test "produces the expected output" do
    Mix.shell(Mix.Shell.Quiet)
    Logger.disable(self())

    TestProject.in_project(fn project ->
      File.write!(
        Path.join([project.path, "lib", "source.ex"]),
        """
        defmodule MyMod do
          def foo do
            bar()
            bar()

            baz(1)
          end

          def bar, do: baz()

          def baz, do: :ok
          def baz(_), do: :ok
        end
        """
      )

      Mix.shell(Mix.Shell.Process)
      output = TestProject.run_task("boundary.visualize.funs", ["MyMod"]).output

      assert output == """
             digraph {
               label="function calls inside MyMod";
               labelloc=top;
               rankdir=LR;

               "bar" [shape="box"];
               "baz" [shape="box"];
               "foo" [shape="box"];

               "bar" -> "baz";
               "foo" -> "bar";
               "foo" -> "baz";
             }
             """
    end)
  end
end
