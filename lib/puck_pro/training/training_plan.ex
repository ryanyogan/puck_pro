defmodule PuckPro.Training.TrainingPlan do
  @moduledoc """
  Training plans/learning paths - collections of drills organized by week/day.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @difficulties ~w(beginner intermediate advanced)

  schema "training_plans" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :difficulty, :string, default: "beginner"
    field :estimated_weeks, :integer, default: 4
    field :icon, :string
    field :color, :string
    field :xp_reward, :integer, default: 100
    field :badge_name, :string
    field :badge_icon, :string
    field :prerequisites, {:array, :string}, default: []

    has_many :plan_drills, PuckPro.Training.PlanDrill
    has_many :drills, through: [:plan_drills, :drill]
    has_many :player_plans, PuckPro.Training.PlayerPlan

    timestamps()
  end

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [:name, :slug, :description, :difficulty, :estimated_weeks,
                    :icon, :color, :xp_reward, :badge_name, :badge_icon, :prerequisites])
    |> validate_required([:name, :slug])
    |> validate_inclusion(:difficulty, @difficulties)
    |> validate_number(:estimated_weeks, greater_than: 0)
    |> validate_number(:xp_reward, greater_than_or_equal_to: 0)
    |> unique_constraint(:slug)
  end

  @doc "Calculate total drills in the plan"
  def total_drills(%__MODULE__{plan_drills: plan_drills}) when is_list(plan_drills) do
    length(plan_drills)
  end
  def total_drills(_), do: 0
end
