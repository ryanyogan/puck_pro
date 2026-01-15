defmodule PuckPro.Training.SkillCategory do
  @moduledoc """
  Categories of hockey skills (shooting, skating, stickhandling, etc.)
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "skill_categories" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :icon, :string
    field :color, :string
    field :sort_order, :integer, default: 0

    has_many :drills, PuckPro.Training.Drill

    timestamps()
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :slug, :description, :icon, :color, :sort_order])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
    |> generate_slug()
  end

  defp generate_slug(changeset) do
    case get_change(changeset, :slug) do
      nil ->
        case get_change(changeset, :name) do
          nil -> changeset
          name -> put_change(changeset, :slug, slugify(name))
        end
      _ -> changeset
    end
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/[\s-]+/, "-")
    |> String.trim("-")
  end
end
