defmodule Boundary.TestProject do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Readability.Specs
  def mix!(project, args) do
    {:ok, output} = mix(project, args)
    output
  end

  def mix(project, args) do
    case System.cmd("mix", args, stderr_to_stdout: true, cd: project.path) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, output}
    end
  end

  def compile(project), do: mix(project, ["do", "deps.get,", "compile"])

  def compile!(project) do
    {:ok, output} = compile(project)
    output
  end

  def create(opts \\ []) do
    File.mkdir_p("tmp")

    project_name = "test_project_#{:erlang.unique_integer(~w/positive monotonic/a)}"
    project_path = Path.join("tmp", project_name)

    File.rm_rf(project_path)

    {_, 0} = System.cmd("mix", ~w/new #{project_name}/, cd: "tmp")
    project = %{name: project_name, path: project_path}
    reinitialize(project, opts)

    ExUnit.Callbacks.on_exit(fn -> File.rm_rf(project_path) end)
    project
  end

  def reinitialize(project, opts \\ []) do
    File.write!(Path.join(project.path, "mix.exs"), mix_exs(project.name, Keyword.get(opts, :mix_opts, [])))
    File.rm_rf(Path.join(project.path, "lib"))
    File.mkdir_p!(Path.join(project.path, "lib"))
  end

  defp mix_exs(project_name, opts) do
    """
    defmodule #{Macro.camelize(project_name)}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{project_name},
          version: "0.1.0",
          elixir: "~> 1.10",
          start_permanent: Mix.env() == :prod,
          deps: deps(),
          compilers: #{inspect(Keyword.get(opts, :compilers, [:boundary]))} ++ Mix.compilers()
        ] ++ #{inspect(Keyword.get(opts, :project_opts, []))}
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      defp deps do
        #{inspect(Keyword.get(opts, :deps, [{:boundary, path: "../.."}]))}
      end
    end
    """
  end
end
