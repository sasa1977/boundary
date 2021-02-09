defmodule Boundary.Call do
  defstruct [:callee, :caller, :file, :line, :mode]

  @type t :: %__MODULE__{
          callee: mfa | {:struct, module} | {:alias_reference, module},
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
  def caller_module(%__MODULE__{caller: {module, _fun, _arity}}), do: module

  def callee_module(%__MODULE__{callee: {module, _fun, _arity}}), do: module
  def callee_module(%__MODULE__{callee: {:struct, module}}), do: module
  def callee_module(%__MODULE__{callee: {:alias_reference, module}}), do: module

  def callee_display(%__MODULE__{callee: {module, fun, arity}}), do: Exception.format_mfa(module, fun, arity)
  def callee_display(%__MODULE__{callee: {:struct, module}}), do: "%#{inspect(module)}{}"
  def callee_display(%__MODULE__{callee: {:alias_reference, module}}), do: inspect(module)
end
