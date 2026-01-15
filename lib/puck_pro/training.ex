defmodule PuckPro.Training do
  @moduledoc """
  Training context - manages drills, plans, sessions, and players.

  Uses metaprogramming to generate common CRUD operations and query helpers.
  """
  import Ecto.Query
  alias PuckPro.Repo
  alias PuckPro.Training.{Player, SkillCategory, Drill, TrainingPlan, PlanDrill, PlayerPlan, Session, SessionVideo}

  # ============================================================================
  # METAPROGRAMMING: Generate common functions for schemas
  # ============================================================================
  @schemas [
    {:player, Player},
    {:skill_category, SkillCategory},
    {:drill, Drill},
    {:training_plan, TrainingPlan},
    {:session, Session}
  ]

  for {name, schema} <- @schemas do
    plural = String.to_atom("#{name}s")

    @doc "List all #{name}s"
    def unquote(:"list_#{plural}")() do
      Repo.all(unquote(schema))
    end

    @doc "Get a #{name} by ID"
    def unquote(:"get_#{name}")(id) do
      Repo.get(unquote(schema), id)
    end

    @doc "Get a #{name} by ID, raise if not found"
    def unquote(:"get_#{name}!")(id) do
      Repo.get!(unquote(schema), id)
    end

    @doc "Create a #{name}"
    def unquote(:"create_#{name}")(attrs) do
      %unquote(schema){}
      |> unquote(schema).changeset(attrs)
      |> Repo.insert()
    end

    @doc "Update a #{name}"
    def unquote(:"update_#{name}")(%unquote(schema){} = record, attrs) do
      record
      |> unquote(schema).changeset(attrs)
      |> Repo.update()
    end

    @doc "Delete a #{name}"
    def unquote(:"delete_#{name}")(%unquote(schema){} = record) do
      Repo.delete(record)
    end

    @doc "Change a #{name} (for forms)"
    def unquote(:"change_#{name}")(%unquote(schema){} = record, attrs \\ %{}) do
      unquote(schema).changeset(record, attrs)
    end
  end

  # ============================================================================
  # PLAYER FUNCTIONS
  # ============================================================================

  @doc "Get or create the default player (single user mode)"
  def get_or_create_default_player do
    case Repo.one(from p in Player, limit: 1) do
      nil ->
        {:ok, player} = create_player(%{name: "Hockey Star"})
        player

      player ->
        player
    end
  end

  @doc "Award XP to a player and handle level ups"
  def award_xp(%Player{} = player, xp_amount) when xp_amount > 0 do
    new_xp = player.xp + xp_amount
    new_level = Player.level_from_xp(new_xp)
    level_up? = new_level > player.level

    {:ok, updated} = update_player(player, %{xp: new_xp, level: new_level})

    if level_up? do
      {:level_up, updated, new_level}
    else
      {:ok, updated}
    end
  end

  def award_xp(player, _), do: {:ok, player}

  @doc "Update player's streak based on practice date"
  def update_streak(%Player{} = player) do
    today = Date.utc_today()

    case player.last_practice_date do
      nil ->
        update_player(player, %{streak_days: 1, last_practice_date: today})

      ^today ->
        {:ok, player}

      last_date ->
        if Date.diff(today, last_date) == 1 do
          update_player(player, %{streak_days: player.streak_days + 1, last_practice_date: today})
        else
          update_player(player, %{streak_days: 1, last_practice_date: today})
        end
    end
  end

  # ============================================================================
  # SKILL CATEGORIES
  # ============================================================================

  @doc "Get a skill category by slug"
  def get_skill_category_by_slug(slug) do
    Repo.get_by(SkillCategory, slug: slug)
  end

  @doc "List skill categories ordered by sort_order"
  def list_skill_categories_ordered do
    from(c in SkillCategory, order_by: c.sort_order)
    |> Repo.all()
  end

  # ============================================================================
  # DRILLS
  # ============================================================================

  @doc "Get a drill by slug"
  def get_drill_by_slug(slug) do
    Repo.get_by(Drill, slug: slug)
  end

  @doc "List drills by difficulty"
  def list_drills_by_difficulty(difficulty) do
    from(d in Drill, where: d.difficulty == ^difficulty, order_by: d.name)
    |> Repo.all()
  end

  @doc "List drills by skill category"
  def list_drills_by_category(category_id) do
    from(d in Drill, where: d.skill_category_id == ^category_id, order_by: d.name)
    |> Repo.all()
  end

  @doc "Get a random drill (for 'random practice' feature)"
  def get_random_drill(opts \\ []) do
    query = from(d in Drill)

    query =
      case Keyword.get(opts, :difficulty) do
        nil -> query
        diff -> from(d in query, where: d.difficulty == ^diff)
      end

    query =
      case Keyword.get(opts, :category_id) do
        nil -> query
        cat_id -> from(d in query, where: d.skill_category_id == ^cat_id)
      end

    query
    |> Repo.all()
    |> Enum.random()
  rescue
    Enum.EmptyError -> nil
  end

  @doc "List drills with their categories preloaded"
  def list_drills_with_categories do
    from(d in Drill, preload: [:skill_category], order_by: d.name)
    |> Repo.all()
  end

  # ============================================================================
  # TRAINING PLANS
  # ============================================================================

  @doc "Get a training plan by slug"
  def get_training_plan_by_slug(slug) do
    Repo.get_by(TrainingPlan, slug: slug)
  end

  @doc "Get a training plan with all drills preloaded"
  def get_training_plan_with_drills(id) do
    plan_drills_query = from(pd in PlanDrill, order_by: [pd.week_number, pd.day_of_week, pd.sort_order])

    TrainingPlan
    |> Repo.get(id)
    |> Repo.preload(plan_drills: {plan_drills_query, [drill: :skill_category]})
  end

  @doc "List training plans by difficulty"
  def list_training_plans_by_difficulty(difficulty) do
    from(p in TrainingPlan, where: p.difficulty == ^difficulty, order_by: p.name)
    |> Repo.all()
  end

  # ============================================================================
  # PLAYER PLANS
  # ============================================================================

  @doc "Enroll a player in a training plan"
  def enroll_player_in_plan(%Player{} = player, %TrainingPlan{} = plan) do
    %PlayerPlan{}
    |> PlayerPlan.changeset(%{
      player_id: player.id,
      training_plan_id: plan.id,
      started_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  @doc "Get a player's active plans"
  def list_player_active_plans(player_id) do
    from(pp in PlayerPlan,
      where: pp.player_id == ^player_id and pp.status == "active",
      preload: [:training_plan]
    )
    |> Repo.all()
  end

  @doc "Advance player plan progress"
  def advance_player_plan(%PlayerPlan{} = player_plan, %TrainingPlan{} = plan) do
    new_day = player_plan.current_day + 1

    if new_day > 7 do
      new_week = player_plan.current_week + 1

      if new_week > plan.estimated_weeks do
        # Plan completed!
        player_plan
        |> PlayerPlan.changeset(%{status: "completed", completed_at: DateTime.utc_now()})
        |> Repo.update()
      else
        player_plan
        |> PlayerPlan.changeset(%{current_week: new_week, current_day: 1})
        |> Repo.update()
      end
    else
      player_plan
      |> PlayerPlan.changeset(%{current_day: new_day})
      |> Repo.update()
    end
  end

  # ============================================================================
  # SESSIONS
  # ============================================================================

  @doc "Start a new practice session"
  def start_session(%Player{} = player, opts \\ []) do
    attrs = %{
      player_id: player.id,
      started_at: DateTime.utc_now(),
      drill_id: Keyword.get(opts, :drill_id),
      player_plan_id: Keyword.get(opts, :player_plan_id)
    }

    create_session(attrs)
  end

  @doc "Complete a session"
  def complete_session(%Session{} = session, stats \\ %{}) do
    completed_at = DateTime.utc_now()
    duration = DateTime.diff(completed_at, session.started_at, :second)

    attrs =
      Map.merge(stats, %{
        completed_at: completed_at,
        duration_seconds: duration,
        status: "completed"
      })

    update_session(session, attrs)
  end

  @doc "List recent sessions for a player"
  def list_recent_sessions(player_id, limit \\ 10) do
    from(s in Session,
      where: s.player_id == ^player_id,
      order_by: [desc: s.started_at],
      limit: ^limit,
      preload: [:drill]
    )
    |> Repo.all()
  end

  @doc "Get session with all associations"
  def get_session_with_details(id) do
    from(s in Session,
      where: s.id == ^id,
      preload: [:player, :drill, :session_videos, :ai_analyses]
    )
    |> Repo.one()
  end

  # ============================================================================
  # SESSION VIDEOS
  # ============================================================================

  @doc "Add a video to a session"
  def add_session_video(%Session{} = session, video_attrs) do
    %SessionVideo{}
    |> SessionVideo.changeset(Map.put(video_attrs, :session_id, session.id))
    |> Repo.insert()
  end

  @doc "List videos for a session"
  def list_session_videos(session_id) do
    from(v in SessionVideo, where: v.session_id == ^session_id)
    |> Repo.all()
  end
end
