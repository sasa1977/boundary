defimpl Inspect, for: TestBoundaries.A do
  # credo:disable-for-this-file
  def inspect(a, opts), do: Kernel.inspect(a.x, opts)
end
