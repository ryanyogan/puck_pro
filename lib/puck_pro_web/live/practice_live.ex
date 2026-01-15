defmodule PuckProWeb.PracticeLive do
  @moduledoc """
  Active practice session interface with video capture support.

  Supports two modes:
  - Video mode: Streams video from camera to R2 for AI analysis
  - Manual mode: Traditional shot tracking with tap buttons
  """
  use PuckProWeb, :live_view

  alias PuckPro.Training
  alias PuckPro.Video
  alias PuckPro.Tracking.ShotTracker
  alias PuckProWeb.VideoComponents
  alias PuckProWeb.ManualEntryComponents

  @impl true
  def mount(_params, _session, socket) do
    player = Training.get_or_create_default_player()
    drills = Training.list_drills_with_categories()

    socket =
      socket
      |> assign(:page_title, "Start Practice")
      |> assign(:player, player)
      |> assign(:selected_drill, nil)
      |> assign(:session, nil)
      |> assign(:session_video, nil)
      |> assign(:timer_seconds, 0)
      |> assign(:video_chunks, [])
      # Manual tracking stats
      |> assign(:shots_attempted, 0)
      |> assign(:goals_scored, 0)
      |> assign(:shots_on_goal, 0)
      # Video mode state
      |> assign(:video_mode, true)
      |> assign(:is_recording, false)
      |> assign(:camera_ready, false)
      |> assign(:camera_error, nil)
      # Real-time shot detection state (MediaPipe Pose)
      |> assign(:shot_tracker_ready, false)
      |> assign(:pose_detected, false)
      |> assign(:last_shot_type, nil)
      |> assign(:last_shot_analysis, nil)
      # Developer mode for debugging
      |> assign(:dev_mode, false)
      # Post-session AI analysis toggle (default off for faster feedback)
      |> assign(:run_ai_analysis, false)
      # Analysis state
      |> assign(:analysis_status, nil)
      |> assign(:analysis_stream, "")
      |> stream(:drills, drills)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_drill", %{"drill-id" => drill_id}, socket) do
    drill = Training.get_drill!(String.to_integer(drill_id))
    {:noreply, assign(socket, :selected_drill, drill)}
  end

  @impl true
  def handle_event("toggle_video_mode", _params, socket) do
    {:noreply, assign(socket, :video_mode, !socket.assigns.video_mode)}
  end

  @impl true
  def handle_event("toggle_ai_analysis", _params, socket) do
    {:noreply, assign(socket, :run_ai_analysis, !socket.assigns.run_ai_analysis)}
  end

  @impl true
  def handle_event("toggle_dev_mode", _params, socket) do
    new_dev_mode = !socket.assigns.dev_mode

    socket =
      socket
      |> assign(:dev_mode, new_dev_mode)
      |> push_event("dev_mode_changed", %{enabled: new_dev_mode})

    {:noreply, socket}
  end

  @impl true
  def handle_event("start_session", _params, socket) do
    player = socket.assigns.player
    drill = socket.assigns.selected_drill

    opts = if drill, do: [drill_id: drill.id], else: []

    case Training.start_session(player, opts) do
      {:ok, session} ->
        if connected?(socket), do: :timer.send_interval(1000, self(), :tick)

        # Subscribe to analysis updates
        analysis_topic = "analysis:#{session.id}"
        Phoenix.PubSub.subscribe(PuckPro.PubSub, analysis_topic)

        # Subscribe to shot detection updates
        shots_topic = "shots:#{session.id}"
        Phoenix.PubSub.subscribe(PuckPro.PubSub, shots_topic)

        # Start the shot tracker for this session
        ShotTracker.start_link(session_id: session.id)

        socket =
          socket
          |> assign(:session, session)
          |> assign(:timer_seconds, 0)
          |> maybe_allow_video_upload()

        # If video mode, trigger camera start via JS hook
        # Only record video if AI analysis is enabled, otherwise just do frame sampling
        socket =
          if socket.assigns.video_mode do
            push_event(socket, "start_recording", %{
              record_video: socket.assigns.run_ai_analysis
            })
          else
            socket
          end

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not start session")}
    end
  end

  # Configure video upload with R2Writer
  defp maybe_allow_video_upload(socket) do
    if connected?(socket) && socket.assigns.session && socket.assigns.video_mode do
      allow_upload(socket, :video_stream,
        accept: ~w(.webm .mp4),
        max_entries: 100,
        max_file_size: 50_000_000,
        auto_upload: true,
        writer: fn _name, _entry, socket ->
          {PuckPro.Uploads.R2Writer, session_id: socket.assigns.session.id}
        end
      )
    else
      socket
    end
  end

  # Video recording events from JS hook
  @impl true
  def handle_event("recording_started", params, socket) do
    recording_video = params["recordingVideo"] == true

    socket = socket
      |> assign(:is_recording, true)
      |> assign(:camera_ready, true)

    # Only create session video record if actually recording video for AI
    socket = if recording_video do
      session = socket.assigns.session

      {:ok, video} =
        Video.create_session_video(session.id, %{
          filename: "session_#{session.id}.webm",
          content_type: params["mimeType"] || "video/webm",
          width: params["width"],
          height: params["height"],
          status: "uploading"
        })

      assign(socket, :session_video, video)
    else
      socket
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("recording_stopped", _params, socket) do
    {:noreply, assign(socket, :is_recording, false)}
  end

  @impl true
  def handle_event("camera_error", %{"message" => message}, socket) do
    # Fall back to manual mode on camera error
    {:noreply,
     socket
     |> assign(:camera_error, message)
     |> assign(:video_mode, false)}
  end

  @impl true
  def handle_event("camera_permission", %{"status" => status}, socket) do
    camera_ready = status == "granted"
    {:noreply, assign(socket, :camera_ready, camera_ready)}
  end

  # Handle video chunk upload (base64 chunks from JS)
  @impl true
  def handle_event("video_chunk", %{"data" => data, "chunk" => chunk_num, "size" => size}, socket) do
    IO.puts("[VideoChunk] Received chunk ##{chunk_num}, size: #{size} bytes")

    # Decode base64 and store the chunk
    chunk_data = Base.decode64!(data)

    {:noreply, update(socket, :video_chunks, fn chunks -> chunks ++ [{chunk_num, chunk_data}] end)}
  end

  # Handle MediaPipe pose tracker ready event
  @impl true
  def handle_event("pose_tracker_ready", _params, socket) do
    require Logger
    Logger.info("[PracticeLive] MediaPipe Pose tracker ready")
    {:noreply, assign(socket, :shot_tracker_ready, true)}
  end

  # Handle shot detected from client-side MediaPipe
  @impl true
  def handle_event("shot_detected", shot_data, socket) do
    require Logger
    Logger.info("[PracticeLive] Shot detected from MediaPipe: #{inspect(shot_data)}")

    if socket.assigns.session do
      ShotTracker.record_shot(socket.assigns.session.id, shot_data)
    end

    {:noreply, socket}
  end

  # Handle pose tracker error (fallback to manual)
  @impl true
  def handle_event("pose_tracker_error", %{"message" => message}, socket) do
    require Logger
    Logger.warning("[PracticeLive] Pose tracker error: #{message}")
    # Continue with manual tracking - buttons still work
    {:noreply, socket}
  end

  # Manual tracking events
  @impl true
  def handle_event("add_shot", _params, socket) do
    {:noreply, update(socket, :shots_attempted, &(&1 + 1))}
  end

  @impl true
  def handle_event("add_goal", _params, socket) do
    {:noreply,
     socket
     |> update(:shots_attempted, &(&1 + 1))
     |> update(:shots_on_goal, &(&1 + 1))
     |> update(:goals_scored, &(&1 + 1))}
  end

  @impl true
  def handle_event("add_on_goal", _params, socket) do
    {:noreply,
     socket
     |> update(:shots_attempted, &(&1 + 1))
     |> update(:shots_on_goal, &(&1 + 1))}
  end

  @impl true
  def handle_event("increment", %{"field" => field}, socket) do
    field_atom = String.to_existing_atom(field)
    {:noreply, update(socket, field_atom, &(&1 + 1))}
  end

  @impl true
  def handle_event("decrement", %{"field" => field}, socket) do
    field_atom = String.to_existing_atom(field)
    current = Map.get(socket.assigns, field_atom, 0)
    {:noreply, assign(socket, field_atom, max(0, current - 1))}
  end

  @impl true
  def handle_event("complete_session", _params, socket) do
    require Logger
    Logger.info("[PracticeLive] 1. complete_session clicked!")

    session = socket.assigns.session

    # Stop the shot tracker (async now)
    Logger.info("[PracticeLive] 2. Stopping shot tracker...")
    ShotTracker.stop(session.id)
    Logger.info("[PracticeLive] 3. Shot tracker stop initiated")

    # Stop recording if active
    socket =
      if socket.assigns.is_recording do
        push_event(socket, "stop_recording", %{})
      else
        socket
      end

    stats = %{
      shots_attempted: socket.assigns.shots_attempted,
      shots_on_goal: socket.assigns.shots_on_goal,
      goals_scored: socket.assigns.goals_scored,
      xp_earned: calculate_xp(socket.assigns)
    }

    Logger.info("[PracticeLive] 4. Calling Training.complete_session...")
    case Training.complete_session(session, stats) do
      {:ok, completed_session} ->
        Logger.info("[PracticeLive] 5. Session completed in DB")

        # Capture all data needed for background work
        player_id = socket.assigns.player.id
        timer_seconds = socket.assigns.timer_seconds
        session_video = socket.assigns.session_video
        run_ai_analysis = socket.assigns.run_ai_analysis
        session_id = completed_session.id

        # Get chunks reference
        chunks = socket.assigns.video_chunks
        chunk_count = length(chunks)
        Logger.info("[PracticeLive] 6. Have #{chunk_count} video chunks")

        # Run ALL background work async - don't block navigation
        if chunk_count > 0 do
          Task.Supervisor.start_child(PuckPro.TaskSupervisor, fn ->
            complete_session_async(
              player_id,
              stats,
              timer_seconds,
              chunks,
              session_id,
              session_video,
              run_ai_analysis
            )
          end)
        else
          # No video, just update player stats async
          Task.Supervisor.start_child(PuckPro.TaskSupervisor, fn ->
            player = Training.get_player!(player_id)
            Training.update_player(player, %{
              total_sessions: player.total_sessions + 1,
              total_shots: player.total_shots + stats.shots_attempted,
              total_goals: player.total_goals + stats.goals_scored,
              total_practice_minutes: player.total_practice_minutes + div(timer_seconds, 60)
            })
            Training.award_xp(player, stats.xp_earned)
            Training.update_streak(player)
          end)
        end

        Logger.info("[PracticeLive] 7. Navigating to session #{session_id}")
        {:noreply,
         socket
         |> put_flash(:info, "Great practice! +#{stats.xp_earned} XP")
         |> push_navigate(to: ~p"/sessions/#{session_id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save session")}
    end
  end

  # Timer tick
  @impl true
  def handle_info(:tick, socket) do
    {:noreply, update(socket, :timer_seconds, &(&1 + 1))}
  end

  # Shot tracker ready
  @impl true
  def handle_info({:tracker_ready, _session_id}, socket) do
    {:noreply, assign(socket, :shot_tracker_ready, true)}
  end

  # Shot detected from ShotTracker
  @impl true
  def handle_info({:shot_detected, result, stats}, socket) do
    require Logger
    Logger.info("[PracticeLive] RECEIVED shot_detected: #{result}, total=#{stats.total_shots}")

    # Update our local stats from the tracker
    socket =
      socket
      |> assign(:shots_attempted, stats.total_shots)
      |> assign(:goals_scored, stats.goals)
      |> assign(:shots_on_goal, stats.on_goal)
      |> assign(:last_shot_type, result)

    # Clear the shot indicator after 2 seconds
    Process.send_after(self(), :clear_last_shot, 2000)

    {:noreply, socket}
  end

  # Clear the last shot indicator
  @impl true
  def handle_info(:clear_last_shot, socket) do
    {:noreply, assign(socket, :last_shot_type, nil)}
  end

  # Handle shot analysis from ShotTracker (for form feedback)
  @impl true
  def handle_info({:shot_analysis, analysis}, socket) do
    {:noreply, assign(socket, :last_shot_analysis, analysis)}
  end

  # Analysis PubSub messages
  @impl true
  def handle_info({:analysis_chunk, chunk}, socket) do
    {:noreply, update(socket, :analysis_stream, &(&1 <> chunk))}
  end

  @impl true
  def handle_info(:analysis_done, socket) do
    {:noreply, assign(socket, :analysis_status, "complete")}
  end

  @impl true
  def handle_info({:analysis_complete, _result}, socket) do
    {:noreply, assign(socket, :analysis_status, "complete")}
  end

  @impl true
  def handle_info({:analysis_error, _reason}, socket) do
    {:noreply, assign(socket, :analysis_status, "failed")}
  end

  defp calculate_xp(assigns) do
    base_xp = if assigns.selected_drill, do: assigns.selected_drill.xp_reward, else: 10
    goal_bonus = assigns.goals_scored * 2
    time_bonus = div(assigns.timer_seconds, 60) * 1

    base_xp + goal_bonus + time_bonus
  end

  defp format_time(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{String.pad_leading("#{minutes}", 2, "0")}:#{String.pad_leading("#{secs}", 2, "0")}"
  end

  # Async session completion - runs in background task
  defp complete_session_async(player_id, stats, timer_seconds, chunks, session_id, session_video, run_ai_analysis) do
    alias PuckPro.Storage.R2
    require Logger

    # Update player stats
    player = Training.get_player!(player_id)

    Training.update_player(player, %{
      total_sessions: player.total_sessions + 1,
      total_shots: player.total_shots + stats.shots_attempted,
      total_goals: player.total_goals + stats.goals_scored,
      total_practice_minutes: player.total_practice_minutes + div(timer_seconds, 60)
    })

    Training.award_xp(player, stats.xp_earned)
    Training.update_streak(player)

    # Upload video if we have chunks
    if length(chunks) > 0 do
      # Sort chunks by number and combine
      sorted_chunks = Enum.sort_by(chunks, fn {num, _data} -> num end)
      video_data = Enum.map(sorted_chunks, fn {_num, data} -> data end) |> IO.iodata_to_binary()

      Logger.info("[Upload] Combined video size: #{byte_size(video_data)} bytes")

      # Write to temp file and upload
      temp_path = Path.join(System.tmp_dir!(), "session_#{session_id}_#{:os.system_time(:millisecond)}.webm")
      File.write!(temp_path, video_data)

      case R2.upload_video(temp_path, session_id) do
        {:ok, r2_key} ->
          Logger.info("[Upload] Video uploaded to R2: #{r2_key}")

          # Update the session video record with R2 info
          if session_video do
            Video.update_session_video(session_video, %{
              r2_key: r2_key,
              r2_url: R2.public_url(r2_key),
              file_size: byte_size(video_data),
              status: "uploaded"
            })

            # Only run AI analysis if enabled
            if run_ai_analysis do
              Logger.info("[Upload] Starting AI video analysis...")
              Video.process_session_video(session_id)
            else
              Logger.info("[Upload] AI analysis disabled, skipping")
            end
          end

          # Cleanup temp file
          File.rm(temp_path)

        {:error, reason} ->
          Logger.error("[Upload] Failed to upload video: #{inspect(reason)}")
          File.rm(temp_path)
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen">
        <%= if @session do %>
          <%!-- Active Session View --%>
          <div class="max-w-2xl mx-auto px-4 py-4 sm:py-8">
            <%!-- Timer --%>
            <div class="text-center mb-4 sm:mb-8">
              <div class="text-5xl sm:text-6xl font-mono font-bold text-primary">
                {format_time(@timer_seconds)}
              </div>
              <div :if={@selected_drill} class="mt-2 text-base-content/60">
                {@selected_drill.name}
              </div>
              <div :if={!@selected_drill} class="mt-2 text-base-content/60">
                Free Practice
              </div>
            </div>

            <%!-- Video Capture (when in video mode) --%>
            <div :if={@video_mode} class="mb-4 sm:mb-6">
              <VideoComponents.camera_capture
                is_recording={@is_recording}
                camera_ready={@camera_ready}
                timer_seconds={@timer_seconds}
                camera_error={@camera_error}
                uploads={@uploads}
                dev_mode={@dev_mode}
              />
            </div>

            <%!-- Pose Tracking Status Panel (when in video mode) --%>
            <div :if={@video_mode && @is_recording} class="mb-4 p-3 bg-base-200 border border-base-300 rounded-lg">
              <div class="flex items-center justify-between mb-2">
                <span class="text-xs font-bold uppercase tracking-wider text-base-content/50">
                  Pose Tracking
                </span>
                <span class={[
                  "text-xs px-2 py-0.5 rounded",
                  @shot_tracker_ready && "bg-success/20 text-success",
                  !@shot_tracker_ready && "bg-warning/20 text-warning"
                ]}>
                  {if @shot_tracker_ready, do: "Active", else: "Loading..."}
                </span>
              </div>

              <%!-- Pose Status --%>
              <div class="flex items-center justify-center gap-3 py-2">
                <div class={[
                  "flex items-center gap-2 px-4 py-2 rounded-lg",
                  @shot_tracker_ready && "bg-success/20 border border-success",
                  !@shot_tracker_ready && "bg-base-300"
                ]}>
                  <.icon
                    name={if @shot_tracker_ready, do: "hero-user", else: "hero-arrow-path"}
                    class={if @shot_tracker_ready, do: "w-5 h-5 text-success", else: "w-5 h-5 text-warning animate-spin"}
                  />
                  <span class={[
                    "text-sm font-medium",
                    @shot_tracker_ready && "text-success",
                    !@shot_tracker_ready && "text-warning"
                  ]}>
                    {if @shot_tracker_ready, do: "MediaPipe Ready", else: "Initializing MediaPipe..."}
                  </span>
                </div>
              </div>

              <%!-- Helpful message --%>
              <div class="mt-2 text-center text-xs text-base-content/60">
                {if @shot_tracker_ready,
                  do: "Stand in frame - shots detected via wrist motion at 30fps",
                  else: "Loading pose detection model..."}
              </div>

              <%!-- Dev Mode Toggle (inline during session) --%>
              <div class="mt-3 pt-3 border-t border-base-300 flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <.icon name="hero-code-bracket" class="w-4 h-4 text-warning" />
                  <span class="text-xs font-medium">Dev Mode (Skeleton)</span>
                </div>
                <button
                  phx-click="toggle_dev_mode"
                  class={[
                    "relative inline-flex h-5 w-9 items-center rounded-full transition-colors",
                    @dev_mode && "bg-warning",
                    !@dev_mode && "bg-base-300"
                  ]}
                >
                  <span class={[
                    "inline-block h-3 w-3 transform rounded-full bg-white transition-transform",
                    @dev_mode && "translate-x-5",
                    !@dev_mode && "translate-x-1"
                  ]}>
                  </span>
                </button>
              </div>
            </div>

            <%!-- Dev Mode Legend (when dev mode is on) - Detection colors --%>
            <div :if={@dev_mode} class="mb-4 p-2 bg-base-300/50 border border-warning/30 rounded-lg">
              <div class="flex items-center gap-3 justify-center text-xs flex-wrap">
                <div class="flex items-center gap-1">
                  <div class="w-3 h-3 bg-green-500 rounded"></div>
                  <span>Player</span>
                </div>
                <div class="flex items-center gap-1">
                  <div class="w-3 h-3 bg-orange-500 rounded"></div>
                  <span>Stick</span>
                </div>
                <div class="flex items-center gap-1">
                  <div class="w-3 h-3 bg-cyan-500 rounded"></div>
                  <span>Puck</span>
                </div>
                <div class="flex items-center gap-1">
                  <div class="w-3 h-3 bg-red-500 rounded"></div>
                  <span>Wrists</span>
                </div>
                <div class="flex items-center gap-1">
                  <div class="w-3 h-3 bg-yellow-500 rounded"></div>
                  <span>Knees</span>
                </div>
              </div>
            </div>

            <%!-- Last Shot Flash (shows briefly when a shot is detected) --%>
            <div
              :if={@last_shot_type}
              class={[
                "mb-4 p-3 text-center rounded-lg font-bold text-lg animate-pulse",
                @last_shot_type == :goal && "bg-success/20 text-success border border-success",
                @last_shot_type == :on_goal && "bg-warning/20 text-warning border border-warning",
                @last_shot_type == :miss && "bg-error/20 text-error border border-error"
              ]}
            >
              {case @last_shot_type do
                :goal -> "GOAL!"
                :on_goal -> "On Goal"
                :miss -> "Miss"
              end}
            </div>

            <%!-- Stats --%>
            <div class="grid grid-cols-3 gap-3 sm:gap-4 mb-4 sm:mb-8">
              <div class="bg-base-200 border border-base-300 p-3 sm:p-4 text-center rounded-lg">
                <div class="text-2xl sm:text-3xl font-bold stat-value">{@shots_attempted}</div>
                <div class="text-xs text-base-content/50">Shots</div>
              </div>
              <div class="bg-base-200 border border-base-300 p-3 sm:p-4 text-center rounded-lg">
                <div class="text-2xl sm:text-3xl font-bold stat-value text-warning">
                  {@shots_on_goal}
                </div>
                <div class="text-xs text-base-content/50">On Goal</div>
              </div>
              <div class="bg-base-200 border border-base-300 p-3 sm:p-4 text-center rounded-lg">
                <div class="text-2xl sm:text-3xl font-bold stat-value text-success">
                  {@goals_scored}
                </div>
                <div class="text-xs text-base-content/50">Goals</div>
              </div>
            </div>

            <%!-- Manual Shot Tracking (when not in video mode or as supplement) --%>
            <div :if={!@video_mode} class="mb-4 sm:mb-8">
              <ManualEntryComponents.quick_shot_tracker
                shots={@shots_attempted}
                goals={@goals_scored}
                on_goal={@shots_on_goal}
              />
            </div>

            <%!-- Quick action buttons (visible in both modes for manual tracking) --%>
            <div :if={@video_mode} class="grid grid-cols-3 gap-3 mb-4 sm:mb-8">
              <button
                phx-click="add_shot"
                class="py-4 bg-base-200 border border-base-300 text-sm font-bold hover:bg-base-300 transition-colors rounded-lg touch-manipulation"
              >
                <.icon name="hero-x-mark" class="w-6 h-6 mx-auto mb-1 text-error" />
                Miss
              </button>
              <button
                phx-click="add_on_goal"
                class="py-4 bg-warning/20 border border-warning text-sm font-bold hover:bg-warning/30 transition-colors rounded-lg touch-manipulation"
              >
                <.icon name="hero-arrow-right" class="w-6 h-6 mx-auto mb-1 text-warning" />
                On Goal
              </button>
              <button
                phx-click="add_goal"
                class="py-4 bg-success/20 border border-success text-sm font-bold hover:bg-success/30 transition-colors rounded-lg touch-manipulation"
              >
                <.icon name="hero-check" class="w-6 h-6 mx-auto mb-1 text-success" />
                Goal!
              </button>
            </div>

            <%!-- XP Preview --%>
            <div class="text-center mb-4 sm:mb-6">
              <span class="text-sm text-base-content/50">Earning:</span>
              <span class="text-lg font-bold text-accent ml-2">+{calculate_xp(assigns)} XP</span>
            </div>

            <%!-- Complete Button --%>
            <button
              phx-click="complete_session"
              class="w-full py-4 bg-primary text-primary-content text-lg font-bold hover:bg-primary/90 transition-colors rounded-lg"
            >
              Complete Practice
            </button>
          </div>
        <% else %>
          <%!-- Session Setup View --%>
          <div class="bg-base-200 border-b border-base-300">
            <div class="max-w-6xl mx-auto px-4 py-6">
              <h1 class="text-2xl font-bold">Start Practice</h1>
              <p class="text-base-content/60 mt-1">
                Pick a drill or start a free practice session
              </p>
            </div>
          </div>

          <div class="max-w-6xl mx-auto px-4 py-6">
            <%!-- Video Mode Toggle --%>
            <div class="mb-4 p-4 bg-base-200 border border-base-300 rounded-lg">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <.icon
                    name={if @video_mode, do: "hero-video-camera", else: "hero-hand-raised"}
                    class="w-6 h-6 text-primary"
                  />
                  <div>
                    <div class="font-medium">
                      {if @video_mode, do: "Video Mode", else: "Manual Mode"}
                    </div>
                    <div class="text-xs text-base-content/50">
                      {if @video_mode,
                        do: "Real-time shot detection via camera",
                        else: "Track shots manually with taps"}
                    </div>
                  </div>
                </div>
                <button
                  phx-click="toggle_video_mode"
                  class={[
                    "relative inline-flex h-6 w-11 items-center rounded-full transition-colors",
                    @video_mode && "bg-primary",
                    !@video_mode && "bg-base-300"
                  ]}
                >
                  <span class={[
                    "inline-block h-4 w-4 transform rounded-full bg-white transition-transform",
                    @video_mode && "translate-x-6",
                    !@video_mode && "translate-x-1"
                  ]}>
                  </span>
                </button>
              </div>
            </div>

            <%!-- AI Analysis Toggle (only visible in video mode) --%>
            <div :if={@video_mode} class="mb-4 p-4 bg-base-200 border border-base-300 rounded-lg">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <.icon name="hero-sparkles" class="w-6 h-6 text-accent" />
                  <div>
                    <div class="font-medium">Post-Session AI Analysis</div>
                    <div class="text-xs text-base-content/50">
                      {if @run_ai_analysis,
                        do: "Claude analyzes video after session",
                        else: "Skip AI analysis for faster results"}
                    </div>
                  </div>
                </div>
                <button
                  phx-click="toggle_ai_analysis"
                  class={[
                    "relative inline-flex h-6 w-11 items-center rounded-full transition-colors",
                    @run_ai_analysis && "bg-accent",
                    !@run_ai_analysis && "bg-base-300"
                  ]}
                >
                  <span class={[
                    "inline-block h-4 w-4 transform rounded-full bg-white transition-transform",
                    @run_ai_analysis && "translate-x-6",
                    !@run_ai_analysis && "translate-x-1"
                  ]}>
                  </span>
                </button>
              </div>
            </div>

            <%!-- Developer Mode Toggle (only visible in video mode) --%>
            <div :if={@video_mode} class="mb-6 p-4 bg-base-200 border border-base-300 rounded-lg">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <.icon name="hero-code-bracket" class="w-6 h-6 text-warning" />
                  <div>
                    <div class="font-medium">Developer Mode</div>
                    <div class="text-xs text-base-content/50">
                      {if @dev_mode,
                        do: "Showing detection bounding boxes",
                        else: "Show bounding boxes for debugging"}
                    </div>
                  </div>
                </div>
                <button
                  phx-click="toggle_dev_mode"
                  class={[
                    "relative inline-flex h-6 w-11 items-center rounded-full transition-colors",
                    @dev_mode && "bg-warning",
                    !@dev_mode && "bg-base-300"
                  ]}
                >
                  <span class={[
                    "inline-block h-4 w-4 transform rounded-full bg-white transition-transform",
                    @dev_mode && "translate-x-6",
                    !@dev_mode && "translate-x-1"
                  ]}>
                  </span>
                </button>
              </div>
            </div>

            <%!-- Selected Drill Preview --%>
            <div :if={@selected_drill} class="mb-6 p-4 bg-base-200 border-2 border-primary rounded-lg">
              <div class="flex items-start justify-between">
                <div>
                  <h3 class="text-lg font-bold">{@selected_drill.name}</h3>
                  <p class="text-sm text-base-content/60 mt-1">{@selected_drill.description}</p>
                </div>
                <button
                  phx-click="select_drill"
                  phx-value-drill-id=""
                  class="text-base-content/50 hover:text-base-content"
                >
                  <.icon name="hero-x-mark" class="w-5 h-5" />
                </button>
              </div>
            </div>

            <%!-- Start Button --%>
            <button
              phx-click="start_session"
              class="w-full py-4 bg-success text-success-content text-lg font-bold hover:bg-success/90 transition-colors mb-6 rounded-lg"
            >
              <.icon name="hero-play" class="w-6 h-6 inline-block mr-2" />
              {if @selected_drill, do: "Start Drill", else: "Start Free Practice"}
            </button>

            <%!-- Drill Selection --%>
            <h2 class="text-lg font-bold mb-4">Or pick a drill:</h2>
            <div id="drills" phx-update="stream" class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <button
                :for={{dom_id, drill} <- @streams.drills}
                id={dom_id}
                phx-click="select_drill"
                phx-value-drill-id={drill.id}
                class={[
                  "p-4 text-left border transition-colors",
                  @selected_drill && @selected_drill.id == drill.id && "bg-primary/10 border-primary",
                  !(@selected_drill && @selected_drill.id == drill.id) && "bg-base-200 border-base-300 hover:bg-base-300"
                ]}
              >
                <div class="font-medium">{drill.name}</div>
                <div class="text-xs text-base-content/60 mt-1">{drill.duration_minutes} min</div>
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
