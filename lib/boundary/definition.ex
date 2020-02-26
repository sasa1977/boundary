defmodule Boundary.Definition do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Readability.Specs

  defmacro generate(opts) do
    quote bind_quoted: [opts: opts] do
      @boundary_opts opts
      @env __ENV__

      # Definition will be injected in before compile, because we need to check if this module is
      # a protocol, which we can only do right before the module is about to be compiled.
      @before_compile Boundary.Definition
    end
  end

  @doc false
  defmacro __before_compile__(_) do
    quote do
      case Keyword.pop(@boundary_opts, :classify_to, nil) do
        {nil, opts} ->
          Module.register_attribute(__MODULE__, Boundary, persist: true, accumulate: false)
          Module.put_attribute(__MODULE__, Boundary, Boundary.Definition.normalize(__MODULE__, opts, @env))

        {boundary, opts} ->
          protocol? = Module.defines?(__MODULE__, {:__impl__, 1}, :def)
          mix_task? = String.starts_with?(inspect(__MODULE__), "Mix.Tasks.")

          unless protocol? or mix_task?,
            do: raise(":classify_to can only be provided in protocol implementations and mix tasks")

          if opts != [],
            do: raise("no other option is allowed with :classify_to")

          Module.register_attribute(__MODULE__, Boundary.Target, persist: true, accumulate: false)
          Module.put_attribute(__MODULE__, Boundary.Target, %{boundary: boundary, file: @env.file, line: @env.line})
      end
    end
  end

  def get(boundary) do
    case Keyword.get(boundary.__info__(:attributes), Boundary) do
      [definition] -> definition
      nil -> nil
    end
  end

  def classified_to(module) do
    case Keyword.get(module.__info__(:attributes), Boundary.Target) do
      [classify_to] -> classify_to
      nil -> nil
    end
  end

  @doc false
  def normalize(boundary, definition, env) do
    defaults()
    |> Map.merge(Map.new(definition))
    |> validate!()
    |> expand_exports(boundary)
    |> Map.update!(:externals, &Map.new/1)
    |> Map.merge(%{file: env.file, line: env.line})
  end

  defp defaults, do: %{deps: [], exports: [], ignore?: false, externals: []}

  defp validate!(definition) do
    valid_keys = ~w/deps exports ignore? externals/a

    with [_ | _] = invalid_options <- definition |> Map.keys() |> Enum.reject(&(&1 in valid_keys)) do
      error = "Invalid options: #{invalid_options |> Stream.map(&inspect/1) |> Enum.join(", ")}"
      raise ArgumentError, error
    end

    if definition.ignore? do
      if definition.deps != [], do: raise(ArgumentError, message: "deps are not allowed in ignored boundaries")
      if definition.exports != [], do: raise(ArgumentError, message: "exports are not allowed in ignored boundaries")
    end

    definition
  end

  defp expand_exports(definition, boundary) do
    with %{ignore?: false} <- definition do
      update_in(
        definition.exports,
        fn exports ->
          expanded_aliases = Enum.map(exports, &Module.concat(boundary, &1))
          [boundary | expanded_aliases]
        end
      )
    end
  end
end
