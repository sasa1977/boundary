defmodule Boundary.Mix.Xref do
  @moduledoc false
  use GenServer

  @entries_table __MODULE__.Entries
  @seen_table __MODULE__.Seen

  @type entry :: %{
          to: module,
          from: module,
          from_function: {function :: atom, arity :: non_neg_integer} | nil,
          type: :call | :struct_expansion | :alias_reference,
          mode: :compile | :runtime,
          file: String.t(),
          line: non_neg_integer
        }

  @spec start_link :: GenServer.on_start()
  def start_link do
    result = GenServer.start_link(__MODULE__, nil, name: __MODULE__)

    if match?({:ok, _pid}, result) or match?({:error, {:already_started, _pid}}, result),
      do: :ets.delete_all_objects(@seen_table)

    result
  end

  @spec record(module, map) :: :ok
  def record(from, entry) do
    :ets.insert(@entries_table, {from, entry})
    :ok
  end

  @spec initialize_module(module) :: :ok
  def initialize_module(module) do
    if :ets.insert_new(@seen_table, {module}), do: :ets.delete(@entries_table, module)
    :ok
  end

  @spec flush([module]) :: :ok | {:error, any}
  def flush(app_modules) do
    app_modules = MapSet.new(app_modules)

    stored_modules()
    |> Stream.reject(&MapSet.member?(app_modules, &1))
    |> Enum.each(&:ets.delete(@entries_table, &1))

    app_modules
    |> Enum.map(&Task.async(fn -> compress_entries(&1) end))
    |> Enum.each(&Task.await(&1, :infinity))

    :ets.delete_all_objects(@seen_table)
    :ets.tab2file(@entries_table, to_charlist(Boundary.Mix.manifest_path("boundary")))
  end

  @doc "Returns a lazy stream where each element is of type `t:Reference.t()`"
  @spec entries :: Enumerable.t()
  def entries do
    :ets.tab2list(@entries_table)
    |> Enum.map(fn {from_module, info} -> Map.put(info, :from, from_module) end)
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

  defp compress_entries(module) do
    :ets.take(@entries_table, module)
    |> Enum.map(fn {^module, entry} -> entry end)
    |> drop_leading_aliases()
    |> dedup_entries()
    |> Enum.each(&:ets.insert(@entries_table, {module, &1}))
  end

  defp drop_leading_aliases([entry, next_entry | rest]) do
    # For the same file/line/to combo remove leading alias reference. This is needed because `Foo.bar()` and `%Foo{}` will
    # generate two entries: alias reference to `Foo`, followed by the function call or the struct expansion. In this
    # case we want to keep only the second entry.
    if entry.type == :alias_reference and
         entry.to == next_entry.to and
         entry.file == next_entry.file and
         entry.line == next_entry.line,
       do: drop_leading_aliases([next_entry | rest]),
       else: [entry | drop_leading_aliases([next_entry | rest])]
  end

  defp drop_leading_aliases(other), do: other

  # Keep only one entry per file/line/to/mode combo
  defp dedup_entries(entries) do
    # Alias ref has lower prio because this check is optional. Therefore, if we have any call or struct expansion, we'll
    # prefer that.
    prios = %{call: 1, struct_expansion: 1, alias_reference: 2}

    entries
    |> Enum.group_by(&{&1.file, &1.line, &1.to, &1.mode})
    |> Enum.map(fn {_key, entries} -> Enum.min_by(entries, &Map.fetch!(prios, &1.type)) end)
    |> Enum.sort_by(&{&1.file, &1.line})
  end
end
