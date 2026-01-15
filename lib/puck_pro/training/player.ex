defmodule PuckPro.Training.Player do
  @moduledoc """
  Schema for a hockey player/student.
  Single user for now (no auth).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @positions ~w(forward defense goalie)

  schema "players" do
    field :name, :string
    field :age, :integer, default: 11
    field :experience_years, :integer, default: 1
    field :position, :string, default: "forward"

    # Gamification
    field :xp, :integer, default: 0
    field :level, :integer, default: 1
    field :streak_days, :integer, default: 0
    field :last_practice_date, :date

    # Stats totals
    field :total_sessions, :integer, default: 0
    field :total_practice_minutes, :integer, default: 0
    field :total_shots, :integer, default: 0
    field :total_goals, :integer, default: 0

    has_many :sessions, PuckPro.Training.Session
    has_many :player_plans, PuckPro.Training.PlayerPlan
    has_many :player_achievements, PuckPro.Progress.PlayerAchievement
    has_many :skill_progress, PuckPro.Progress.SkillProgress
    has_many :daily_stats, PuckPro.Progress.DailyStat

    timestamps()
  end

  def changeset(player, attrs) do
    player
    |> cast(attrs, [:name, :age, :experience_years, :position, :xp, :level,
                    :streak_days, :last_practice_date, :total_sessions,
                    :total_practice_minutes, :total_shots, :total_goals])
    |> validate_required([:name])
    |> validate_inclusion(:position, @positions)
    |> validate_number(:age, greater_than: 0, less_than: 100)
    |> validate_number(:xp, greater_than_or_equal_to: 0)
    |> validate_number(:level, greater_than: 0)
  end

  @doc "XP required to reach the next level"
  def xp_for_level(level) when level > 0 do
    # Exponential curve: 100 * 1.5^(level-1)
    trunc(100 * :math.pow(1.5, level - 1))
  end

  @doc "Calculate level from total XP"
  def level_from_xp(total_xp) when total_xp >= 0 do
    # Inverse of xp_for_level formula
    level = trunc(:math.log(total_xp / 100 + 1) / :math.log(1.5)) + 1
    max(1, level)
  end

  @doc "XP progress within current level (0.0 to 1.0)"
  def level_progress(%__MODULE__{xp: xp, level: level}) do
    current_threshold = if level == 1, do: 0, else: xp_for_level(level - 1)
    next_threshold = xp_for_level(level)
    progress_xp = xp - current_threshold
    required_xp = next_threshold - current_threshold
    min(1.0, progress_xp / required_xp)
  end
end
