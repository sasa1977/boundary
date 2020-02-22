defmodule Boundary.ProjectTestCaseTemplate do
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__)
    end
  end

  setup_all do
    File.mkdir_p("tmp")

    project_name = "test_project_#{:erlang.unique_integer(~w/positive monotonic/a)}"
    project_path = Path.join("tmp", project_name)

    File.rm_rf(project_path)

    {_, 0} = System.cmd("mix", ~w/new #{project_name}/, cd: "tmp")
    File.write!(Path.join(project_path, "mix.exs"), mix_exs_content())
    reinitialize_folder(Path.join(project_path, "lib"))

    mix!(project_path, ~w/deps.get/)
    mix!(project_path, ~w/deps.compile/)

    on_exit(fn -> File.rm_rf(project_path) end)
    {:ok, %{project_path: project_path}}
  end

  setup context do
    reinitialize_folder(Path.join(context.project_path, "lib"))
  end

  def mix!(path, args) do
    {output, 0} = mix(path, args)
    output
  end

  def mix(path, args),
    do: System.cmd("mix", args, stderr_to_stdout: true, cd: path)

  defp reinitialize_folder(path) do
    File.rm_rf(path)
    File.mkdir_p!(path)
  end

  defp mix_exs_content() do
    """
    defmodule TestProject.MixProject do
      use Mix.Project

      def project do
        [
          app: :test_project,
          version: "0.1.0",
          elixir: "~> 1.10",
          start_permanent: Mix.env() == :prod,
          deps: deps(),
          compilers: [:boundary | Mix.compilers()]
        ]
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      defp deps do
        [
          {:boundary, path: "../.."}
        ]
      end
    end
    """
  end
end
