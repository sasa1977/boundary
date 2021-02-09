defmodule Boundary.Reference do
  @moduledoc """
  Represent a reference to another module.

  A reference can be one of the following:

    - invocation of a function or a macro of another module (`Foo.bar(...)` or `bar(...)` if `Foo` is imported)
    - structure expansion (`%Foo{...}`)
    - alias reference (`Foo`)
  """
  defstruct [:from, :to, :file, :line, :mode]

  @type t :: %__MODULE__{
          from: mfa | module,
          to: mfa | {:struct_expansion, module} | {:alias_reference, module},
          file: String.t(),
          line: pos_integer,
          mode: Boundary.mode()
        }

  @doc false
  @spec new(map) :: t
  def new(info), do: struct!(__MODULE__, info)

  @doc "Returns the source module of the reference."
  @spec from_module(t) :: module
  def from_module(%__MODULE__{from: module}) when is_atom(module), do: module
  def from_module(%__MODULE__{from: {module, _fun, _arity}}), do: module

  @doc "Returns the target module of the reference."
  @spec to_module(t) :: module
  def to_module(%__MODULE__{to: {module, _fun, _arity}}), do: module
  def to_module(%__MODULE__{to: {:struct_expansion, module}}), do: module
  def to_module(%__MODULE__{to: {:alias_reference, module}}), do: module

  @doc "Returns the reference type."
  @spec type(t) :: :call | :struct_expansion | :alias_reference
  def type(%__MODULE__{to: {_module, _fun, _arity}}), do: :call
  def type(%__MODULE__{to: {:struct_expansion, _module}}), do: :struct_expansion
  def type(%__MODULE__{to: {:alias_reference, _module}}), do: :alias_reference
end
