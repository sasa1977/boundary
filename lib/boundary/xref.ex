defmodule Boundary.Xref do
  @moduledoc false
  use GenServer

  @type call :: %{
          callee: mfa,
          callee_module: module,
          caller_module: module,
          file: String.t(),
          line: pos_integer
        }

  @spec start_link(String.t()) :: GenServer.on_start()
  def start_link(path), do: GenServer.start_link(__MODULE__, path, name: __MODULE__)

  @spec add_call(module, %{callee: mfa, file: String.t(), line: non_neg_integer}) :: :ok
  def add_call(caller, call) do
    if :ets.insert_new(:boundary_xref_seen_modules, {caller}),
      do: :ets.delete(:boundary_xref_calls, caller)

    :ets.insert(:boundary_xref_calls, {caller, call})
    :ok
  end

  @spec flush(String.t(), [module]) :: :ok
  def flush(path, app_modules) do
    if not is_nil(app_modules), do: purge_deleted_modules(app_modules)
    :ets.tab2file(:boundary_xref_calls, to_charlist(path))
  end

  @spec calls() :: [call]
  def calls() do
    :boundary_xref_calls
    |> :ets.tab2list()
    |> Stream.map(fn {caller, meta} -> Map.put(meta, :caller_module, caller) end)
    |> Stream.map(fn %{callee: {mod, _fun, _arg}} = entry -> Map.put(entry, :callee_module, mod) end)
    |> Enum.reject(&(&1.callee_module == &1.caller_module))
  end

  @spec stop() :: :ok
  def stop(), do: GenServer.stop(__MODULE__)

  @impl GenServer
  def init(path) do
    :ets.new(
      :boundary_xref_seen_modules,
      [:set, :public, :named_table, read_concurrency: true, write_concurrency: true]
    )

    load_file(path) ||
      :ets.new(:boundary_xref_calls, [
        :named_table,
        :public,
        :duplicate_bag,
        write_concurrency: true
      ])

    {:ok, nil}
  end

  defp purge_deleted_modules(app_modules) do
    recorded_modules()
    |> MapSet.new()
    |> MapSet.difference(MapSet.new(app_modules))
    |> Enum.each(&:ets.delete(:boundary_xref_calls, &1))
  end

  defp recorded_modules do
    :boundary_xref_calls
    |> :ets.match({:"$1", :_})
    |> Stream.concat()
  end

  defp load_file(path) do
    {:ok, tab} = :ets.file2tab(to_charlist(path))
    tab
  catch
    _, _ ->
      nil
  end
end
