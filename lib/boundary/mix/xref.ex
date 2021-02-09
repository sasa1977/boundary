defmodule Boundary.Mix.Xref do
  @moduledoc false
  use GenServer
  alias Boundary.Call

  @calls_table __MODULE__.Calls
  @seen_table __MODULE__.Seen

  @type call :: %{
          callee: mfa | {:struct, module} | {:alias_reference, module},
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

  @doc "Returns a lazy stream where each element is of type `t:Call.t()`"
  @spec calls :: Enumerable.t()
  def calls do
    :ets.tab2list(@calls_table)
    |> Enum.map(fn {caller_module, call_info} -> Call.new(caller_module, call_info) end)
    |> dedup_calls()
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

  # Removes consecutive references to the same module in the same line.
  # This is needed because `Foo.bar` will generate two references: one from alias `Foo`, another from call `Foo.bar`.
  # In this case we want to keep the the call reference, because we can determine if it is a macro.

  defp dedup_calls([]), do: []
  defp dedup_calls([call | rest]), do: dedup_calls(rest, call)

  defp dedup_calls([], last_call), do: [last_call]

  defp dedup_calls([next_call | rest], pushed_call) do
    cond do
      pushed_call.file != next_call.file or pushed_call.line != next_call.line or
          Call.callee_module(pushed_call) != Call.callee_module(next_call) ->
        [pushed_call | dedup_calls(rest, next_call)]

      match?({_m, _f, _a}, pushed_call.callee) or match?({:struct, _module}, pushed_call.callee) ->
        dedup_calls(rest, pushed_call)

      true ->
        dedup_calls(rest, next_call)
    end
  end
end
