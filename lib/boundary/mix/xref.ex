defmodule Boundary.Mix.Xref do
  @moduledoc false
  use GenServer

  @calls_table __MODULE__.Calls
  @seen_table __MODULE__.Seen

  @type call :: %{
          callee: mfa,
          caller_function: {atom, non_neg_integer} | nil,
          file: String.t(),
          line: non_neg_integer,
          mode: :compile | :runtime
        }

  @spec start_link :: GenServer.on_start()
  def start_link do
    result = GenServer.start_link(__MODULE__, nil, name: __MODULE__)

    if match?({:ok, _pid}, result) or match?({:error, {:already_started, _pid}}, result),
      do: :ets.delete_all_objects(@seen_table)

    result
  end

  @spec add_call(module, call) :: :ok
  def add_call(caller, call) do
    if :ets.insert_new(@seen_table, {caller}), do: :ets.delete(@calls_table, caller)
    :ets.insert(@calls_table, {caller, call})
    :ok
  end

  @spec flush([module]) :: :ok | {:error, any}
  def flush(app_modules) do
    app_modules = MapSet.new(app_modules)

    stored_modules()
    |> Stream.reject(&MapSet.member?(app_modules, &1))
    |> Enum.each(&:ets.delete(@calls_table, &1))

    :ets.delete_all_objects(@seen_table)
    :ets.tab2file(@calls_table, to_charlist(Boundary.Mix.manifest_path("boundary")))
  end

  @doc "Returns a lazy stream where each element is of type `Boundary.call()`"
  @spec calls :: Enumerable.t()
  def calls do
    Enum.map(
      :ets.tab2list(@calls_table),
      fn {caller_module, %{callee: {callee, _fun, _arity}} = meta} ->
        caller =
          case meta.caller_function do
            {name, arity} -> {caller_module, name, arity}
            _ -> nil
          end

        Map.merge(meta, %{caller: caller, caller_module: caller_module, callee_module: callee})
      end
    )
  end

  @impl GenServer
  def init(nil) do
    :ets.new(@seen_table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    read_manifest() || build_manifest()
    {:ok, %{}}
  end

  defp build_manifest, do: :ets.new(@calls_table, [:named_table, :public, :duplicate_bag, write_concurrency: true])

  defp read_manifest do
    unless Boundary.Mix.stale_manifest?("boundary") do
      {:ok, table} = :ets.file2tab(String.to_charlist(Boundary.Mix.manifest_path("boundary")))
      table
    end
  rescue
    _ -> nil
  end

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
