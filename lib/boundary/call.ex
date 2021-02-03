defmodule Boundary.Call do
  defstruct [:callee, :callee_module, :caller, :caller_module, :file, :line, :mode]

  @type t :: %__MODULE__{
          callee: mfa,
          callee_module: module,
          caller: mfa,
          caller_module: module,
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
        _ -> nil
      end

    struct!(
      __MODULE__,
      call_info
      |> Map.merge(%{caller: caller, caller_module: caller_module, callee_module: callee_module})
      |> Map.delete(:caller_function)
    )
  end
end
