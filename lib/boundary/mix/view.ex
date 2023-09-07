defmodule Boundary.Mix.View do
  @moduledoc false
  alias Boundary.Mix.{Classifier, CompilerState}

  @spec build() :: Boundary.view()
  def build do
    main_app = Boundary.Mix.app_name()

    module_to_app =
      for {app, _description, _vsn} <- Application.loaded_applications(),
          module <- Boundary.Mix.app_modules(app),
          into: %{},
          do: {module, app}

    classifier = classify(main_app, module_to_app)
    main_app_boundaries = classifier.boundaries |> Map.values() |> Enum.filter(&(&1.app == main_app))

    %{
      version: unquote(Mix.Project.config()[:version]),
      main_app: main_app,
      classifier: classifier,
      unclassified_modules: nil,
      module_to_app: module_to_app,
      external_deps: all_external_deps(main_app, main_app_boundaries, module_to_app),
      boundary_defs: nil,
      protocol_impls: nil
    }
    |> load_main_app_cache()
    |> then(&Map.update!(&1, :unclassified_modules, fn _ -> unclassified_modules(&1) end))
  end

  defp load_main_app_cache(view) do
    boundary_defs = CompilerState.boundary_defs(view.main_app)
    protocol_impls = CompilerState.protocol_impls(view.main_app)
    %{view | boundary_defs: boundary_defs, protocol_impls: protocol_impls}
  end

  @spec refresh([Application.app()], force: boolean) :: Boundary.view()
  def refresh(user_apps, opts) do
    manifest_file = "boundary_view_v2"

    view =
      with false <- Keyword.get(opts, :force, false),
           view = Boundary.Mix.read_manifest(manifest_file),
           %{version: unquote(Mix.Project.config()[:version])} <- view,
           %{} = view <- do_refresh(view, user_apps) do
        view
      else
        _ ->
          Boundary.Mix.load_app()
          build()
      end

    stored_view =
      Enum.reduce(
        user_apps,
        %{view | unclassified_modules: MapSet.new(), boundary_defs: %{}, protocol_impls: %{}},
        &drop_app(&2, &1)
      )

    Boundary.Mix.write_manifest(manifest_file, stored_view)

    view
  end

  defp do_refresh(%{version: unquote(Mix.Project.config()[:version])} = view, apps) do
    view = load_main_app_cache(view)

    module_to_app =
      for {app, _description, _vsn} <- Application.loaded_applications(),
          module <- Boundary.Mix.app_modules(app),
          into: view.module_to_app,
          do: {module, app}

    main_app_modules = Boundary.Mix.app_modules(view.main_app)
    main_app_boundaries = load_app_boundaries(view.main_app, main_app_modules, module_to_app)

    if MapSet.equal?(view.external_deps, all_external_deps(view.main_app, main_app_boundaries, module_to_app)) do
      view =
        Enum.reduce(
          apps,
          %{view | module_to_app: module_to_app},
          fn app, view ->
            app_modules = Boundary.Mix.app_modules(app)
            module_to_app = for module <- app_modules, into: view.module_to_app, do: {module, app}
            app_boundaries = load_app_boundaries(app, app_modules, module_to_app)
            classifier = Classifier.classify(view.classifier, app, app_modules, app_boundaries)
            %{view | classifier: classifier, module_to_app: module_to_app}
          end
        )

      unclassified_modules = unclassified_modules(view)
      %{view | unclassified_modules: unclassified_modules}
    else
      nil
    end
  end

  defp drop_app(view, app) do
    modules_to_delete = for {module, ^app} <- view.module_to_app, do: module
    module_to_app = Map.drop(view.module_to_app, modules_to_delete)
    classifier = Classifier.delete(view.classifier, app)
    %{view | classifier: classifier, module_to_app: module_to_app}
  end

  defp classify(main_app, module_to_app) do
    main_app_modules = Boundary.Mix.app_modules(main_app)
    main_app_boundaries = load_app_boundaries(main_app, main_app_modules, module_to_app)

    classifier = classify_external_deps(main_app_boundaries, module_to_app)
    Classifier.classify(classifier, main_app, main_app_modules, main_app_boundaries)
  end

  defp classify_external_deps(main_app_boundaries, module_to_app) do
    Enum.reduce(
      load_external_boundaries(main_app_boundaries, module_to_app),
      Classifier.new(),
      &Classifier.classify(&2, &1.app, &1.modules, &1.boundaries)
    )
  end

  defp all_external_deps(main_app, main_app_boundaries, module_to_app) do
    for boundary <- main_app_boundaries,
        {dep, _} <- boundary.deps,
        Map.get(module_to_app, dep) != main_app,
        into: MapSet.new(),
        do: dep
  end

  defp load_app_boundaries(app_name, modules, module_to_app) do
    boundary_defs = CompilerState.boundary_defs(app_name)

    for module <- modules, boundary = Boundary.Definition.get(module, boundary_defs) do
      check_apps =
        for {dep_name, _mode} <- boundary.deps,
            app = Map.get(module_to_app, dep_name),
            app not in [nil, app_name],
            reduce: boundary.check.apps do
          check_apps -> [{app, :compile}, {app, :runtime} | check_apps]
        end

      Map.merge(boundary, %{
        name: module,
        implicit?: false,
        modules: [],
        check: %{boundary.check | apps: Enum.sort(Enum.uniq(check_apps))}
      })
    end
  end

  defp load_external_boundaries(main_app_boundaries, module_to_app) do
    # fetch and index all deps
    all_deps =
      for user_boundary <- main_app_boundaries,
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

    Enum.map(
      for(boundary <- main_app_boundaries, {app, _} <- boundary.check.apps, into: MapSet.new(), do: app),
      fn app ->
        modules = Boundary.Mix.app_modules(app)

        boundaries =
          with [] <- load_app_boundaries(app, modules, module_to_app) do
            # app defines no boundaries -> we'll use implicit boundaries from all deps pointing to modules of this app
            implicit_boundaries
            |> Map.get(app, [])
            |> Enum.map(fn
              {dep, _user_boundary} ->
                app
                |> Boundary.Definition.normalize(dep, [])
                |> Map.merge(%{name: dep, implicit?: true, top_level?: true, exports: [dep]})
            end)
          end

        %{app: app, modules: modules, boundaries: boundaries}
      end
    )
  end

  defp unclassified_modules(view) do
    # gather unclassified modules of this app
    for module <- Boundary.Mix.app_modules(view.main_app),
        not Map.has_key?(view.classifier.modules, module),
        not Boundary.protocol_impl?(view, module),
        into: MapSet.new(),
        do: module
  end
end
