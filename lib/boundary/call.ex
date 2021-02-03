defmodule Boundary.Call do
  defstruct [:callee, :caller, :file, :line, :mode]

  @type t :: %__MODULE__{
          callee: mfa,
          caller: mfa | module,
          file: String.t(),
          line: pos_integer,
          mode: Boundary.mode()
        }

  @doc false
  @spec new(module, map) :: t
  def new(caller_module, call_info) do
    caller =
      case call_info.caller_function do
        {name, arity} -> {caller_module, name, arity}
        nil -> caller_module
      end

    struct!(__MODULE__, call_info |> Map.put(:caller, caller) |> Map.delete(:caller_function))
  end

  def caller_module(%__MODULE__{caller: module}) when is_atom(module), do: module
  def caller_module(%__MODULE__{caller: {module, _fun, _arg}}), do: module

  def callee_module(%__MODULE__{callee: {module, _fun, _arg}}), do: module
end
