defmodule Boundary.Call do
  defstruct [:callee, :callee_module, :caller, :file, :line, :mode]

  @type t :: %__MODULE__{
          callee: mfa,
          callee_module: module,
          caller: mfa | module,
          file: String.t(),
          line: pos_integer,
          mode: Boundary.mode()
        }

  @doc false
  @spec new(module, map) :: t
  def new(caller_module, call_info) do
    {callee_module, _fun, _arity} = call_info.callee

    caller =
      case call_info.caller_function do
        {name, arity} -> {caller_module, name, arity}
        _ -> caller_module
      end

    struct!(
      __MODULE__,
      call_info
      |> Map.merge(%{caller: caller, callee_module: callee_module})
      |> Map.delete(:caller_function)
    )
  end

  def caller_module(%__MODULE__{caller: module}) when is_atom(module), do: module
  def caller_module(%__MODULE__{caller: {module, _fun, _arg}}), do: module
end
