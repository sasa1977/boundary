defmodule Boundary.GraphTest do
  use ExUnit.Case, async: true

  alias Boundary.Graph

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
                 rankdir=LR;

                 "A" [shape="box"];
                 "B" [shape="box"];
                 "C" [shape="box"];

                 "A" -> "B";
                 "A" -> "C";
                 "B" -> "C";
               }
               """
    end

    test "generate dot output with options" do
      dot =
        Graph.new("test")
        |> Graph.add_dependency("A", "B", label: "compile", test: "test")
        |> Graph.add_dependency("A", "C", label: "compile")
        |> Graph.dot(test: "test")

      assert dot ==
               """
               digraph {
                 label="test";
                 labelloc=top;
                 rankdir=LR;
                 test=test;

                 "A" [shape="box"];
                 "B" [shape="box"];
                 "C" [shape="box"];

                 "A" -> "B" [label=compile, test=test];
                 "A" -> "C" [label=compile];
               }
               """
    end

    test "generate dot output without options" do
      dot =
        Graph.new("test")
        |> Graph.add_dependency("A", "B")
        |> Graph.dot()

      assert dot ==
               """
               digraph {
                 label="test";
                 labelloc=top;
                 rankdir=LR;

                 "A" [shape="box"];
                 "B" [shape="box"];

                 "A" -> "B";
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
                 rankdir=LR;
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
                 rankdir=LR;

                 "A" [shape="box"];
                 "B" [shape="box"];

                 "A" -> "B";
               }
               """
    end

    test "add single node with no connections" do
      dot =
        Graph.new("test")
        |> Graph.add_node("C")
        |> Graph.add_dependency("A", "B")
        |> Graph.dot()

      assert dot ==
               """
               digraph {
                 label="test";
                 labelloc=top;
                 rankdir=LR;

                 "A" [shape="box"];
                 "B" [shape="box"];
                 "C" [shape="box"];

                 "A" -> "B";
               }
               """
    end
  end
end
