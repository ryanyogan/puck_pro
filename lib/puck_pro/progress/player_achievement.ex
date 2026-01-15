defmodule PuckPro.Progress.PlayerAchievement do
  @moduledoc """
  Junction table for player's unlocked achievements.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "player_achievements" do
    belongs_to :player, PuckPro.Training.Player
    belongs_to :achievement, PuckPro.Progress.Achievement

    field :unlocked_at, :utc_datetime

    timestamps()
  end

  def changeset(player_achievement, attrs) do
    player_achievement
    |> cast(attrs, [:player_id, :achievement_id, :unlocked_at])
    |> validate_required([:player_id, :achievement_id, :unlocked_at])
    |> foreign_key_constraint(:player_id)
    |> foreign_key_constraint(:achievement_id)
    |> unique_constraint([:player_id, :achievement_id])
  end
end
