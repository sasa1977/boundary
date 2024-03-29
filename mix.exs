defmodule Boundary.MixProject do
  use Mix.Project

  @version "0.10.3"

  def project do
    [
      app: :boundary,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs(),
      dialyzer: dialyzer(),
      package: package(),
      aliases: aliases()
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
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false},
      {:credo, "~> 1.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ~w(lib test/support)
  defp elixirc_paths(_), do: ~w(lib)

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
      plt_add_apps: [:mix],
      ignore_warnings: ".dialyzer_ignore"
    ]
  end

  defp aliases do
    [docs: ["docs", fn _ -> File.cp_r!("images", "doc/images") end]]
  end
end
