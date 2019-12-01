defmodule BoundaryXref.MixProject do
  use Mix.Project

  def project do
    [
      app: :boundary_xref,
      version: "0.1.0",
      elixir: "~> 1.10-dev",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:stream_data, "~> 0.4", only: :test}
    ]
  end
end
