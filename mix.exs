defmodule Boundary.MixProject do
  use Mix.Project

  def project do
    [
      app: :boundary,
      version: "0.1.0",
      elixir: "~> 1.10.0-dev",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: Mix.compilers() ++ extra_compilers(Mix.env()),
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs(),
      dialyzer: dialyzer()
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
      extras: ["README.md"]
    ]
  end

  defp dialyzer() do
    [
      plt_add_apps: [:mix]
    ]
  end
end
