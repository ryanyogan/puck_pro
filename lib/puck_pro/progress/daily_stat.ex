defmodule PuckPro.Progress.DailyStat do
  @moduledoc """
  Daily statistics for a player - used for streaks and charts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "daily_stats" do
    belongs_to :player, PuckPro.Training.Player

    field :date, :date
    field :sessions_completed, :integer, default: 0
    field :practice_minutes, :integer, default: 0
    field :shots_attempted, :integer, default: 0
    field :shots_on_goal, :integer, default: 0
    field :goals_scored, :integer, default: 0
    field :xp_earned, :integer, default: 0

    timestamps()
  end

  def changeset(stat, attrs) do
    stat
    |> cast(attrs, [:player_id, :date, :sessions_completed, :practice_minutes,
                    :shots_attempted, :shots_on_goal, :goals_scored, :xp_earned])
    |> validate_required([:player_id, :date])
    |> validate_number(:sessions_completed, greater_than_or_equal_to: 0)
    |> validate_number(:practice_minutes, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:player_id)
    |> unique_constraint([:player_id, :date])
  end

  @doc "Calculate shooting percentage for the day"
  def shooting_percentage(%__MODULE__{shots_attempted: 0}), do: 0.0
  def shooting_percentage(%__MODULE__{goals_scored: goals, shots_attempted: shots}) do
    Float.round(goals / shots * 100, 1)
  end
end
