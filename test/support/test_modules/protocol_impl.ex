# credo:disable-for-this-file

defimpl Inspect, for: TestBoundaries.A do
  def inspect(a, opts), do: Kernel.inspect(a.x, opts)
end

defimpl String.Chars, for: TestBoundaries.A do
  use Boundary, classify_to: TestBoundaries.A
  def to_string(a), do: inspect(a)
end
