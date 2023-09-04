defmodule Boundary.Mix.CompilerState do
  @moduledoc false
  use GenServer

  @spec start_link(force: boolean) :: {:ok, pid}
  def start_link(opts \\ []) do
    # The GenServer name (and ets tables) must contain app name, to properly work in umbrellas.
    name = :"#{__MODULE__}.#{Boundary.Mix.app_name()}"

    pid =
      case GenServer.start_link(__MODULE__, opts, name: name) do
        {:ok, pid} -> pid
        # this can happen in ElixirLS, since the process remains alive after the compilation run
        {:error, {:already_started, pid}} -> pid
      end

    :ets.delete_all_objects(seen_table())

    {:ok, pid}
  end

  @spec record_references(module, map) :: :ok
  def record_references(from, entry) do
    :ets.insert(references_table(), {from, entry})
    :ok
  end

  @spec initialize_module(module) :: :ok
  def initialize_module(module) do
    if :ets.insert_new(seen_table(), {module}), do: :ets.delete(references_table(), module)
    :ok
  end

  @spec flush([module]) :: :ok | {:error, any}
  def flush(app_modules) do
    app_modules = MapSet.new(app_modules)

    stored_modules()
    |> Stream.reject(&MapSet.member?(app_modules, &1))
    |> Enum.each(&:ets.delete(references_table(), &1))

    app_modules
    |> Enum.map(&Task.async(fn -> compress_entries(&1) end))
    |> Enum.each(&Task.await(&1, :infinity))

    :ets.delete_all_objects(seen_table())
    :ets.tab2file(references_table(), to_charlist(Boundary.Mix.manifest_path("boundary_references")))
  end

  @doc "Returns a lazy stream where each element is of type `t:Boundary.ref()`"
  @spec references :: Enumerable.t()
  def references do
    :ets.tab2list(references_table())
    |> Enum.map(fn {from_module, info} -> Map.put(info, :from, from_module) end)
  end

  @impl GenServer
  def init(opts) do
    :ets.new(seen_table(), [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])

    with false <- Keyword.get(opts, :force, false),
         {:ok, table} <- :ets.file2tab(String.to_charlist(Boundary.Mix.manifest_path("boundary_references"))),
         do: table,
         else: (_ -> :ets.new(references_table(), [:named_table, :public, :duplicate_bag, write_concurrency: true]))

    {:ok, %{}}
  end

  defp stored_modules do
    Stream.unfold(
      :ets.first(references_table()),
      fn
        :"$end_of_table" -> nil
        key -> {key, :ets.next(references_table(), key)}
      end
    )
  end

  defp compress_entries(module) do
    :ets.take(references_table(), module)
    |> Enum.map(fn {^module, entry} -> entry end)
    |> drop_leading_aliases()
    |> dedup_entries()
    |> Enum.each(&:ets.insert(references_table(), {module, &1}))
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

  defp seen_table, do: :"#{__MODULE__}.#{Boundary.Mix.app_name()}.Seen"
  defp references_table, do: :"#{__MODULE__}.#{Boundary.Mix.app_name()}.References"
end
