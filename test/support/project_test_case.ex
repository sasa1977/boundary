defmodule Boundary.ProjectTestCaseTemplate do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Readability.Specs
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__)
    end
  end

  setup_all do
    {:ok, %{project: new_project()}}
  end

  setup context do
    File.write!(Path.join(context.project.path, "mix.exs"), mix_exs(context.project.name))
    reinitialize_folder(Path.join(context.project.path, "lib"))
  end

  def mix!(path, args) do
    {output, 0} = mix(path, args)
    output
  end

  def mix(path, args),
    do: System.cmd("mix", args, stderr_to_stdout: true, cd: path)

  def new_project(opts \\ []) do
    File.mkdir_p("tmp")

    project_name = "test_project_#{:erlang.unique_integer(~w/positive monotonic/a)}"
    project_path = Path.join("tmp", project_name)

    File.rm_rf(project_path)

    {_, 0} = System.cmd("mix", ~w/new #{project_name}/, cd: "tmp")
    File.write!(Path.join(project_path, "mix.exs"), mix_exs(project_name, Keyword.get(opts, :mix_opts, [])))
    reinitialize_folder(Path.join(project_path, "lib"))

    mix!(project_path, ~w/deps.get/)
    mix!(project_path, ~w/deps.compile/)

    on_exit(fn -> File.rm_rf(project_path) end)
    %{name: project_name, path: project_path}
  end

  defp reinitialize_folder(path) do
    File.rm_rf(path)
    File.mkdir_p!(path)
  end

  def mix_exs(project_name, opts \\ []) do
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
        ]
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
