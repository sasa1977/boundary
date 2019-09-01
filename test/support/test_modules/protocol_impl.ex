defimpl Inspect, for: TestBoundaries.A do
  def inspect(a, opts), do: Kernel.inspect(a.x, opts)
end
