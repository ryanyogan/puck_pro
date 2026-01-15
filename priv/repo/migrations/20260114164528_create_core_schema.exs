defmodule PuckPro.Repo.Migrations.CreateCoreSchema do
  use Ecto.Migration

  def change do
    # =====================================================
    # PLAYER (Single user for now, no auth)
    # =====================================================
    create table(:players) do
      add :name, :string, null: false
      add :age, :integer, default: 11
      add :experience_years, :integer, default: 1
      add :position, :string, default: "forward"

      # Gamification
      add :xp, :integer, default: 0
      add :level, :integer, default: 1
      add :streak_days, :integer, default: 0
      add :last_practice_date, :date

      # Stats totals
      add :total_sessions, :integer, default: 0
      add :total_practice_minutes, :integer, default: 0
      add :total_shots, :integer, default: 0
      add :total_goals, :integer, default: 0

      timestamps()
    end

    # =====================================================
    # SKILL CATEGORIES
    # =====================================================
    create table(:skill_categories) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :icon, :string
      add :color, :string
      add :sort_order, :integer, default: 0

      timestamps()
    end

    create unique_index(:skill_categories, [:slug])

    # =====================================================
    # DRILLS
    # =====================================================
    create table(:drills) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :instructions, :text
      add :tips, :text
      add :duration_minutes, :integer, default: 10
      add :difficulty, :string, default: "beginner"
      add :equipment_needed, {:array, :string}, default: []
      add :video_demo_url, :string

      # Scoring criteria for AI analysis
      add :scoring_criteria, :map, default: %{}

      # XP reward for completion
      add :xp_reward, :integer, default: 10

      add :skill_category_id, references(:skill_categories, on_delete: :restrict)

      timestamps()
    end

    create unique_index(:drills, [:slug])
    create index(:drills, [:skill_category_id])
    create index(:drills, [:difficulty])

    # =====================================================
    # TRAINING PLANS (Learning Paths)
    # =====================================================
    create table(:training_plans) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :difficulty, :string, default: "beginner"
      add :estimated_weeks, :integer, default: 4
      add :icon, :string
      add :color, :string

      # Gamification
      add :xp_reward, :integer, default: 100
      add :badge_name, :string
      add :badge_icon, :string

      # Prerequisites (plan slugs)
      add :prerequisites, {:array, :string}, default: []

      timestamps()
    end

    create unique_index(:training_plans, [:slug])

    # =====================================================
    # PLAN DRILLS (Junction table with ordering)
    # =====================================================
    create table(:plan_drills) do
      add :training_plan_id, references(:training_plans, on_delete: :delete_all), null: false
      add :drill_id, references(:drills, on_delete: :restrict), null: false
      add :week_number, :integer, default: 1
      add :day_of_week, :integer, default: 1
      add :sort_order, :integer, default: 0
      add :repetitions, :integer, default: 1

      timestamps()
    end

    create index(:plan_drills, [:training_plan_id])
    create index(:plan_drills, [:drill_id])
    create unique_index(:plan_drills, [:training_plan_id, :drill_id, :week_number, :day_of_week])

    # =====================================================
    # PLAYER PLANS (Enrolled plans with progress)
    # =====================================================
    create table(:player_plans) do
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :training_plan_id, references(:training_plans, on_delete: :restrict), null: false
      add :status, :string, default: "active"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :current_week, :integer, default: 1
      add :current_day, :integer, default: 1

      timestamps()
    end

    create index(:player_plans, [:player_id])
    create index(:player_plans, [:training_plan_id])
    create unique_index(:player_plans, [:player_id, :training_plan_id])

    # =====================================================
    # PRACTICE SESSIONS
    # =====================================================
    create table(:sessions) do
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :drill_id, references(:drills, on_delete: :restrict)
      add :player_plan_id, references(:player_plans, on_delete: :nilify_all)

      add :started_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime
      add :duration_seconds, :integer
      add :status, :string, default: "in_progress"

      # Session stats
      add :shots_attempted, :integer, default: 0
      add :shots_on_goal, :integer, default: 0
      add :goals_scored, :integer, default: 0

      # XP earned this session
      add :xp_earned, :integer, default: 0

      # AI analysis status
      add :analysis_status, :string, default: "pending"

      # Notes from player
      add :notes, :text

      timestamps()
    end

    create index(:sessions, [:player_id])
    create index(:sessions, [:drill_id])
    create index(:sessions, [:player_plan_id])
    create index(:sessions, [:started_at])
    create index(:sessions, [:status])

    # =====================================================
    # SESSION VIDEOS
    # =====================================================
    create table(:session_videos) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false

      add :filename, :string, null: false
      add :content_type, :string
      add :file_size, :integer
      add :storage_path, :string

      # Video metadata
      add :duration_seconds, :integer
      add :width, :integer
      add :height, :integer
      add :fps, :float

      # Processing status
      add :status, :string, default: "uploaded"

      timestamps()
    end

    create index(:session_videos, [:session_id])

    # =====================================================
    # AI ANALYSES
    # =====================================================
    create table(:ai_analyses) do
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
      add :session_video_id, references(:session_videos, on_delete: :nilify_all)

      add :status, :string, default: "pending"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      # AI model info
      add :model_used, :string
      add :prompt_tokens, :integer
      add :completion_tokens, :integer

      # Analysis results (JSON)
      add :strengths, {:array, :map}, default: []
      add :improvements, {:array, :map}, default: []
      add :metrics, :map, default: %{}
      add :overall_score, :integer
      add :summary, :text

      # Raw AI response for debugging
      add :raw_response, :text

      timestamps()
    end

    create index(:ai_analyses, [:session_id])
    create index(:ai_analyses, [:status])

    # =====================================================
    # ACHIEVEMENTS (Badges)
    # =====================================================
    create table(:achievements) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :icon, :string
      add :color, :string
      add :xp_reward, :integer, default: 50

      # Unlock criteria (JSON)
      add :criteria, :map, default: %{}

      # Rarity: common, uncommon, rare, epic, legendary
      add :rarity, :string, default: "common"

      timestamps()
    end

    create unique_index(:achievements, [:slug])

    # =====================================================
    # PLAYER ACHIEVEMENTS
    # =====================================================
    create table(:player_achievements) do
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :achievement_id, references(:achievements, on_delete: :restrict), null: false
      add :unlocked_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:player_achievements, [:player_id])
    create unique_index(:player_achievements, [:player_id, :achievement_id])

    # =====================================================
    # SKILL PROGRESS (Per-skill tracking)
    # =====================================================
    create table(:skill_progress) do
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :skill_category_id, references(:skill_categories, on_delete: :restrict), null: false

      add :level, :integer, default: 1
      add :xp, :integer, default: 0
      add :sessions_completed, :integer, default: 0
      add :total_practice_minutes, :integer, default: 0

      # AI-determined proficiency (1-100)
      add :proficiency_score, :integer, default: 0

      timestamps()
    end

    create index(:skill_progress, [:player_id])
    create unique_index(:skill_progress, [:player_id, :skill_category_id])

    # =====================================================
    # DAILY STATS (For streaks and charts)
    # =====================================================
    create table(:daily_stats) do
      add :player_id, references(:players, on_delete: :delete_all), null: false
      add :date, :date, null: false

      add :sessions_completed, :integer, default: 0
      add :practice_minutes, :integer, default: 0
      add :shots_attempted, :integer, default: 0
      add :shots_on_goal, :integer, default: 0
      add :goals_scored, :integer, default: 0
      add :xp_earned, :integer, default: 0

      timestamps()
    end

    create index(:daily_stats, [:player_id])
    create unique_index(:daily_stats, [:player_id, :date])
  end
end
