defmodule Boundary.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :boundary,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: Mix.compilers() ++ extra_compilers(Mix.env()),
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs(),
      dialyzer: dialyzer(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:stream_data, "~> 0.4.0", only: :test},
      {:dialyxir, "~> 0.5", only: :dev, runtime: false},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:credo, "~> 1.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ~w(lib test/support)
  defp elixirc_paths(_), do: ~w(lib)

  defp extra_compilers(:prod), do: []
  defp extra_compilers(_env), do: [:boundary]

  defp docs() do
    [
      main: "Boundary",
      extras: ["README.md"],
      source_url: "https://github.com/sasa1977/boundary/",
      source_ref: @version
    ]
  end

  defp package() do
    [
      description: "Managing cross-module dependencies in Elixir projects.",
      maintainers: ["Saša Jurić"],
      licenses: ["MIT"],
      links: %{
        "Github" => "https://github.com/sasa1977/boundary",
        "Changelog" =>
          "https://github.com/sasa1977/boundary/blob/#{@version}/CHANGELOG.md##{String.replace(@version, ".", "")}"
      }
    ]
  end

  defp dialyzer() do
    [
      plt_add_apps: [:mix]
    ]
  end
end
