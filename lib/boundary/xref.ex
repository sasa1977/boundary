defmodule Boundary.Xref do
  @moduledoc false
  use GenServer

  def start_link(path), do: GenServer.start_link(__MODULE__, path, name: __MODULE__)
  def add_call(caller, call), do: GenServer.cast(__MODULE__, {:add_call, {caller, call}})

  def finalize(app_modules \\ nil) do
    with pid when not is_nil(pid) <- Process.whereis(__MODULE__),
         do: GenServer.call(pid, {:finalize, app_modules}, :infinity)

    :ok
  end

  def calls(path) do
    db = open_db!(path)

    try do
      db
      |> :dets.match(:"$1")
      |> Enum.concat()
    after
      :dets.close(db)
    end
  end

  @impl GenServer
  def init(path) do
    {:ok, %{seen_modules: :ets.new(:seen_modules, [:set, :private]), calls: open_db!(path), path: path}}
  end

  @impl GenServer
  def handle_call({:finalize, app_modules}, _from, state) do
    if not is_nil(app_modules), do: purge_deleted_modules(state, app_modules)
    :dets.close(state.calls)
    {:stop, :normal, :ok, state}
  end

  @impl GenServer
  def handle_cast({:add_call, {caller, _call} = call}, state) when not is_nil(state) do
    if :ets.insert_new(state.seen_modules, {caller}),
      do: :dets.delete(state.calls, caller)

    :dets.insert(state.calls, call)

    {:noreply, state}
  end

  defp purge_deleted_modules(state, app_modules) do
    state
    |> recorded_modules()
    |> MapSet.new()
    |> MapSet.difference(MapSet.new(app_modules))
    |> Enum.each(&:dets.delete(state.calls, &1))
  end

  defp recorded_modules(state) do
    state.calls
    |> :dets.match({:"$1", :_})
    |> Stream.concat()
  end

  defp open_db!(path) do
    {:ok, state} =
      :dets.open_file(make_ref(), file: to_char_list(path), access: :read_write, auto_save: 0, type: :duplicate_bag)

    state
  end
end
