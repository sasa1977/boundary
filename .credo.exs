%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "src/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      requires: [],
      strict: true,
      color: true,
      checks: [
        # extra enabled checks
        {Credo.Check.Readability.Specs, []},
        {Credo.Check.Readability.AliasAs, []},

        # disabled checks
        {Credo.Check.Design.TagTODO, false},
        {Credo.Check.Design.AliasUsage, false}
      ]
    }
  ]
}
