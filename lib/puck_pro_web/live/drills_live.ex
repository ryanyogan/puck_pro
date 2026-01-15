defmodule PuckProWeb.DrillsLive do
  @moduledoc """
  Browse and filter drills by category and difficulty.
  """
  use PuckProWeb, :live_view

  alias PuckPro.Training

  @impl true
  def mount(_params, _session, socket) do
    categories = Training.list_skill_categories_ordered()
    drills = Training.list_drills_with_categories()

    socket =
      socket
      |> assign(:page_title, "Drills")
      |> assign(:categories, categories)
      |> assign(:selected_category, nil)
      |> assign(:selected_difficulty, nil)
      |> stream(:drills, drills)

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    category_slug = Map.get(params, "category")
    difficulty = Map.get(params, "difficulty")

    drills = filter_drills(category_slug, difficulty)

    {:noreply,
     socket
     |> assign(:selected_category, category_slug)
     |> assign(:selected_difficulty, difficulty)
     |> stream(:drills, drills, reset: true)}
  end

  defp filter_drills(nil, nil), do: Training.list_drills_with_categories()
  defp filter_drills(nil, ""), do: Training.list_drills_with_categories()
  defp filter_drills("", nil), do: Training.list_drills_with_categories()
  defp filter_drills("", ""), do: Training.list_drills_with_categories()

  defp filter_drills(category_slug, nil) when is_binary(category_slug) do
    case Training.get_skill_category_by_slug(category_slug) do
      nil -> Training.list_drills_with_categories()
      cat -> Training.list_drills_by_category(cat.id)
    end
  end

  defp filter_drills(nil, difficulty) when is_binary(difficulty) do
    Training.list_drills_by_difficulty(difficulty)
  end

  defp filter_drills(category_slug, difficulty) do
    # Combine filters
    case Training.get_skill_category_by_slug(category_slug) do
      nil ->
        Training.list_drills_by_difficulty(difficulty)

      cat ->
        Training.list_drills_by_category(cat.id)
        |> Enum.filter(&(&1.difficulty == difficulty))
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen">
        <%!-- Header --%>
        <div class="bg-base-200 border-b border-base-300">
          <div class="max-w-6xl mx-auto px-4 py-6">
            <h1 class="text-2xl font-bold">Drills Library</h1>
            <p class="text-base-content/60 mt-1">
              Pick a drill to practice or start a random one
            </p>
          </div>
        </div>

        <%!-- Filters --%>
        <div class="max-w-6xl mx-auto px-4 py-4 border-b border-base-300/50">
          <div class="flex flex-wrap gap-4">
            <%!-- Category Filter --%>
            <div class="flex items-center gap-2">
              <span class="text-xs font-bold uppercase tracking-wider text-base-content/50">
                Skill:
              </span>
              <div class="flex flex-wrap gap-1">
                <button
                  phx-click="filter"
                  phx-value-category=""
                  phx-value-difficulty={@selected_difficulty}
                  class={[
                    "px-2 py-1 text-xs font-medium border transition-colors",
                    @selected_category == nil && "bg-primary text-primary-content border-primary",
                    @selected_category != nil && "bg-base-200 border-base-300 hover:bg-base-300"
                  ]}
                >
                  All
                </button>
                <button
                  :for={cat <- @categories}
                  phx-click="filter"
                  phx-value-category={cat.slug}
                  phx-value-difficulty={@selected_difficulty}
                  class={[
                    "px-2 py-1 text-xs font-medium border transition-colors",
                    @selected_category == cat.slug && "bg-primary text-primary-content border-primary",
                    @selected_category != cat.slug && "bg-base-200 border-base-300 hover:bg-base-300"
                  ]}
                >
                  {cat.name}
                </button>
              </div>
            </div>

            <%!-- Difficulty Filter --%>
            <div class="flex items-center gap-2">
              <span class="text-xs font-bold uppercase tracking-wider text-base-content/50">
                Level:
              </span>
              <div class="flex gap-1">
                <button
                  :for={diff <- ["beginner", "intermediate", "advanced"]}
                  phx-click="filter"
                  phx-value-category={@selected_category}
                  phx-value-difficulty={diff}
                  class={[
                    "px-2 py-1 text-xs font-medium border transition-colors capitalize",
                    @selected_difficulty == diff && "bg-primary text-primary-content border-primary",
                    @selected_difficulty != diff && "bg-base-200 border-base-300 hover:bg-base-300"
                  ]}
                >
                  {diff}
                </button>
              </div>
            </div>
          </div>
        </div>

        <%!-- Drills Grid --%>
        <div class="max-w-6xl mx-auto px-4 py-6">
          <div id="drills" phx-update="stream" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <div class="hidden only:block col-span-full text-center py-12 text-base-content/50">
              No drills found matching your filters
            </div>

            <.link
              :for={{dom_id, drill} <- @streams.drills}
              id={dom_id}
              navigate={~p"/drills/#{drill.slug}"}
              class="card-hover"
            >
              <div class="bg-base-200 border border-base-300 h-full flex flex-col">
                <div class="px-4 py-3 border-b border-base-300/50 flex items-center justify-between">
                  <div class="flex items-center gap-2">
                    <.icon
                      :if={drill.skill_category}
                      name={drill.skill_category.icon || "hero-bolt"}
                      class={"w-4 h-4 #{drill.skill_category.color}"}
                    />
                    <span class="text-xs text-base-content/60">
                      {if drill.skill_category, do: drill.skill_category.name, else: "General"}
                    </span>
                  </div>
                  <span class={[
                    "text-[10px] font-bold uppercase px-1.5 py-0.5",
                    difficulty_color(drill.difficulty)
                  ]}>
                    {drill.difficulty}
                  </span>
                </div>

                <div class="p-4 flex-1">
                  <h3 class="font-bold text-lg">{drill.name}</h3>
                  <p class="text-sm text-base-content/60 mt-1 line-clamp-2">
                    {drill.description}
                  </p>
                </div>

                <div class="px-4 py-3 border-t border-base-300/50 flex justify-between items-center">
                  <div class="flex items-center gap-3 text-xs text-base-content/50">
                    <span class="flex items-center gap-1">
                      <.icon name="hero-clock" class="w-3.5 h-3.5" />
                      {drill.duration_minutes} min
                    </span>
                  </div>
                  <span class="text-xs font-medium text-accent">
                    +{drill.xp_reward} XP
                  </span>
                </div>
              </div>
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp difficulty_color("beginner"), do: "bg-success/20 text-success"
  defp difficulty_color("intermediate"), do: "bg-warning/20 text-warning"
  defp difficulty_color("advanced"), do: "bg-error/20 text-error"
  defp difficulty_color(_), do: "bg-base-300 text-base-content/60"
end
