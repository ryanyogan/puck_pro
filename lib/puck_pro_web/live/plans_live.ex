defmodule PuckProWeb.PlansLive do
  @moduledoc """
  Browse training plans and enroll in them.
  """
  use PuckProWeb, :live_view

  alias PuckPro.Training

  @impl true
  def mount(_params, _session, socket) do
    player = Training.get_or_create_default_player()
    plans = Training.list_training_plans()
    active_plans = Training.list_player_active_plans(player.id)

    active_plan_ids = Enum.map(active_plans, & &1.training_plan_id)

    socket =
      socket
      |> assign(:page_title, "Training Plans")
      |> assign(:player, player)
      |> assign(:active_plan_ids, active_plan_ids)
      |> stream(:plans, plans)

    {:ok, socket}
  end

  @impl true
  def handle_event("enroll", %{"plan-id" => plan_id}, socket) do
    plan = Training.get_training_plan!(String.to_integer(plan_id))

    case Training.enroll_player_in_plan(socket.assigns.player, plan) do
      {:ok, _player_plan} ->
        active_plans = Training.list_player_active_plans(socket.assigns.player.id)
        active_plan_ids = Enum.map(active_plans, & &1.training_plan_id)

        {:noreply,
         socket
         |> assign(:active_plan_ids, active_plan_ids)
         |> put_flash(:info, "Enrolled in #{plan.name}!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not enroll in plan")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen">
        <%!-- Header --%>
        <div class="bg-gradient-to-r from-primary/20 via-base-200 to-accent/20 border-b border-base-300">
          <div class="max-w-6xl mx-auto px-4 py-6">
            <h1 class="text-2xl font-bold">Training Plans</h1>
            <p class="text-base-content/60 mt-1">
              Choose a path and level up your game!
            </p>
          </div>
        </div>

        <%!-- Plans Grid --%>
        <div class="max-w-6xl mx-auto px-4 py-6">
          <div id="plans" phx-update="stream" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <div
              :for={{dom_id, plan} <- @streams.plans}
              id={dom_id}
              class={[
                "bg-base-200 border border-base-300 flex flex-col",
                plan.id in @active_plan_ids && "ring-2 ring-success"
              ]}
            >
              <%!-- Plan Header --%>
              <div class={[
                "px-4 py-3 border-b border-base-300/50",
                "bg-gradient-to-r from-#{String.replace(plan.color || "text-primary", "text-", "")}/10 to-transparent"
              ]}>
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-2">
                    <.icon
                      name={plan.icon || "hero-academic-cap"}
                      class={"w-5 h-5 #{plan.color}"}
                    />
                    <span class={[
                      "text-[10px] font-bold uppercase px-1.5 py-0.5",
                      difficulty_color(plan.difficulty)
                    ]}>
                      {plan.difficulty}
                    </span>
                  </div>
                  <span :if={plan.id in @active_plan_ids} class="text-xs text-success font-medium">
                    Active
                  </span>
                </div>
              </div>

              <%!-- Plan Content --%>
              <div class="p-4 flex-1">
                <h3 class="font-bold text-xl">{plan.name}</h3>
                <p class="text-sm text-base-content/60 mt-2">
                  {plan.description}
                </p>

                <%!-- Plan Stats --%>
                <div class="mt-4 flex items-center gap-4 text-sm">
                  <div class="flex items-center gap-1 text-base-content/60">
                    <.icon name="hero-calendar" class="w-4 h-4" />
                    <span>{plan.estimated_weeks} weeks</span>
                  </div>
                </div>

                <%!-- Badge Preview --%>
                <div :if={plan.badge_name} class="mt-4 p-3 bg-base-300/30 flex items-center gap-3">
                  <div class="w-10 h-10 bg-accent/20 flex items-center justify-center">
                    <.icon name={plan.badge_icon || "hero-trophy"} class="w-6 h-6 text-accent" />
                  </div>
                  <div>
                    <div class="text-xs text-base-content/50">Complete to unlock</div>
                    <div class="font-medium text-accent">{plan.badge_name}</div>
                  </div>
                </div>
              </div>

              <%!-- Plan Footer --%>
              <div class="px-4 py-3 border-t border-base-300/50">
                <div class="flex items-center justify-between">
                  <span class="text-sm font-medium text-accent">
                    +{plan.xp_reward} XP
                  </span>

                  <.link
                    :if={plan.id in @active_plan_ids}
                    navigate={~p"/plans/#{plan.slug}"}
                    class="px-4 py-2 bg-primary text-primary-content text-sm font-medium hover:bg-primary/90 transition-colors"
                  >
                    Continue
                  </.link>

                  <button
                    :if={plan.id not in @active_plan_ids}
                    phx-click="enroll"
                    phx-value-plan-id={plan.id}
                    class="px-4 py-2 bg-success text-success-content text-sm font-medium hover:bg-success/90 transition-colors"
                  >
                    Start Plan
                  </button>
                </div>
              </div>
            </div>
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
