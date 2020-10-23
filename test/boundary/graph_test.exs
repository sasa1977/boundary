defmodule Boundary.GraphTest do
  use ExUnit.Case, async: true

  alias Graph

  describe "dot/1" do
    test "generate dot output" do
      dot =
        Graph.new("test")
        |> Graph.add_dependency("A", "B")
        |> Graph.add_dependency("A", "C")
        |> Graph.add_dependency("B", "C")
        |> Graph.dot()

      assert dot ==
               """
               digraph {
                 label="test";
                 labelloc=top;
                 A [shape="box"];
                 B [shape="box"];
                 C [shape="box"];


                 "A" -> "B";
                 "A" -> "C";
                 "B" -> "C";

               }
               """
    end

    test "succeeds for an empty graph" do
      dot = Graph.dot(Graph.new("test"))

      assert dot ==
               """
               digraph {
                 label="test";
                 labelloc=top;



               }
               """
    end

    test "deduplicated dependencies" do
      dot =
        Graph.new("test")
        |> Graph.add_dependency("A", "B")
        |> Graph.add_dependency("A", "B")
        |> Graph.dot()

      assert dot ==
               """
               digraph {
                 label="test";
                 labelloc=top;
                 A [shape="box"];
                 B [shape="box"];


                 "A" -> "B";

               }
               """
    end
  end
end
