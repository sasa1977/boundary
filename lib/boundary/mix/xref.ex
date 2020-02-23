defmodule Boundary.Mix.Xref do
  @moduledoc false
  use GenServer

  @spec start_link :: GenServer.on_start()
  def start_link, do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @spec add_call(module, %{callee: mfa, file: String.t(), line: non_neg_integer}) :: :ok
  def add_call(caller, call) do
    :ets.insert(:boundary_xref_calls, {caller, call})
    :ok
  end

  @spec flush([module]) :: :ok
  def flush(app_modules) do
    purge_deleted_modules(app_modules)

    Stream.iterate(:ets.first(:boundary_xref_calls), &:ets.next(:boundary_xref_calls, &1))
    |> Stream.take_while(&(&1 != :"$end_of_table"))
    |> Enum.each(fn module ->
      File.write!(
        module_file(module),
        :erlang.term_to_binary(:ets.lookup_element(:boundary_xref_calls, module, 2))
      )
    end)
  end

  @doc "Returns a lazy stream where each element is of type `Boundary.call()`"
  @spec calls :: Enumerable.t()
  def calls do
    Path.join(path(), "*.bert")
    |> Path.wildcard()
    |> Stream.flat_map(fn filename ->
      caller_module = filename |> Path.basename(".bert") |> String.to_atom()

      filename
      |> File.read!()
      |> :erlang.binary_to_term()
      |> Stream.reject(&match?(%{callee: {^caller_module, _fun, _arg}}, &1))
      |> Stream.map(fn %{callee: {callee, _fun, _arg}} = meta ->
        Map.merge(meta, %{caller_module: caller_module, callee_module: callee})
      end)
    end)
  end

  @spec stop :: :ok
  def stop, do: GenServer.stop(__MODULE__)

  @impl GenServer
  def init(nil) do
    File.mkdir_p!(path())

    :ets.new(:boundary_xref_calls, [
      :named_table,
      :public,
      :duplicate_bag,
      write_concurrency: true
    ])

    {:ok, nil}
  end

  defp purge_deleted_modules(app_modules) do
    existing_modules = Enum.into(app_modules, MapSet.new(), &module_file/1)

    recorded_modules =
      Path.join(path(), "*.bert")
      |> Path.wildcard()
      |> MapSet.new()

    Enum.each(
      MapSet.difference(recorded_modules, existing_modules),
      &File.rm_rf/1
    )
  end

  defp module_file(module), do: Path.join(path(), "#{module}.bert")

  defp path do
    Path.join([
      Mix.Project.build_path(),
      "boundary",
      to_string(Boundary.Mix.app_name())
    ])
  end
end
