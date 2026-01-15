defmodule PuckPro.Training.PlayerPlan do
  @moduledoc """
  Player's enrolled training plans with progress tracking.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active paused completed abandoned)

  schema "player_plans" do
    belongs_to :player, PuckPro.Training.Player
    belongs_to :training_plan, PuckPro.Training.TrainingPlan

    field :status, :string, default: "active"
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :current_week, :integer, default: 1
    field :current_day, :integer, default: 1

    has_many :sessions, PuckPro.Training.Session

    timestamps()
  end

  def changeset(player_plan, attrs) do
    player_plan
    |> cast(attrs, [:player_id, :training_plan_id, :status, :started_at,
                    :completed_at, :current_week, :current_day])
    |> validate_required([:player_id, :training_plan_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:current_week, greater_than: 0)
    |> validate_number(:current_day, greater_than: 0, less_than_or_equal_to: 7)
    |> foreign_key_constraint(:player_id)
    |> foreign_key_constraint(:training_plan_id)
    |> unique_constraint([:player_id, :training_plan_id])
  end

  @doc "Calculate completion percentage"
  def completion_percentage(%__MODULE__{} = pp, total_weeks) when total_weeks > 0 do
    total_days = total_weeks * 7
    completed_days = (pp.current_week - 1) * 7 + (pp.current_day - 1)
    min(100, trunc(completed_days / total_days * 100))
  end
  def completion_percentage(_, _), do: 0
end
