defmodule PuckPro.Training.PlanDrill do
  @moduledoc """
  Junction table linking training plans to drills with ordering/scheduling.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "plan_drills" do
    belongs_to :training_plan, PuckPro.Training.TrainingPlan
    belongs_to :drill, PuckPro.Training.Drill

    field :week_number, :integer, default: 1
    field :day_of_week, :integer, default: 1
    field :sort_order, :integer, default: 0
    field :repetitions, :integer, default: 1

    timestamps()
  end

  def changeset(plan_drill, attrs) do
    plan_drill
    |> cast(attrs, [:training_plan_id, :drill_id, :week_number, :day_of_week,
                    :sort_order, :repetitions])
    |> validate_required([:training_plan_id, :drill_id])
    |> validate_number(:week_number, greater_than: 0)
    |> validate_number(:day_of_week, greater_than: 0, less_than_or_equal_to: 7)
    |> validate_number(:repetitions, greater_than: 0)
    |> foreign_key_constraint(:training_plan_id)
    |> foreign_key_constraint(:drill_id)
    |> unique_constraint([:training_plan_id, :drill_id, :week_number, :day_of_week])
  end
end
