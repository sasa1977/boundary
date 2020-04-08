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

          defmodule Repo do end
          defmodule Accounts do
            use Boundary, deps: [Repo]
          end
          defmodule Articles do
            use Boundary, deps: [Repo, Accounts]
          end
        end

        defmodule BlogEngineWeb do
          use Boundary, deps: [BlogEngine], exports: []
        end

        defmodule BlogEngineApp do
          use Boundary, deps: [BlogEngineWeb, BlogEngine], exports: []
        end
        """
      )

      TestProject.run_task("boundary.visualize")

      test_output_file(
        Path.join([project.path, "dot", "app.dot"]),
        """
        digraph {
          BlogEngineApp -> BlogEngine;
          BlogEngineApp -> BlogEngineWeb;
          BlogEngineWeb -> BlogEngine;

          label="test_project_2 application";
          labelloc=top;
        }
        """
      )

      # test_output_file(
      #   Path.join([project.path, "dot", "BlogEngine.dot"]),
      #   """
      #   digraph {
      #     Articles -> Accounts;
      #     Articles -> Repo;
      #     Accounts -> Repo;

      #     label="test_project_2 boundary";
      #     labelloc=top;
      #   }
      #   """
      # )
    end)
  end

  def test_output_file(path, content) do
    assert File.exists?(path)
    assert File.read!(path) =~ content
  end
end
