defmodule PuckPro.AI.Analysis do
  @moduledoc """
  AI analysis results for practice sessions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)
  @analysis_types ~w(session video form drill_specific)

  schema "ai_analyses" do
    belongs_to :session, PuckPro.Training.Session
    belongs_to :session_video, PuckPro.Training.SessionVideo

    field :status, :string, default: "pending"
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    # AI model info
    field :model_used, :string
    field :prompt_tokens, :integer
    field :completion_tokens, :integer

    # Analysis results
    field :strengths, {:array, :map}, default: []
    field :improvements, {:array, :map}, default: []
    field :metrics, :map, default: %{}
    field :overall_score, :integer
    field :summary, :string

    # Type of analysis: session, video, form, drill_specific
    field :analysis_type, :string, default: "session"

    # Vision analysis: Form metrics (stance, grip, follow_through scores 1-100)
    field :form_metrics, :map, default: %{}

    # Vision analysis: Technique scores (release, accuracy, power scores 1-100)
    field :technique_scores, :map, default: %{}

    # Vision analysis: Detected shots [{frame: 3, type: "wrist", result: "goal"}, ...]
    field :detected_shots, {:array, :map}, default: []

    # How well the session matched drill/plan requirements
    field :plan_compliance, :map, default: %{}

    # AI-recommended drill slugs for next practice
    field :recommended_drills, {:array, :string}, default: []

    # Number of frames analyzed for video analysis
    field :frames_analyzed, :integer, default: 0

    # Raw AI response for debugging
    field :raw_response, :string

    timestamps()
  end

  @cast_fields ~w(
    session_id session_video_id status started_at completed_at
    model_used prompt_tokens completion_tokens
    strengths improvements metrics overall_score summary
    analysis_type form_metrics technique_scores detected_shots
    plan_compliance recommended_drills frames_analyzed
    raw_response
  )a

  def changeset(analysis, attrs) do
    analysis
    |> cast(attrs, @cast_fields)
    |> validate_required([:session_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:analysis_type, @analysis_types)
    |> validate_number(:overall_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:frames_analyzed, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:session_id)
    |> foreign_key_constraint(:session_video_id)
  end

  @doc "Get the top N strengths"
  def top_strengths(%__MODULE__{strengths: strengths}, n) when is_list(strengths) do
    Enum.take(strengths, n)
  end
  def top_strengths(_, _), do: []

  @doc "Get the top N areas for improvement"
  def top_improvements(%__MODULE__{improvements: improvements}, n) when is_list(improvements) do
    Enum.take(improvements, n)
  end
  def top_improvements(_, _), do: []

  @doc "Processing duration in seconds"
  def processing_duration(%__MODULE__{started_at: nil}), do: nil
  def processing_duration(%__MODULE__{completed_at: nil}), do: nil
  def processing_duration(%__MODULE__{started_at: started, completed_at: completed}) do
    DateTime.diff(completed, started, :second)
  end
end
