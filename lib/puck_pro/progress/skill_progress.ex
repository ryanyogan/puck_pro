defmodule PuckPro.Progress.SkillProgress do
  @moduledoc """
  Per-skill progress tracking for a player.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "skill_progress" do
    belongs_to :player, PuckPro.Training.Player
    belongs_to :skill_category, PuckPro.Training.SkillCategory

    field :level, :integer, default: 1
    field :xp, :integer, default: 0
    field :sessions_completed, :integer, default: 0
    field :total_practice_minutes, :integer, default: 0
    field :proficiency_score, :integer, default: 0

    timestamps()
  end

  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [:player_id, :skill_category_id, :level, :xp, :sessions_completed,
                    :total_practice_minutes, :proficiency_score])
    |> validate_required([:player_id, :skill_category_id])
    |> validate_number(:level, greater_than: 0)
    |> validate_number(:xp, greater_than_or_equal_to: 0)
    |> validate_number(:proficiency_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:player_id)
    |> foreign_key_constraint(:skill_category_id)
    |> unique_constraint([:player_id, :skill_category_id])
  end

  @doc "Get proficiency label based on score"
  def proficiency_label(score) when score < 20, do: "Rookie"
  def proficiency_label(score) when score < 40, do: "Beginner"
  def proficiency_label(score) when score < 60, do: "Developing"
  def proficiency_label(score) when score < 80, do: "Skilled"
  def proficiency_label(_), do: "Elite"
end
