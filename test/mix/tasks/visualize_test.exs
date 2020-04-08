defmodule Mix.Tasks.Boundary.VisualizeTest do
  use ExUnit.Case, async: false
  alias Boundary.TestProject

  test "produces the expected files output" do
    Mix.shell(Mix.Shell.Process)
    Logger.disable(self())

    TestProject.run_task("boundary.visualize")

    test_output_file(
      Path.join([File.cwd!(), "dot", "Test.Graph.dot"]),
      """
      digraph {
        A -> B
        A -> C
        B -> C [style = dotted]

        label=\"Test.Graph\";
        labelloc=top;
      }
      """
    )
  end

  def test_output_file(path, content) do
    assert File.exists?(path)
    assert File.read!(path) =~ content
  end
end
