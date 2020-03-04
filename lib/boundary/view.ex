defmodule Boundary.View do
  @moduledoc false
  alias Boundary.Classifier

  @type t :: %{
          boundaries: %{Boundary.name() => t},
          classified_modules: %{module => Boundary.name()},
          unclassified_modules: MapSet.t(module),
          module_to_app: %{module => atom}
        }

  @spec build(atom) :: t
  def build(main_app) do
    main_app_modules = app_modules(main_app)

    module_to_app =
      for {app, _description, _vsn} <- Application.loaded_applications(),
          module <- app_modules(app),
          into: %{},
          do: {module, app}

    %{boundaries: boundaries, modules: classified_modules} =
      main_app
      |> load_apps_and_boundaries(main_app_modules, module_to_app)
      |> Enum.reduce(Classifier.new(), &Classifier.classify(&2, &1.modules, &1.boundaries))

    %{
      boundaries: boundaries,
      classified_modules: classified_modules,
      unclassified_modules: unclassified_modules(main_app_modules, classified_modules),
      module_to_app: module_to_app
    }
  end

  defp load_apps_and_boundaries(main_app, main_app_modules, module_to_app) do
    # fetch boundaries of this app
    app_boundaries = load_app_boundaries(main_app, main_app_modules, module_to_app)

    # fetch and index all deps
    all_deps =
      for user_boundary <- app_boundaries,
          {dep, _type} <- user_boundary.deps,
          into: %{},
          do: {dep, user_boundary}

    # create app -> [boundary] mapping which will be used to determine implicit boundaries
    implicit_boundaries =
      for {dep, user_boundary} <- all_deps,
          boundary_app = Map.get(module_to_app, dep),
          reduce: %{} do
        acc -> Map.update(acc, boundary_app, [{dep, user_boundary}], &[{dep, user_boundary} | &1])
      end

    external_boundaries =
      Enum.map(
        for(boundary <- app_boundaries, app <- boundary.externals, into: MapSet.new(), do: app),
        fn app ->
          modules = app_modules(app)

          boundaries =
            with [] <- load_app_boundaries(app, modules, module_to_app) do
              # app defines no boundaries -> we'll use implicit boundaries from all deps pointing to modules of this app
              implicit_boundaries
              |> Map.get(app, [])
              |> Enum.map(fn
                {dep, user_boundary} ->
                  app
                  |> Boundary.Definition.normalize(dep, [], user_boundary)
                  |> Map.merge(%{name: dep, implicit?: true})
              end)
            end

          %{modules: modules, boundaries: boundaries}
        end
      )

    [%{modules: main_app_modules, boundaries: app_boundaries} | external_boundaries]
  end

  defp load_app_boundaries(app_name, modules, module_to_app) do
    for module <- modules, boundary = Boundary.Definition.get(module) do
      externals =
        boundary.deps
        |> Stream.map(fn {dep, _} -> Map.get(module_to_app, dep) end)
        |> Stream.reject(&is_nil/1)
        |> Stream.reject(&(&1 == app_name))
        |> Stream.concat(boundary.extra_externals)
        |> Enum.uniq()

      Map.merge(boundary, %{name: module, implicit?: false, modules: [], externals: externals})
    end
  end

  defp unclassified_modules(main_app_modules, classified_modules) do
    # gather unclassified modules of this app
    for module <- main_app_modules,
        not Map.has_key?(classified_modules, module),
        not Boundary.protocol_impl?(module),
        into: MapSet.new(),
        do: module
  end

  defp app_modules(app),
    # we're currently supporting only Elixir modules
    do: Enum.filter(Application.spec(app, :modules), &String.starts_with?(Atom.to_string(&1), "Elixir."))
end
