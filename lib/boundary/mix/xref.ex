defmodule Boundary.Mix.Xref do
  @moduledoc false
  use GenServer
  alias __MODULE__.TermsStorage

  @vsn 1

  @spec start_link :: GenServer.on_start()
  def start_link, do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @spec add_call(module, %{callee: mfa, file: String.t(), line: non_neg_integer}) :: :ok
  def add_call(caller, call) do
    case call do
      %{callee: {^caller, _fun, _arg}} -> :ok
      _ -> GenServer.cast(__MODULE__, {:record, caller, call})
    end
  end

  @spec flush([module]) :: :ok
  def flush(app_modules) do
    purge_deleted_modules(app_modules)
    GenServer.stop(__MODULE__)
  end

  @doc "Returns a lazy stream where each element is of type `Boundary.call()`"
  @spec calls :: Enumerable.t()
  def calls do
    Path.join(path(), "*.calls")
    |> Path.wildcard()
    |> Stream.flat_map(fn filename ->
      caller = filename |> Path.basename(".calls") |> String.to_atom()

      TermsStorage.read!(filename)
      |> Stream.filter(fn %{callee: {callee, _fun, _arity}} ->
        String.starts_with?(Atom.to_string(callee), "Elixir.")
      end)
      |> Stream.map(fn %{callee: {callee, _fun, _arity}} = meta ->
        Map.merge(meta, %{caller_module: caller, callee_module: callee})
      end)
    end)
  end

  @spec stop :: :ok
  def stop, do: GenServer.stop(__MODULE__)

  @impl GenServer
  def init(nil) do
    File.mkdir_p!(path())
    {:ok, %{}}
  end

  @impl GenServer
  def handle_cast({:record, caller, call}, state) do
    {storage, state} = ensure_storage(state, caller)
    TermsStorage.append!(storage, call)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    for {_module, storage} <- state, do: TermsStorage.close!(storage)
    :ok
  end

  defp ensure_storage(state, caller) do
    case Map.fetch(state, caller) do
      {:ok, storage} ->
        {storage, state}

      :error ->
        storage = TermsStorage.create!(module_file(caller))
        {storage, Map.put(state, caller, storage)}
    end
  end

  defp purge_deleted_modules(app_modules) do
    existing_modules = Enum.into(app_modules, MapSet.new(), &module_file/1)

    recorded_modules =
      Path.join(path(), "*.calls")
      |> Path.wildcard()
      |> MapSet.new()

    Enum.each(
      MapSet.difference(recorded_modules, existing_modules),
      &File.rm_rf/1
    )
  end

  defp module_file(module), do: Path.join(path(), "#{module}.calls")

  defp path do
    Path.join([
      Mix.Project.build_path(),
      "boundary",
      to_string(@vsn),
      to_string(Boundary.Mix.app_name())
    ])
  end

  defmodule TermsStorage do
    @moduledoc false

    # This module is used to persist terms on the fly. As a result, the client code doesn't have to
    # collect the complete list of calls, before storing it to disk. This is particularly important
    # because compiler tracer doesn't inform us when the module has started or finished compiling.
    # If we used a naive `:erlang.term_to_binary/1`, we'd have to collect all the calls of all
    # modules in memory, before we could persist anything to disk.
    #
    # This storage allows us to avoid that, ultimately stabilizing the memory usage with respect to
    # the project size. The calls are stored on the fly (with a bit of `:delayed_write` buffering),
    # which means the memory usage shouldn't grow significantly.

    @opaque t :: File.io_device()

    @spec create!(String.t()) :: t
    def create!(path) do
      File.open!(
        path,
        [:binary, :raw, :write, :delayed_write]
      )
    end

    @spec close!(t) :: :ok
    def close!(storage) do
      :ok = File.close(storage)
    end

    @spec append!(t, term) :: :ok
    def append!(storage, term) do
      bytes = :erlang.term_to_binary(term)
      full_message = <<byte_size(bytes)::64, bytes::binary>>
      :ok = IO.binwrite(storage, full_message)
    end

    @spec read!(String.t()) :: Enumerable.t()
    def read!(path) do
      Stream.resource(
        fn -> File.open!(path, [:binary, :raw, :read, :read_ahead]) end,
        fn file ->
          with <<size::64>> <- IO.binread(file, 8),
               <<_::binary>> = bytes <- IO.binread(file, size) do
            try do
              {[:erlang.binary_to_term(bytes)], file}
            rescue
              ArgumentError -> {:halt, file}
            end
          else
            _ -> {:halt, file}
          end
        end,
        fn file -> File.close(file) end
      )
    end
  end
end
