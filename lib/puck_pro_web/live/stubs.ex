# Stub LiveViews - Placeholder implementations for remaining routes
# These will be fully implemented later

defmodule PuckProWeb.PlanLive do
  use PuckProWeb, :live_view

  alias PuckPro.Training

  def mount(%{"slug" => slug}, _session, socket) do
    plan = Training.get_training_plan_by_slug(slug)

    if plan do
      plan = Training.get_training_plan_with_drills(plan.id)

      {:ok,
       socket
       |> assign(:page_title, plan.name)
       |> assign(:plan, plan)}
    else
      {:ok, push_navigate(socket, to: ~p"/plans")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto px-4 py-6">
        <.link navigate={~p"/plans"} class="text-primary hover:underline mb-4 inline-block">
          &larr; Back to Plans
        </.link>

        <h1 class="text-3xl font-bold">{@plan.name}</h1>
        <p class="text-base-content/60 mt-2">{@plan.description}</p>

        <div class="mt-8">
          <h2 class="text-xl font-bold mb-4">Drills in this plan</h2>
          <div class="space-y-2">
            <div
              :for={pd <- @plan.plan_drills || []}
              class="p-4 bg-base-200 border border-base-300"
            >
              <div class="flex justify-between items-center">
                <div>
                  <div class="font-medium">{pd.drill.name}</div>
                  <div class="text-xs text-base-content/60">Week {pd.week_number}, Day {pd.day_of_week}</div>
                </div>
                <.link navigate={~p"/drills/#{pd.drill.slug}"} class="text-primary text-sm">
                  View Drill &rarr;
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

defmodule PuckProWeb.DrillLive do
  use PuckProWeb, :live_view

  alias PuckPro.Training

  def mount(%{"slug" => slug}, _session, socket) do
    case Training.get_drill_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/drills")}

      drill ->
        drill = PuckPro.Repo.preload(drill, :skill_category)

        {:ok,
         socket
         |> assign(:page_title, drill.name)
         |> assign(:drill, drill)}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto px-4 py-6">
        <.link navigate={~p"/drills"} class="text-primary hover:underline mb-4 inline-block">
          &larr; Back to Drills
        </.link>

        <div class="bg-base-200 border border-base-300 p-6">
          <h1 class="text-3xl font-bold">{@drill.name}</h1>
          <p class="text-base-content/60 mt-2">{@drill.description}</p>

          <div class="mt-6 space-y-4">
            <div>
              <h2 class="font-bold text-lg mb-2">Instructions</h2>
              <div class="prose prose-sm text-base-content/80 whitespace-pre-line">
                {@drill.instructions}
              </div>
            </div>

            <div :if={@drill.tips}>
              <h2 class="font-bold text-lg mb-2">Tips</h2>
              <p class="text-base-content/80">{@drill.tips}</p>
            </div>
          </div>

          <div class="mt-6 pt-6 border-t border-base-300/50">
            <.link
              navigate={~p"/practice"}
              class="inline-block px-6 py-3 bg-success text-success-content font-bold hover:bg-success/90"
            >
              Practice This Drill
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

defmodule PuckProWeb.RandomPracticeLive do
  use PuckProWeb, :live_view

  alias PuckPro.Training

  def mount(_params, _session, socket) do
    drill = Training.get_random_drill()

    if drill do
      {:ok, push_navigate(socket, to: ~p"/drills/#{drill.slug}")}
    else
      {:ok, push_navigate(socket, to: ~p"/drills")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-center justify-center min-h-[50vh]">
        <div class="animate-spin w-8 h-8 border-2 border-primary border-t-transparent rounded-full"></div>
      </div>
    </Layouts.app>
    """
  end
end

defmodule PuckProWeb.SessionsLive do
  use PuckProWeb, :live_view

  alias PuckPro.Training

  def mount(_params, _session, socket) do
    player = Training.get_or_create_default_player()
    sessions = Training.list_recent_sessions(player.id, 50)

    {:ok,
     socket
     |> assign(:page_title, "Sessions")
     |> stream(:sessions, sessions)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto px-4 py-6">
        <h1 class="text-2xl font-bold mb-6">Practice History</h1>

        <div id="sessions" phx-update="stream" class="space-y-2">
          <div class="hidden only:block text-center py-12 text-base-content/50">
            No sessions yet. Start practicing!
          </div>

          <.link
            :for={{dom_id, session} <- @streams.sessions}
            id={dom_id}
            navigate={~p"/sessions/#{session.id}"}
            class="block p-4 bg-base-200 border border-base-300 hover:bg-base-300 transition-colors"
          >
            <div class="flex justify-between items-center">
              <div>
                <div class="font-medium">
                  {if session.drill, do: session.drill.name, else: "Free Practice"}
                </div>
                <div class="text-xs text-base-content/60">
                  {Calendar.strftime(session.started_at, "%b %d, %Y at %I:%M %p")}
                </div>
              </div>
              <div class="text-right">
                <div class="font-mono">
                  <span class="text-success">{session.goals_scored}</span>/{session.shots_attempted}
                </div>
                <div class="text-xs text-accent">+{session.xp_earned} XP</div>
              </div>
            </div>
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

defmodule PuckProWeb.SessionLive do
  use PuckProWeb, :live_view

  alias PuckPro.Training
  alias PuckPro.AI
  alias PuckPro.Video
  alias PuckProWeb.VideoComponents

  def mount(%{"id" => id}, _session, socket) do
    session_id = String.to_integer(id)

    case Training.get_session_with_details(session_id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/sessions")}

      session ->
        # Subscribe to analysis updates
        topic = "analysis:#{session_id}"
        if connected?(socket), do: Phoenix.PubSub.subscribe(PuckPro.PubSub, topic)

        {:ok,
         socket
         |> assign(:page_title, "Session Details")
         |> assign(:session, session)
         |> assign(:analysis_stream, "")
         |> assign(:is_streaming, false)
         # Load analysis and video data asynchronously
         |> assign_async(:analysis_data, fn ->
           analyses = AI.list_analyses_for_session(session_id)
           analysis = List.first(analyses)
           {:ok, %{analysis_data: analysis}}
         end)
         |> assign_async(:video_data, fn ->
           video = Video.get_video_for_session(session_id)
           {:ok, %{video_data: video}}
         end)}
    end
  end

  def handle_info({:analysis_chunk, chunk}, socket) do
    {:noreply,
     socket
     |> update(:analysis_stream, &(&1 <> chunk))
     |> assign(:is_streaming, true)}
  end

  def handle_info(:analysis_done, socket) do
    {:noreply, assign(socket, :is_streaming, false)}
  end

  def handle_info({:analysis_complete, _result}, socket) do
    # Refresh the analysis from DB by re-assigning async
    session_id = socket.assigns.session.id

    {:noreply,
     socket
     |> assign(:is_streaming, false)
     |> assign_async(:analysis_data, fn ->
       analyses = AI.list_analyses_for_session(session_id)
       analysis = List.first(analyses)
       {:ok, %{analysis_data: analysis}}
     end, reset: true)}
  end

  def handle_info({:analysis_error, _reason}, socket) do
    {:noreply, assign(socket, :is_streaming, false)}
  end

  # Helper to extract async result
  defp get_async_result(%Phoenix.LiveView.AsyncResult{ok?: true, result: result}), do: result
  defp get_async_result(_), do: nil

  def render(assigns) do
    # Extract async results for easier template access
    analysis = get_async_result(assigns.analysis_data)
    video = get_async_result(assigns.video_data)

    assigns =
      assigns
      |> Map.put(:analysis, analysis)
      |> Map.put(:video, video)

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto px-4 py-6">
        <.link navigate={~p"/sessions"} class="text-primary hover:underline mb-4 inline-block">
          &larr; Back to Sessions
        </.link>

        <%!-- Session Header --%>
        <div class="bg-base-200 border border-base-300 p-6 rounded-lg">
          <h1 class="text-2xl font-bold">
            {if @session.drill, do: @session.drill.name, else: "Free Practice"}
          </h1>
          <div class="text-base-content/60 mt-1">
            {Calendar.strftime(@session.started_at, "%B %d, %Y at %I:%M %p")}
          </div>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mt-6">
            <div class="p-4 bg-base-300/50 text-center rounded">
              <div class="text-2xl font-bold stat-value">{@session.shots_attempted}</div>
              <div class="text-xs text-base-content/50">Shots</div>
            </div>
            <div class="p-4 bg-base-300/50 text-center rounded">
              <div class="text-2xl font-bold stat-value text-warning">{@session.shots_on_goal}</div>
              <div class="text-xs text-base-content/50">On Goal</div>
            </div>
            <div class="p-4 bg-base-300/50 text-center rounded">
              <div class="text-2xl font-bold stat-value text-success">{@session.goals_scored}</div>
              <div class="text-xs text-base-content/50">Goals</div>
            </div>
            <div class="p-4 bg-base-300/50 text-center rounded">
              <div class="text-2xl font-bold stat-value text-accent">{@session.xp_earned}</div>
              <div class="text-xs text-base-content/50">XP</div>
            </div>
          </div>
        </div>

        <%!-- Loading State for Analysis --%>
        <div :if={@analysis_data.loading} class="mt-6 bg-base-200 border border-base-300 p-8 rounded-lg text-center">
          <div class="animate-spin w-8 h-8 border-2 border-primary border-t-transparent rounded-full mx-auto mb-4"></div>
          <p class="text-base-content/50">Loading analysis...</p>
        </div>

        <%!-- AI Analysis Section --%>
        <%= if @analysis do %>
          <div class="mt-6 space-y-6">
            <%!-- Overall Score --%>
            <div :if={@analysis.overall_score} class="bg-base-200 border border-base-300 p-6 rounded-lg">
              <VideoComponents.overall_score score={@analysis.overall_score} />
            </div>

            <%!-- Form Metrics (Video Analysis) --%>
            <div
              :if={@analysis.form_metrics && map_size(@analysis.form_metrics) > 0}
              class="bg-base-200 border border-base-300 p-6 rounded-lg"
            >
              <h2 class="text-lg font-bold mb-4">Form Analysis</h2>
              <VideoComponents.form_metrics metrics={@analysis.form_metrics} />
            </div>

            <%!-- Technique Scores (Video Analysis) --%>
            <div
              :if={@analysis.technique_scores && map_size(@analysis.technique_scores) > 0}
              class="bg-base-200 border border-base-300 p-6 rounded-lg"
            >
              <h2 class="text-lg font-bold mb-4">Technique</h2>
              <VideoComponents.technique_scores scores={@analysis.technique_scores} />
            </div>

            <%!-- Detected Shots --%>
            <div
              :if={@analysis.detected_shots && length(@analysis.detected_shots) > 0}
              class="bg-base-200 border border-base-300 p-6 rounded-lg"
            >
              <VideoComponents.detected_shots shots={@analysis.detected_shots} />
            </div>

            <%!-- Strengths & Improvements --%>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div
                :if={@analysis.strengths && length(@analysis.strengths) > 0}
                class="bg-base-200 border border-base-300 p-6 rounded-lg"
              >
                <VideoComponents.strengths_list strengths={@analysis.strengths} />
              </div>

              <div
                :if={@analysis.improvements && length(@analysis.improvements) > 0}
                class="bg-base-200 border border-base-300 p-6 rounded-lg"
              >
                <VideoComponents.improvements_list improvements={@analysis.improvements} />
              </div>
            </div>

            <%!-- Summary --%>
            <div :if={@analysis.summary} class="bg-base-200 border border-base-300 p-6 rounded-lg">
              <h2 class="text-lg font-bold mb-3">Coach's Summary</h2>
              <p class="text-base-content/80">{@analysis.summary}</p>
            </div>

            <%!-- Recommended Drills --%>
            <div
              :if={@analysis.recommended_drills && length(@analysis.recommended_drills) > 0}
              class="bg-base-200 border border-base-300 p-6 rounded-lg"
            >
              <h2 class="text-lg font-bold mb-3">Recommended Next Drills</h2>
              <div class="flex flex-wrap gap-2">
                <span
                  :for={drill_slug <- @analysis.recommended_drills}
                  class="px-3 py-1 bg-primary/20 text-primary rounded-full text-sm"
                >
                  {drill_slug}
                </span>
              </div>
            </div>
          </div>
        <% else %>
          <%!-- Streaming Analysis Display --%>
          <div :if={@is_streaming || @analysis_stream != ""} class="mt-6">
            <VideoComponents.analysis_stream
              content={@analysis_stream}
              is_streaming={@is_streaming}
            />
          </div>

          <%!-- No Analysis Yet (only show when not loading and not streaming) --%>
          <div
            :if={!@analysis_data.loading && !@is_streaming && @analysis_stream == ""}
            class="mt-6 bg-base-200 border border-base-300 p-8 rounded-lg text-center"
          >
            <.icon name="hero-cpu-chip" class="w-12 h-12 text-base-content/20 mx-auto mb-4" />
            <p class="text-base-content/50">
              No AI analysis available for this session.
            </p>
            <p class="text-xs text-base-content/30 mt-2">
              Start a new session with video mode enabled to get AI feedback!
            </p>
          </div>
        <% end %>

        <%!-- Video Info --%>
        <div :if={@video} class="mt-6 bg-base-200 border border-base-300 p-4 rounded-lg">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <.icon name="hero-video-camera" class="w-5 h-5 text-primary" />
              <span class="text-sm">Video recorded</span>
            </div>
            <div class="text-xs text-base-content/50">
              {if @video.frame_count > 0, do: "#{@video.frame_count} frames analyzed", else: @video.status}
            </div>
          </div>
        </div>

        <%!-- Video Loading State --%>
        <div :if={@video_data.loading && !@video} class="mt-6 bg-base-200 border border-base-300 p-4 rounded-lg">
          <div class="flex items-center gap-3">
            <div class="animate-spin w-4 h-4 border-2 border-primary border-t-transparent rounded-full"></div>
            <span class="text-sm text-base-content/50">Loading video info...</span>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

defmodule PuckProWeb.ProgressLive do
  use PuckProWeb, :live_view

  alias PuckPro.Training
  alias PuckPro.Progress

  def mount(_params, _session, socket) do
    player = Training.get_or_create_default_player()
    skill_progress = Progress.list_player_skill_progress(player.id)
    daily_stats = Progress.list_daily_stats(player.id, 14)

    {:ok,
     socket
     |> assign(:page_title, "My Progress")
     |> assign(:player, player)
     |> assign(:skill_progress, skill_progress)
     |> assign(:daily_stats, daily_stats)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto px-4 py-6">
        <h1 class="text-2xl font-bold mb-6">My Progress</h1>

        <%!-- Overall Stats --%>
        <div class="bg-base-200 border border-base-300 p-6 mb-6">
          <h2 class="text-lg font-bold mb-4">Overall Stats</h2>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <div class="text-center">
              <div class="text-3xl font-bold stat-value">{@player.level}</div>
              <div class="text-xs text-base-content/50">Level</div>
            </div>
            <div class="text-center">
              <div class="text-3xl font-bold stat-value">{@player.total_sessions}</div>
              <div class="text-xs text-base-content/50">Sessions</div>
            </div>
            <div class="text-center">
              <div class="text-3xl font-bold stat-value text-success">{@player.total_goals}</div>
              <div class="text-xs text-base-content/50">Goals</div>
            </div>
            <div class="text-center">
              <div class="text-3xl font-bold stat-value text-warning">{@player.streak_days}</div>
              <div class="text-xs text-base-content/50">Day Streak</div>
            </div>
          </div>
        </div>

        <%!-- Skill Progress --%>
        <div class="bg-base-200 border border-base-300 p-6">
          <h2 class="text-lg font-bold mb-4">Skill Progress</h2>
          <div :if={@skill_progress == []} class="text-center py-8 text-base-content/50">
            Complete drills to track your skill progress!
          </div>
          <div class="space-y-4">
            <div :for={sp <- @skill_progress} class="flex items-center gap-4">
              <div class="w-24 font-medium">
                {if sp.skill_category, do: sp.skill_category.name, else: "General"}
              </div>
              <div class="flex-1">
                <div class="h-3 bg-base-300 rounded-full overflow-hidden">
                  <div
                    class="h-full bg-primary"
                    style={"width: #{sp.proficiency_score}%"}
                  >
                  </div>
                </div>
              </div>
              <div class="w-12 text-right text-sm font-mono">{sp.proficiency_score}%</div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

defmodule PuckProWeb.AchievementsLive do
  use PuckProWeb, :live_view

  alias PuckPro.Training
  alias PuckPro.Progress

  def mount(_params, _session, socket) do
    player = Training.get_or_create_default_player()
    all_achievements = Progress.list_achievements()
    unlocked = Progress.list_player_achievements(player.id)
    unlocked_ids = Enum.map(unlocked, & &1.achievement_id)

    {:ok,
     socket
     |> assign(:page_title, "Achievements")
     |> assign(:achievements, all_achievements)
     |> assign(:unlocked_ids, unlocked_ids)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto px-4 py-6">
        <h1 class="text-2xl font-bold mb-6">Achievements</h1>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <div
            :for={achievement <- @achievements}
            class={[
              "p-4 border",
              achievement.id in @unlocked_ids && "bg-base-200 border-accent",
              achievement.id not in @unlocked_ids && "bg-base-200/50 border-base-300 opacity-50"
            ]}
          >
            <div class="flex items-center gap-3">
              <div class={[
                "w-12 h-12 flex items-center justify-center",
                achievement.id in @unlocked_ids && "bg-accent/20",
                achievement.id not in @unlocked_ids && "bg-base-300"
              ]}>
                <.icon
                  name={achievement.icon || "hero-trophy"}
                  class={"w-6 h-6 #{if achievement.id in @unlocked_ids, do: achievement.color, else: "text-base-content/30"}"}
                />
              </div>
              <div>
                <div class="font-bold">{achievement.name}</div>
                <div class="text-xs text-base-content/60">{achievement.description}</div>
                <div class="text-xs text-accent mt-1">+{achievement.xp_reward} XP</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
