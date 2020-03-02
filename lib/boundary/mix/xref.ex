defmodule Boundary.Mix.Xref do
  @moduledoc false
  use GenServer

  @vsn 1
  @calls_table __MODULE__.Calls
  @seen_table __MODULE__.Seen

  @spec start_link :: GenServer.on_start()
  def start_link, do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @spec add_call(module, %{callee: mfa, file: String.t(), line: non_neg_integer, mode: :compile | :runtime}) :: :ok
  def add_call(caller, call) do
    if :ets.insert_new(@seen_table, {caller}), do: :ets.delete(@calls_table, caller)
    unless match?({^caller, _fun, _arg}, call.callee), do: :ets.insert(@calls_table, {caller, call})
    :ok
  end

  @spec flush([module]) :: :ok | {:error, any}
  def flush(app_modules) do
    app_modules = MapSet.new(app_modules)

    stored_modules()
    |> Stream.reject(&MapSet.member?(app_modules, &1))
    |> Enum.each(&:ets.delete(@calls_table, &1))

    :ets.tab2file(@calls_table, to_charlist(manifest()))
  end

  @doc "Returns a lazy stream where each element is of type `Boundary.call()`"
  @spec calls :: Enumerable.t()
  def calls do
    Enum.map(
      :ets.tab2list(@calls_table),
      fn {caller, %{callee: {callee, _fun, _arity}} = meta} ->
        Map.merge(meta, %{caller_module: caller, callee_module: callee})
      end
    )
  end

  @impl GenServer
  def init(nil) do
    :ets.new(@seen_table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])

    manifest = manifest()

    if Mix.Utils.stale?([Mix.Project.config_mtime()], [manifest]),
      do: build_manifest(),
      else: read_manifest(manifest)

    {:ok, %{}}
  end

  defp build_manifest, do: :ets.new(@calls_table, [:named_table, :public, :duplicate_bag, write_concurrency: true])

  defp read_manifest(manifest) do
    {:ok, table} = :ets.file2tab(String.to_charlist(manifest))
    table
  rescue
    _ -> build_manifest()
  end

  defp manifest, do: Path.join(Mix.Project.manifest_path(Mix.Project.config()), "compile.boundary")

  defp stored_modules do
    Stream.unfold(
      :ets.first(@calls_table),
      fn
        :"$end_of_table" -> nil
        key -> {key, :ets.next(@calls_table, key)}
      end
    )
  end
end
