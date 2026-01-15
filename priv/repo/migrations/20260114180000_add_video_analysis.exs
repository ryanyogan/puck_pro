defmodule PuckPro.Repo.Migrations.AddVideoAnalysis do
  use Ecto.Migration

  def change do
    # =====================================================
    # VIDEO FRAMES (Extracted for AI analysis)
    # =====================================================
    create table(:video_frames) do
      add :session_video_id, references(:session_videos, on_delete: :delete_all), null: false
      add :frame_number, :integer, null: false
      add :timestamp_ms, :integer, null: false
      add :storage_path, :string, null: false
      add :r2_key, :string
      add :file_size, :integer

      # Elements detected in this frame (shot, player position, etc.)
      add :detected_elements, :map, default: %{}

      timestamps()
    end

    create index(:video_frames, [:session_video_id])
    create unique_index(:video_frames, [:session_video_id, :frame_number])

    # =====================================================
    # MANUAL ENTRIES (Fallback when video unavailable)
    # =====================================================
    create table(:manual_entries) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :drill_id, references(:drills, on_delete: :nilify_all)

      # Dynamic entry data based on drill's tracking_fields
      add :entry_data, :map, default: %{}

      # Type of manual entry: shot_tracking, time_tracking, rep_counting, etc.
      add :entry_type, :string, default: "shot_tracking"

      timestamps()
    end

    create index(:manual_entries, [:session_id])
    create index(:manual_entries, [:drill_id])

    # =====================================================
    # ENHANCE SESSION VIDEOS (R2 storage integration)
    # =====================================================
    alter table(:session_videos) do
      # Cloudflare R2 storage
      add :r2_key, :string
      add :r2_url, :string

      # Thumbnail for preview
      add :thumbnail_path, :string
      add :thumbnail_r2_key, :string

      # Frame extraction info
      add :frame_count, :integer, default: 0
      add :frames_extracted_at, :utc_datetime

      # Processing errors
      add :error_message, :text
    end

    create index(:session_videos, [:r2_key])

    # =====================================================
    # ENHANCE AI ANALYSES (Vision analysis results)
    # =====================================================
    alter table(:ai_analyses) do
      # Type of analysis: session, video, form, drill_specific
      add :analysis_type, :string, default: "session"

      # Form metrics from video analysis (stance, grip, follow_through scores 1-100)
      add :form_metrics, :map, default: %{}

      # Technique scores (release, accuracy, power scores 1-100)
      add :technique_scores, :map, default: %{}

      # Detected shots from video [{frame: 3, type: "wrist", result: "goal"}, ...]
      add :detected_shots, {:array, :map}, default: []

      # How well the session matched the drill/plan requirements
      add :plan_compliance, :map, default: %{}

      # AI-recommended drill slugs for next practice
      add :recommended_drills, {:array, :string}, default: []

      # Number of frames analyzed
      add :frames_analyzed, :integer, default: 0
    end

    # =====================================================
    # ENHANCE DRILLS (Dynamic tracking fields)
    # =====================================================
    alter table(:drills) do
      # Dynamic form fields for manual entry
      # [{name: "shots", label: "Total Shots", type: "counter"}, ...]
      add :tracking_fields, {:array, :map}, default: []

      # Criteria for determining drill compliance
      # {min_shots: 10, target_accuracy: 0.7, required_positions: ["slot", "point"]}
      add :compliance_criteria, :map, default: %{}

      # Whether this drill supports video analysis
      add :supports_video_analysis, :boolean, default: true
    end
  end
end
