defmodule PuckPro.Training.ManualEntry do
  @moduledoc """
  Manual data entry fallback when video capture is unavailable.

  Stores dynamic entry data based on drill-specific tracking fields,
  allowing for flexible manual stat tracking during practice.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @entry_types ~w(shot_tracking time_tracking rep_counting custom)

  schema "manual_entries" do
    belongs_to :session, PuckPro.Training.Session
    belongs_to :drill, PuckPro.Training.Drill

    # Dynamic entry data based on drill's tracking_fields
    # e.g., %{"shots" => 10, "goals" => 7, "position" => "slot"}
    field :entry_data, :map, default: %{}

    field :entry_type, :string, default: "shot_tracking"

    timestamps()
  end

  @cast_fields ~w(session_id drill_id entry_data entry_type)a

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @cast_fields)
    |> validate_required([:session_id])
    |> validate_inclusion(:entry_type, @entry_types)
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:drill_id)
  end

  @doc """
  Extract a specific value from entry_data.
  """
  def get_value(%__MODULE__{entry_data: data}, key, default \\ nil) do
    Map.get(data, key, default)
  end

  @doc """
  Calculate totals from entry data for common stats.
  """
  def calculate_stats(%__MODULE__{entry_data: data}) do
    %{
      shots: Map.get(data, "shots", 0) |> to_integer(),
      goals: Map.get(data, "goals", 0) |> to_integer(),
      on_goal: Map.get(data, "on_goal", 0) |> to_integer()
    }
  end

  defp to_integer(val) when is_integer(val), do: val
  defp to_integer(val) when is_binary(val), do: String.to_integer(val)
  defp to_integer(_), do: 0
end
