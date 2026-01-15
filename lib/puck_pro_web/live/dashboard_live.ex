defmodule PuckProWeb.DashboardLive do
  @moduledoc """
  Main dashboard - shows player stats, recent activity, and quick actions.
  """
  use PuckProWeb, :live_view

  alias PuckPro.Training
  alias PuckPro.Progress

  @impl true
  def mount(_params, _session, socket) do
    player = Training.get_or_create_default_player()

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:player, player)
      |> assign_async(:recent_sessions, fn -> load_recent_sessions(player.id) end)
      |> assign_async(:weekly_stats, fn -> load_weekly_stats(player.id) end)
      |> assign_async(:achievements, fn -> load_achievements(player.id) end)
      |> assign_async(:skill_progress, fn -> load_skill_progress(player.id) end)

    {:ok, socket}
  end

  defp load_recent_sessions(player_id) do
    sessions = Training.list_recent_sessions(player_id, 5)
    {:ok, %{recent_sessions: sessions}}
  end

  defp load_weekly_stats(player_id) do
    end_date = Date.utc_today()
    start_date = Date.add(end_date, -7)
    stats = Progress.get_stats_summary(player_id, start_date, end_date)
    {:ok, %{weekly_stats: stats}}
  end

  defp load_achievements(player_id) do
    achievements = Progress.list_player_achievements(player_id)
    {:ok, %{achievements: achievements}}
  end

  defp load_skill_progress(player_id) do
    progress = Progress.list_player_skill_progress(player_id)
    {:ok, %{skill_progress: progress}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen">
        <%!-- Hero Header --%>
        <div class="bg-gradient-to-r from-primary/20 via-base-200 to-accent/20 border-b border-base-300">
          <div class="max-w-6xl mx-auto px-4 py-6 sm:py-8">
            <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
              <div>
                <h1 class="text-2xl sm:text-3xl font-bold">
                  Hey, {@player.name}!
                </h1>
                <p class="text-base-content/60 mt-1">
                  Ready to hit the ice? Let's get better today!
                </p>
              </div>

              <%!-- Level Badge --%>
              <div class="flex items-center gap-3 bg-base-200 border border-base-300 px-4 py-2">
                <div class="text-center">
                  <div class="text-2xl font-bold text-accent stat-value">
                    {level_display(@player.level)}
                  </div>
                  <div class="text-[10px] uppercase tracking-wider text-base-content/50">Level</div>
                </div>
                <div class="w-24">
                  <div class="flex justify-between text-[10px] text-base-content/50 mb-1">
                    <span>{@player.xp} XP</span>
                    <span>{PuckPro.Training.Player.xp_for_level(@player.level)} XP</span>
                  </div>
                  <div class="h-2 bg-base-300 rounded-full overflow-hidden">
                    <div
                      class="h-full xp-bar animate-progress-fill"
                      style={"width: #{trunc(PuckPro.Training.Player.level_progress(@player) * 100)}%"}
                    >
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Streak --%>
            <div :if={@player.streak_days > 0} class="mt-4 flex items-center gap-2">
              <.icon name="hero-fire" class="w-5 h-5 text-warning" />
              <span class="font-medium text-warning">{@player.streak_days} day streak!</span>
              <span class="text-sm text-base-content/50">Keep it going!</span>
            </div>
          </div>
        </div>

        <%!-- Quick Actions --%>
        <div class="max-w-6xl mx-auto px-4 py-6">
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <.link navigate={~p"/practice"} class="card-hover">
              <div class="bg-base-200 border border-base-300 p-4 text-center">
                <.icon name="hero-play" class="w-8 h-8 text-success mx-auto mb-2" />
                <div class="font-medium">Start Practice</div>
                <div class="text-xs text-base-content/50">Jump into training</div>
              </div>
            </.link>

            <.link navigate={~p"/practice/random"} class="card-hover">
              <div class="bg-base-200 border border-base-300 p-4 text-center">
                <.icon name="hero-sparkles" class="w-8 h-8 text-accent mx-auto mb-2" />
                <div class="font-medium">Random Drill</div>
                <div class="text-xs text-base-content/50">Surprise me!</div>
              </div>
            </.link>

            <.link navigate={~p"/plans"} class="card-hover">
              <div class="bg-base-200 border border-base-300 p-4 text-center">
                <.icon name="hero-academic-cap" class="w-8 h-8 text-primary mx-auto mb-2" />
                <div class="font-medium">Training Plans</div>
                <div class="text-xs text-base-content/50">Level up skills</div>
              </div>
            </.link>

            <.link navigate={~p"/progress"} class="card-hover">
              <div class="bg-base-200 border border-base-300 p-4 text-center">
                <.icon name="hero-chart-bar" class="w-8 h-8 text-info mx-auto mb-2" />
                <div class="font-medium">My Progress</div>
                <div class="text-xs text-base-content/50">See your stats</div>
              </div>
            </.link>
          </div>
        </div>

        <%!-- Stats Grid --%>
        <div class="max-w-6xl mx-auto px-4 pb-6">
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <%!-- Weekly Stats Card --%>
            <div class="bg-base-200 border border-base-300">
              <div class="px-4 py-2 bg-base-300/50 border-b border-base-300">
                <span class="text-xs font-bold uppercase tracking-wider">This Week</span>
              </div>
              <div class="p-4">
                <.async_result :let={stats} assign={@weekly_stats}>
                  <:loading>
                    <div class="flex items-center justify-center py-8">
                      <div class="w-6 h-6 border-2 border-primary border-t-transparent rounded-full animate-spin"></div>
                    </div>
                  </:loading>
                  <:failed :let={_reason}>
                    <div class="text-center py-8 text-base-content/50">
                      Could not load stats
                    </div>
                  </:failed>

                  <div class="grid grid-cols-3 gap-4">
                    <div class="text-center">
                      <div class="text-2xl font-bold stat-value text-primary">
                        {stats[:total_sessions] || 0}
                      </div>
                      <div class="text-[10px] uppercase tracking-wider text-base-content/50">Sessions</div>
                    </div>
                    <div class="text-center">
                      <div class="text-2xl font-bold stat-value text-success">
                        {stats[:total_goals] || 0}
                      </div>
                      <div class="text-[10px] uppercase tracking-wider text-base-content/50">Goals</div>
                    </div>
                    <div class="text-center">
                      <div class="text-2xl font-bold stat-value text-accent">
                        {stats[:total_xp] || 0}
                      </div>
                      <div class="text-[10px] uppercase tracking-wider text-base-content/50">XP Earned</div>
                    </div>
                  </div>

                  <div class="mt-4 pt-4 border-t border-base-300/50">
                    <div class="flex justify-between text-sm">
                      <span class="text-base-content/60">Practice Time</span>
                      <span class="font-mono font-medium">{stats[:total_minutes] || 0} min</span>
                    </div>
                    <div class="flex justify-between text-sm mt-2">
                      <span class="text-base-content/60">Shots On Goal</span>
                      <span class="font-mono font-medium">{stats[:total_on_goal] || 0} / {stats[:total_shots] || 0}</span>
                    </div>
                  </div>
                </.async_result>
              </div>
            </div>

            <%!-- Recent Sessions Card --%>
            <div class="bg-base-200 border border-base-300">
              <div class="px-4 py-2 bg-base-300/50 border-b border-base-300 flex justify-between items-center">
                <span class="text-xs font-bold uppercase tracking-wider">Recent Sessions</span>
                <.link navigate={~p"/sessions"} class="text-xs text-primary hover:underline">
                  View All
                </.link>
              </div>
              <div class="divide-y divide-base-300/50">
                <.async_result :let={sessions} assign={@recent_sessions}>
                  <:loading>
                    <div class="flex items-center justify-center py-8">
                      <div class="w-6 h-6 border-2 border-primary border-t-transparent rounded-full animate-spin"></div>
                    </div>
                  </:loading>
                  <:failed :let={_reason}>
                    <div class="text-center py-8 text-base-content/50">
                      Could not load sessions
                    </div>
                  </:failed>

                  <div :if={sessions == []} class="p-4 text-center text-base-content/50">
                    No sessions yet. Start practicing!
                  </div>

                  <.link
                    :for={session <- sessions}
                    navigate={~p"/sessions/#{session.id}"}
                    class="block px-4 py-3 hover:bg-base-300/30 transition-colors"
                  >
                    <div class="flex justify-between items-start">
                      <div>
                        <div class="font-medium text-sm">
                          {if session.drill, do: session.drill.name, else: "Free Practice"}
                        </div>
                        <div class="text-xs text-base-content/50">
                          {format_date(session.started_at)}
                        </div>
                      </div>
                      <div class="text-right">
                        <div class="font-mono text-sm">
                          <span class="text-success">{session.goals_scored}</span>
                          <span class="text-base-content/50">/</span>
                          <span>{session.shots_attempted}</span>
                        </div>
                        <div class="text-xs text-accent">+{session.xp_earned} XP</div>
                      </div>
                    </div>
                  </.link>
                </.async_result>
              </div>
            </div>
          </div>
        </div>

        <%!-- Achievements Preview --%>
        <div class="max-w-6xl mx-auto px-4 pb-6">
          <div class="bg-base-200 border border-base-300">
            <div class="px-4 py-2 bg-base-300/50 border-b border-base-300 flex justify-between items-center">
              <span class="text-xs font-bold uppercase tracking-wider">Achievements</span>
              <.link navigate={~p"/achievements"} class="text-xs text-primary hover:underline">
                View All
              </.link>
            </div>
            <div class="p-4">
              <.async_result :let={achievements} assign={@achievements}>
                <:loading>
                  <div class="flex items-center justify-center py-4">
                    <div class="w-6 h-6 border-2 border-primary border-t-transparent rounded-full animate-spin"></div>
                  </div>
                </:loading>
                <:failed :let={_reason}>
                  <div class="text-center py-4 text-base-content/50">
                    Could not load achievements
                  </div>
                </:failed>

                <div :if={achievements == []} class="text-center py-4">
                  <.icon name="hero-trophy" class="w-12 h-12 text-base-content/20 mx-auto mb-2" />
                  <p class="text-base-content/50">Complete sessions to unlock achievements!</p>
                </div>

                <div :if={achievements != []} class="flex flex-wrap gap-2">
                  <div
                    :for={pa <- Enum.take(achievements, 6)}
                    class="flex items-center gap-2 bg-base-300/50 px-3 py-1.5 rounded"
                    title={pa.achievement.description}
                  >
                    <.icon
                      name={pa.achievement.icon || "hero-trophy"}
                      class={"w-4 h-4 #{PuckPro.Progress.Achievement.rarity_color(pa.achievement.rarity)}"}
                    />
                    <span class="text-sm font-medium">{pa.achievement.name}</span>
                  </div>
                </div>
              </.async_result>
            </div>
          </div>
        </div>

        <%!-- Total Stats Footer --%>
        <div class="max-w-6xl mx-auto px-4 pb-8">
          <div class="bg-base-200 border border-base-300 p-4">
            <div class="text-xs font-bold uppercase tracking-wider text-base-content/50 mb-3">
              All-Time Stats
            </div>
            <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
              <div>
                <div class="text-xl font-bold stat-value">{@player.total_sessions}</div>
                <div class="text-xs text-base-content/50">Total Sessions</div>
              </div>
              <div>
                <div class="text-xl font-bold stat-value">{@player.total_practice_minutes}</div>
                <div class="text-xs text-base-content/50">Minutes Practiced</div>
              </div>
              <div>
                <div class="text-xl font-bold stat-value">{@player.total_shots}</div>
                <div class="text-xs text-base-content/50">Total Shots</div>
              </div>
              <div>
                <div class="text-xl font-bold stat-value text-success">{@player.total_goals}</div>
                <div class="text-xs text-base-content/50">Total Goals</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp level_display(level) when level < 10, do: "0#{level}"
  defp level_display(level), do: "#{level}"

  defp format_date(datetime) do
    datetime
    |> DateTime.to_date()
    |> Calendar.strftime("%b %d, %Y")
  end
end
