defmodule Boundary.DocTest do
  use ExUnit.Case, async: false
  alias Boundary.TestProject

  test "Does add moduledoc meta when configured to do so" do
    Mix.shell(Mix.Shell.Process)
    Logger.disable(self())

    TestProject.in_project(
      [mix_opts: [project_opts: [boundary: [docs_meta: true]]]],
      fn project ->
        TestProject.run_task("deps.compile")

        File.write!(
          Path.join([project.path, "lib", "source.ex"]),
          """
          defmodule Boundary1 do
            use Boundary
          end
          """
        )

        TestProject.run_task("compile")

        assert {:docs_v1, _, :elixir, _, _, %{boundary: _}, _} = Code.fetch_docs(Boundary1)
      end
    )
  end

  test "Does add moduledoc meta to all modules of a boundary when configured to do so" do
    Mix.shell(Mix.Shell.Process)
    Logger.disable(self())

    TestProject.in_project(
      [mix_opts: [project_opts: [boundary: [docs_meta: true]]]],
      fn project ->
        TestProject.run_task("deps.compile")

        File.write!(
          Path.join([project.path, "lib", "source.ex"]),
          """
          defmodule Boundary1 do
            use Boundary

            defmodule Foo do end
          end
          """
        )

        TestProject.run_task("compile")

        assert {:docs_v1, _, :elixir, _, _, %{boundary: _}, _} = Code.fetch_docs(Boundary1.Foo)
      end
    )
  end

  test "Does not add moduledoc meta when not configured to do so" do
    Mix.shell(Mix.Shell.Process)
    Logger.disable(self())

    TestProject.in_project(
      [mix_opts: [project_opts: [boundary: [docs_meta: false]]]],
      fn project ->
        File.write!(
          Path.join([project.path, "lib", "source.ex"]),
          """
          defmodule Boundary1 do
            use Boundary
          end
          """
        )

        TestProject.run_task("compile")

        {:docs_v1, _, :elixir, _, _, meta, _} = Code.fetch_docs(Boundary1)

        refute Map.has_key?(meta, :boundary)
      end
    )
  end
end
