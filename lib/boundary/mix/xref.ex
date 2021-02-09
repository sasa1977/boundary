defmodule Boundary.Mix.Xref do
  @moduledoc false
  use GenServer
  alias Boundary.Reference

  @entries_table __MODULE__.Entries
  @seen_table __MODULE__.Seen

  @type entry :: %{
          to: mfa | {:struct_expansion, module} | {:alias_reference, module},
          from: {atom, non_neg_integer} | nil,
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

  @spec record(module, entry) :: :ok
  def record(from, entry) do
    if :ets.insert_new(@seen_table, {from}), do: :ets.delete(@entries_table, from)
    :ets.insert(@entries_table, {from, entry})
    :ok
  end

  @spec flush([module]) :: :ok | {:error, any}
  def flush(app_modules) do
    app_modules = MapSet.new(app_modules)

    stored_modules()
    |> Stream.reject(&MapSet.member?(app_modules, &1))
    |> Enum.each(&:ets.delete(@entries_table, &1))

    :ets.delete_all_objects(@seen_table)
    :ets.tab2file(@entries_table, to_charlist(Boundary.Mix.manifest_path("boundary")))
  end

  @doc "Returns a lazy stream where each element is of type `t:Reference.t()`"
  @spec entries :: Enumerable.t()
  def entries do
    :ets.tab2list(@entries_table)
    |> Enum.map(fn {from_module, info} -> Reference.new(from_module, info) end)
    |> dedup_entries()
  end

  @impl GenServer
  def init(nil) do
    :ets.new(@seen_table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    read_manifest() || build_manifest()
    {:ok, %{}}
  end

  defp build_manifest, do: :ets.new(@entries_table, [:named_table, :public, :duplicate_bag, write_concurrency: true])

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
      :ets.first(@entries_table),
      fn
        :"$end_of_table" -> nil
        key -> {key, :ets.next(@entries_table, key)}
      end
    )
  end

  # Removes consecutive references to the same module in the same line.
  # This is needed because `Foo.bar` will generate two references: one from alias `Foo`, another from call `Foo.bar`.
  # In this case we want to keep the the entry, because we can determine if it is a macro.

  defp dedup_entries([]), do: []
  defp dedup_entries([entry | rest]), do: dedup_entries(rest, entry)

  defp dedup_entries([], last_entry), do: [last_entry]

  defp dedup_entries([next_entry | rest], pushed_entry) do
    cond do
      pushed_entry.file != next_entry.file or pushed_entry.line != next_entry.line or
          Reference.to_module(pushed_entry) != Reference.to_module(next_entry) ->
        [pushed_entry | dedup_entries(rest, next_entry)]

      Reference.type(pushed_entry) in [:call, :struct_expansion] ->
        dedup_entries(rest, pushed_entry)

      true ->
        dedup_entries(rest, next_entry)
    end
  end
end
