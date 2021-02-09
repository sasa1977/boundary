defmodule Boundary.Reference do
  defstruct [:from, :to, :file, :line, :mode]

  @type t :: %__MODULE__{
          from: mfa | module,
          to: mfa | {:struct_expansion, module} | {:alias_reference, module},
          file: String.t(),
          line: pos_integer,
          mode: Boundary.mode()
        }

  @doc false
  @spec new(module, map) :: t
  def new(from_module, info) do
    struct!(
      __MODULE__,
      Map.update!(info, :from, fn
        {name, arity} -> {from_module, name, arity}
        nil -> from_module
      end)
    )
  end

  def from_module(%__MODULE__{from: module}) when is_atom(module), do: module
  def from_module(%__MODULE__{from: {module, _fun, _arity}}), do: module

  def to_module(%__MODULE__{to: {module, _fun, _arity}}), do: module
  def to_module(%__MODULE__{to: {:struct_expansion, module}}), do: module
  def to_module(%__MODULE__{to: {:alias_reference, module}}), do: module

  def type(%__MODULE__{to: {_module, _fun, _arity}}), do: :call
  def type(%__MODULE__{to: {:struct_expansion, _module}}), do: :struct_expansion
  def type(%__MODULE__{to: {:alias_reference, _module}}), do: :alias_reference
end
