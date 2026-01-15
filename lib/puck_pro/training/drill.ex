defmodule PuckPro.Training.Drill do
  @moduledoc """
  Individual training drills/exercises.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @difficulties ~w(beginner intermediate advanced)

  schema "drills" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :instructions, :string
    field :tips, :string
    field :duration_minutes, :integer, default: 10
    field :difficulty, :string, default: "beginner"
    field :equipment_needed, {:array, :string}, default: []
    field :video_demo_url, :string
    field :scoring_criteria, :map, default: %{}
    field :xp_reward, :integer, default: 10

    # Manual entry tracking fields
    # e.g., [%{name: "shots", label: "Total Shots", type: "counter"}, ...]
    field :tracking_fields, {:array, :map}, default: []

    # Criteria for determining drill compliance during analysis
    # e.g., %{min_shots: 10, target_accuracy: 0.7}
    field :compliance_criteria, :map, default: %{}

    # Whether this drill supports AI video analysis
    field :supports_video_analysis, :boolean, default: true

    belongs_to :skill_category, PuckPro.Training.SkillCategory
    has_many :sessions, PuckPro.Training.Session
    has_many :plan_drills, PuckPro.Training.PlanDrill

    timestamps()
  end

  @cast_fields ~w(
    name slug description instructions tips duration_minutes difficulty
    equipment_needed video_demo_url scoring_criteria xp_reward
    tracking_fields compliance_criteria supports_video_analysis
    skill_category_id
  )a

  def changeset(drill, attrs) do
    drill
    |> cast(attrs, @cast_fields)
    |> validate_required([:name, :slug])
    |> validate_inclusion(:difficulty, @difficulties)
    |> validate_number(:duration_minutes, greater_than: 0)
    |> validate_number(:xp_reward, greater_than_or_equal_to: 0)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:skill_category_id)
  end

  @doc "Calculate effective XP based on difficulty multiplier"
  def effective_xp(%__MODULE__{xp_reward: base, difficulty: diff}) do
    multiplier = case diff do
      "beginner" -> 1.0
      "intermediate" -> 1.5
      "advanced" -> 2.0
      _ -> 1.0
    end
    trunc(base * multiplier)
  end
end
