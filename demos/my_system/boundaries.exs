[
  {MySystem.Application, deps: [MySystem, MySystemWeb]},
  {MySystem, deps: [], exports: [User]},
  {MySystemWeb, deps: [MySystem], exports: [Endpoint]}
]
