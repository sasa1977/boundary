use Mix.Config

if Mix.env() == :test do
  config :stream_data,
    max_runs: if(System.get_env("CI"), do: 100, else: 50)
end
