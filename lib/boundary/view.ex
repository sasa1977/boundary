defmodule Boundary.View do
  @moduledoc false
  alias Boundary.Classifier

  @type t :: %{
          main_app: app,
          classifier: Classifier.t(),
          unclassified_modules: MapSet.t(module),
          module_to_app: %{module => app},
          externals: MapSet.t(app)
        }

  @type app :: atom

  @type opts :: [classified_externals: Classifier.t()]

  @spec build(app) :: t
  def build(main_app) do
    module_to_app =
      for {app, _description, _vsn} <- Application.loaded_applications(),
          module <- app_modules(app),
          into: %{},
          do: {module, app}

    classifier = classify(main_app, module_to_app)
    main_app_boundaries = classifier.boundaries |> Map.values() |> Enum.filter(&(&1.app == main_app))

    %{
      main_app: main_app,
      classifier: classifier,
      unclassified_modules: unclassified_modules(main_app, classifier.modules),
      module_to_app: module_to_app,
      externals: all_externals(main_app_boundaries)
    }
  end

  @spec refresh(t) :: t | nil
  def refresh(view) do
    main_app_modules = app_modules(view.main_app)
    main_app_boundaries = load_app_boundaries(view.main_app, main_app_modules, view.module_to_app)

    if MapSet.equal?(view.externals, all_externals(main_app_boundaries)) do
      module_to_app = for module <- main_app_modules, into: view.module_to_app, do: {module, view.main_app}
      classifier = Classifier.classify(view.classifier, main_app_modules, main_app_boundaries)
      unclassified_modules = unclassified_modules(view.main_app, classifier.modules)
      %{view | classifier: classifier, unclassified_modules: unclassified_modules, module_to_app: module_to_app}
    else
      nil
    end
  end

  @spec drop_main_app(t) :: t
  def drop_main_app(view) do
    modules_to_delete = for {module, app} <- view.module_to_app, app == view.main_app, do: module
    module_to_app = Map.drop(view.module_to_app, modules_to_delete)

    classifier = Classifier.delete(view.classifier, view.main_app)
    %{view | classifier: classifier, unclassified_modules: MapSet.new(), module_to_app: module_to_app}
  end

  defp classify(main_app, module_to_app) do
    main_app_modules = app_modules(main_app)
    main_app_boundaries = load_app_boundaries(main_app, main_app_modules, module_to_app)

    classifier = classify_externals(main_app_boundaries, module_to_app)
    Classifier.classify(classifier, main_app_modules, main_app_boundaries)
  end

  defp classify_externals(main_app_boundaries, module_to_app) do
    Enum.reduce(
      load_external_boundaries(main_app_boundaries, module_to_app),
      Classifier.new(),
      &Classifier.classify(&2, &1.modules, &1.boundaries)
    )
  end

  defp all_externals(main_app_boundaries) do
    for boundary <- main_app_boundaries,
        external <- boundary.externals,
        into: MapSet.new(),
        do: external
  end

  defp load_app_boundaries(app_name, modules, module_to_app) do
    for module <- modules, boundary = Boundary.Definition.get(module) do
      exports = Enum.flat_map(boundary.exports, &expand_export(&1, modules))

      externals =
        boundary.deps
        |> Enum.map(fn {dep, _} -> Map.get(module_to_app, dep) end)
        |> Stream.reject(&is_nil/1)
        |> Stream.reject(&(&1 == app_name))
        |> Stream.concat(boundary.extra_externals)
        |> Enum.uniq()

      Map.merge(boundary, %{name: module, implicit?: false, modules: [], exports: exports, externals: externals})
    end
  end

  defp expand_export({module, opts}, modules) do
    case Keyword.fetch(opts, :except) do
      :error ->
        [module]

      {:ok, except} ->
        prefix = Module.split(module)
        except = Enum.into(except, MapSet.new(), &Module.concat(module, &1))

        modules
        |> Stream.reject(&MapSet.member?(except, &1))
        |> Enum.filter(fn candidate ->
          candidate = Module.split(candidate)
          List.starts_with?(candidate, prefix)
        end)
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
      for(boundary <- main_app_boundaries, app <- boundary.externals, into: MapSet.new(), do: app),
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
                |> Map.merge(%{name: dep, implicit?: true, top_level?: true, exports: [dep]})
            end)
          end

        %{modules: modules, boundaries: boundaries}
      end
    )
  end

  defp unclassified_modules(main_app, classified_modules) do
    # gather unclassified modules of this app
    for module <- app_modules(main_app),
        not Map.has_key?(classified_modules, module),
        not Boundary.protocol_impl?(module),
        into: MapSet.new(),
        do: module
  end

  @doc false
  @spec app_modules(Application.app()) :: list(Module.t())
  def app_modules(app),
    # we're currently supporting only Elixir modules
    do: Enum.filter(Application.spec(app, :modules) || [], &String.starts_with?(Atom.to_string(&1), "Elixir."))
end
