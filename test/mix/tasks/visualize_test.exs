defmodule Mix.Tasks.Boundary.VisualizeTest do
  use ExUnit.Case, async: false
  alias Boundary.TestProject

  test "produces the expected files output" do
    Mix.shell(Mix.Shell.Process)
    Logger.disable(self())

    TestProject.in_project(fn project ->
      File.write!(
        Path.join([project.path, "lib", "source.ex"]),
        """
        defmodule BlogEngine do
          use Boundary

          defmodule Repo do
            use Boundary
          end

          defmodule Accounts do
            use Boundary, deps: [Repo, {Mix, :compile}]
          end

          defmodule Articles do
            use Boundary, deps: [BlogEngine, Repo, Accounts]
          end
        end

        defmodule BlogEngineWeb do
          use Boundary, deps: [BlogEngine], exports: []
        end

        defmodule BlogEngineApp do
          use Boundary, deps: [BlogEngineWeb, BlogEngine, {Mix, :compile}], exports: []
        end
        """
      )

      TestProject.run_task("boundary.visualize")

      test_output_file(
        Path.join([project.path, "boundary", "app.dot"]),
        """
        digraph {
          label="#{project.app} application";
          labelloc=top;

          "BlogEngine";
          "BlogEngineApp";
          "BlogEngineWeb";

          "BlogEngineApp" -> "BlogEngine";
          "BlogEngineApp" -> "BlogEngineWeb";
          "BlogEngineWeb" -> "BlogEngine";
        }
        """
      )

      test_output_file(
        Path.join([project.path, "boundary", "BlogEngine.dot"]),
        """
        digraph {
          label="BlogEngine boundary";
          labelloc=top;

          "BlogEngine.Accounts";
          "BlogEngine.Articles";
          "BlogEngine.Repo";

          "BlogEngine.Accounts" -> "BlogEngine.Repo";
          "BlogEngine.Articles" -> "BlogEngine.Accounts";
          "BlogEngine.Articles" -> "BlogEngine.Repo";
        }
        """
      )
    end)
  end

  defp test_output_file(path, content) do
    assert File.exists?(path)
    assert File.read!(path) =~ content
  end
end
