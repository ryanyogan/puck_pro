defmodule PuckPro.Training.Session do
  @moduledoc """
  Individual practice sessions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(in_progress completed cancelled)
  @analysis_statuses ~w(pending processing completed failed)

  schema "sessions" do
    belongs_to :player, PuckPro.Training.Player
    belongs_to :drill, PuckPro.Training.Drill
    belongs_to :player_plan, PuckPro.Training.PlayerPlan

    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :duration_seconds, :integer
    field :status, :string, default: "in_progress"

    # Session stats
    field :shots_attempted, :integer, default: 0
    field :shots_on_goal, :integer, default: 0
    field :goals_scored, :integer, default: 0

    field :xp_earned, :integer, default: 0
    field :analysis_status, :string, default: "pending"
    field :notes, :string

    has_many :session_videos, PuckPro.Training.SessionVideo
    has_many :ai_analyses, PuckPro.AI.Analysis

    timestamps()
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:player_id, :drill_id, :player_plan_id, :started_at,
                    :completed_at, :duration_seconds, :status, :shots_attempted,
                    :shots_on_goal, :goals_scored, :xp_earned, :analysis_status, :notes])
    |> validate_required([:player_id, :started_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:analysis_status, @analysis_statuses)
    |> validate_number(:shots_attempted, greater_than_or_equal_to: 0)
    |> validate_number(:shots_on_goal, greater_than_or_equal_to: 0)
    |> validate_number(:goals_scored, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:player_id)
    |> foreign_key_constraint(:drill_id)
    |> foreign_key_constraint(:player_plan_id)
  end

  @doc "Calculate shooting percentage"
  def shooting_percentage(%__MODULE__{shots_attempted: 0}), do: 0.0
  def shooting_percentage(%__MODULE__{goals_scored: goals, shots_attempted: shots}) do
    Float.round(goals / shots * 100, 1)
  end

  @doc "Calculate accuracy percentage (shots on goal)"
  def accuracy_percentage(%__MODULE__{shots_attempted: 0}), do: 0.0
  def accuracy_percentage(%__MODULE__{shots_on_goal: on_goal, shots_attempted: shots}) do
    Float.round(on_goal / shots * 100, 1)
  end

  @doc "Duration in minutes"
  def duration_minutes(%__MODULE__{duration_seconds: nil}), do: 0
  def duration_minutes(%__MODULE__{duration_seconds: seconds}) do
    div(seconds, 60)
  end
end
