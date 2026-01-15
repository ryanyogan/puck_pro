defmodule PuckPro.Progress.Achievement do
  @moduledoc """
  Achievements/badges that players can unlock.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @rarities ~w(common uncommon rare epic legendary)

  schema "achievements" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :icon, :string
    field :color, :string
    field :xp_reward, :integer, default: 50
    field :criteria, :map, default: %{}
    field :rarity, :string, default: "common"

    has_many :player_achievements, PuckPro.Progress.PlayerAchievement

    timestamps()
  end

  def changeset(achievement, attrs) do
    achievement
    |> cast(attrs, [:name, :slug, :description, :icon, :color, :xp_reward, :criteria, :rarity])
    |> validate_required([:name, :slug])
    |> validate_inclusion(:rarity, @rarities)
    |> validate_number(:xp_reward, greater_than_or_equal_to: 0)
    |> unique_constraint(:slug)
  end

  @doc "Get the rarity color class"
  def rarity_color("common"), do: "text-base-content"
  def rarity_color("uncommon"), do: "text-success"
  def rarity_color("rare"), do: "text-info"
  def rarity_color("epic"), do: "text-primary"
  def rarity_color("legendary"), do: "text-accent"
  def rarity_color(_), do: "text-base-content"

  @doc "XP multiplier based on rarity"
  def rarity_multiplier("common"), do: 1.0
  def rarity_multiplier("uncommon"), do: 1.5
  def rarity_multiplier("rare"), do: 2.0
  def rarity_multiplier("epic"), do: 3.0
  def rarity_multiplier("legendary"), do: 5.0
  def rarity_multiplier(_), do: 1.0
end
