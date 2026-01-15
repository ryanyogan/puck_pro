defmodule PuckPro.Tracking.ShotTracker do
  @moduledoc """
  Server-side shot statistics tracking for practice sessions.

  Shot detection happens client-side via MediaPipe Pose at 30fps.
  This module handles:
  - Shot statistics aggregation
  - PubSub broadcasts for real-time UI updates
  - Shot analysis storage for session review

  The client sends shot events with form analysis data:
  - velocity: wrist speed during shot
  - shoulder_rotation: upper body rotation
  - hip_rotation: lower body rotation
  - follow_through: whether wrist ended above shoulder
  - weight_transfer: hip movement during shot
  - knee_bend: stance depth
  """
  use GenServer
  require Logger

  @pubsub PuckPro.PubSub

  # Client API

  @doc """
  Start a shot tracker for a session.
  """
  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    name = via_tuple(session_id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Record a shot detected client-side via MediaPipe.
  """
  def record_shot(session_id, shot_data) when is_map(shot_data) do
    case whereis(session_id) do
      nil -> {:error, :not_started}
      pid -> GenServer.cast(pid, {:record_shot, shot_data})
    end
  end

  @doc """
  Get current shot stats for a session.
  """
  def get_stats(session_id) do
    case whereis(session_id) do
      nil -> {:error, :not_started}
      pid -> GenServer.call(pid, :get_stats)
    end
  end

  @doc """
  Stop tracking for a session.
  """
  def stop(session_id) do
    case whereis(session_id) do
      nil -> :ok
      pid ->
        # Stop async to avoid blocking
        Task.start(fn -> GenServer.stop(pid, :normal, 5000) end)
        :ok
    end
  end

  @doc """
  Check if tracker is running for a session.
  """
  def running?(session_id) do
    whereis(session_id) != nil
  end

  defp whereis(session_id) do
    case Registry.lookup(PuckPro.ShotTrackerRegistry, session_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp via_tuple(session_id) do
    {:via, Registry, {PuckPro.ShotTrackerRegistry, session_id}}
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    topic = "shots:#{session_id}"

    Logger.info("[ShotTracker] Starting for session #{session_id} (MediaPipe mode)")

    state = %{
      session_id: session_id,
      topic: topic,
      # Shot statistics
      total_shots: 0,
      goals: 0,
      on_goal: 0,
      misses: 0,
      # Shot analysis history
      shot_analyses: [],
      # Timing
      started_at: DateTime.utc_now()
    }

    # Notify client that tracker is ready
    broadcast(topic, {:tracker_ready, session_id})

    {:ok, state}
  end

  @impl true
  def handle_cast({:record_shot, shot_data}, state) do
    Logger.info("[ShotTracker] Recording shot: #{inspect(shot_data)}")

    # Classify shot result based on form analysis
    result = classify_shot(shot_data)

    # Update stats
    state = update_shot_stats(state, result)

    # Store shot analysis for session review
    analysis = %{
      timestamp: shot_data["timestamp"] || shot_data[:timestamp],
      velocity: shot_data["velocity"] || shot_data[:velocity],
      shoulder_rotation: shot_data["shoulder_rotation"] || shot_data[:shoulder_rotation],
      hip_rotation: shot_data["hip_rotation"] || shot_data[:hip_rotation],
      follow_through: shot_data["follow_through"] || shot_data[:follow_through],
      weight_transfer: shot_data["weight_transfer"] || shot_data[:weight_transfer],
      knee_bend: shot_data["knee_bend"] || shot_data[:knee_bend],
      result: result
    }

    state = %{state | shot_analyses: [analysis | state.shot_analyses]}

    # Broadcast for real-time UI
    broadcast_shot(state, result, analysis)

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_shots: state.total_shots,
      goals: state.goals,
      on_goal: state.on_goal,
      misses: state.misses,
      shot_analyses: Enum.reverse(state.shot_analyses),
      started_at: state.started_at
    }
    {:reply, {:ok, stats}, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[ShotTracker] Stopping for session #{state.session_id}: #{inspect(reason)}")
    :ok
  end

  # Private Functions

  # Classify shot result based on form analysis from MediaPipe.
  # Since we can't detect the puck or net with pose estimation,
  # we use form quality as a proxy for shot success:
  # - Good form (follow-through + rotation) = Goal
  # - Partial form = On Goal
  # - Poor form = Miss
  # Manual buttons are still available for accurate tracking.
  defp classify_shot(shot_data) do
    follow_through = shot_data["follow_through"] || shot_data[:follow_through] || 0
    shoulder_rotation = shot_data["shoulder_rotation"] || shot_data[:shoulder_rotation] || 0
    hip_rotation = shot_data["hip_rotation"] || shot_data[:hip_rotation] || 0
    velocity = shot_data["velocity"] || shot_data[:velocity] || 0

    # Calculate a form score
    rotation_score = abs(shoulder_rotation) + abs(hip_rotation)

    cond do
      # Excellent form: good follow-through AND rotation AND velocity
      follow_through > 0.5 and rotation_score > 0.5 and velocity > 2.0 ->
        :goal

      # Good form: decent follow-through OR good rotation
      follow_through > 0.3 or rotation_score > 0.3 ->
        :on_goal

      # Poor form
      true ->
        :miss
    end
  end

  defp update_shot_stats(state, result) do
    state = %{state | total_shots: state.total_shots + 1}

    case result do
      :goal -> %{state | goals: state.goals + 1, on_goal: state.on_goal + 1}
      :on_goal -> %{state | on_goal: state.on_goal + 1}
      :miss -> %{state | misses: state.misses + 1}
    end
  end

  defp broadcast_shot(state, result, analysis) do
    stats = %{
      total_shots: state.total_shots,
      goals: state.goals,
      on_goal: state.on_goal,
      misses: state.misses,
      last_shot: result
    }

    broadcast(state.topic, {:shot_detected, result, stats})
    broadcast(state.topic, {:shot_analysis, analysis})

    Logger.info("[ShotTracker] Session #{state.session_id}: #{result} - " <>
      "Total: #{stats.total_shots}, Goals: #{stats.goals}, On Goal: #{stats.on_goal}, Misses: #{stats.misses}")
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic, message)
  end
end
