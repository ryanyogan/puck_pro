defmodule PuckPro.Progress do
  @moduledoc """
  Progress tracking context - achievements, skill progress, daily stats.
  """
  import Ecto.Query
  alias PuckPro.Repo
  alias PuckPro.Progress.{Achievement, PlayerAchievement, SkillProgress, DailyStat}
  alias PuckPro.Training.Player

  # ============================================================================
  # ACHIEVEMENTS
  # ============================================================================

  def list_achievements do
    from(a in Achievement, order_by: [a.rarity, a.name])
    |> Repo.all()
  end

  def get_achievement!(id), do: Repo.get!(Achievement, id)

  def get_achievement_by_slug(slug), do: Repo.get_by(Achievement, slug: slug)

  def create_achievement(attrs) do
    %Achievement{}
    |> Achievement.changeset(attrs)
    |> Repo.insert()
  end

  @doc "List achievements a player has unlocked"
  def list_player_achievements(player_id) do
    from(pa in PlayerAchievement,
      where: pa.player_id == ^player_id,
      preload: [:achievement],
      order_by: [desc: pa.unlocked_at]
    )
    |> Repo.all()
  end

  @doc "Check if player has achievement"
  def player_has_achievement?(player_id, achievement_id) do
    from(pa in PlayerAchievement,
      where: pa.player_id == ^player_id and pa.achievement_id == ^achievement_id
    )
    |> Repo.exists?()
  end

  @doc "Unlock an achievement for a player"
  def unlock_achievement(%Player{} = player, %Achievement{} = achievement) do
    if player_has_achievement?(player.id, achievement.id) do
      {:already_unlocked, nil}
    else
      case %PlayerAchievement{}
           |> PlayerAchievement.changeset(%{
             player_id: player.id,
             achievement_id: achievement.id,
             unlocked_at: DateTime.utc_now()
           })
           |> Repo.insert() do
        {:ok, pa} ->
          # Award bonus XP
          PuckPro.Training.award_xp(player, achievement.xp_reward)
          {:ok, pa}

        error ->
          error
      end
    end
  end

  @doc "Check and unlock any achievements based on current stats"
  def check_achievements(%Player{} = player) do
    achievements = list_achievements()
    player = Repo.preload(player, :daily_stats)

    Enum.reduce(achievements, [], fn achievement, unlocked ->
      if should_unlock?(player, achievement) do
        case unlock_achievement(player, achievement) do
          {:ok, pa} -> [pa | unlocked]
          _ -> unlocked
        end
      else
        unlocked
      end
    end)
  end

  defp should_unlock?(%Player{} = player, %Achievement{criteria: criteria}) do
    Enum.all?(criteria, fn {key, value} ->
      check_criterion(player, key, value)
    end)
  end

  defp check_criterion(player, "total_sessions", min), do: player.total_sessions >= min
  defp check_criterion(player, "total_goals", min), do: player.total_goals >= min
  defp check_criterion(player, "streak_days", min), do: player.streak_days >= min
  defp check_criterion(player, "level", min), do: player.level >= min
  defp check_criterion(player, "total_practice_minutes", min), do: player.total_practice_minutes >= min
  defp check_criterion(_, _, _), do: false

  # ============================================================================
  # SKILL PROGRESS
  # ============================================================================

  @doc "Get or create skill progress for a player/category"
  def get_or_create_skill_progress(player_id, skill_category_id) do
    case Repo.get_by(SkillProgress, player_id: player_id, skill_category_id: skill_category_id) do
      nil ->
        {:ok, progress} =
          %SkillProgress{}
          |> SkillProgress.changeset(%{
            player_id: player_id,
            skill_category_id: skill_category_id
          })
          |> Repo.insert()

        progress

      progress ->
        progress
    end
  end

  @doc "List all skill progress for a player"
  def list_player_skill_progress(player_id) do
    from(sp in SkillProgress,
      where: sp.player_id == ^player_id,
      preload: [:skill_category]
    )
    |> Repo.all()
  end

  @doc "Update skill progress after a session"
  def update_skill_progress_from_session(player_id, skill_category_id, session_minutes, xp_earned) do
    progress = get_or_create_skill_progress(player_id, skill_category_id)

    progress
    |> SkillProgress.changeset(%{
      sessions_completed: progress.sessions_completed + 1,
      total_practice_minutes: progress.total_practice_minutes + session_minutes,
      xp: progress.xp + xp_earned
    })
    |> Repo.update()
  end

  # ============================================================================
  # DAILY STATS
  # ============================================================================

  @doc "Get or create today's stats for a player"
  def get_or_create_daily_stat(player_id, date \\ Date.utc_today()) do
    case Repo.get_by(DailyStat, player_id: player_id, date: date) do
      nil ->
        {:ok, stat} =
          %DailyStat{}
          |> DailyStat.changeset(%{player_id: player_id, date: date})
          |> Repo.insert()

        stat

      stat ->
        stat
    end
  end

  @doc "Update daily stats after a session"
  def update_daily_stats_from_session(player_id, session) do
    today = Date.utc_today()
    stat = get_or_create_daily_stat(player_id, today)

    duration_minutes = div(session.duration_seconds || 0, 60)

    stat
    |> DailyStat.changeset(%{
      sessions_completed: stat.sessions_completed + 1,
      practice_minutes: stat.practice_minutes + duration_minutes,
      shots_attempted: stat.shots_attempted + (session.shots_attempted || 0),
      shots_on_goal: stat.shots_on_goal + (session.shots_on_goal || 0),
      goals_scored: stat.goals_scored + (session.goals_scored || 0),
      xp_earned: stat.xp_earned + (session.xp_earned || 0)
    })
    |> Repo.update()
  end

  @doc "Get daily stats for the last N days"
  def list_daily_stats(player_id, days \\ 7) do
    start_date = Date.add(Date.utc_today(), -days)

    from(ds in DailyStat,
      where: ds.player_id == ^player_id and ds.date >= ^start_date,
      order_by: ds.date
    )
    |> Repo.all()
  end

  @doc "Get stats summary for a date range"
  def get_stats_summary(player_id, start_date, end_date) do
    result =
      from(ds in DailyStat,
        where: ds.player_id == ^player_id and ds.date >= ^start_date and ds.date <= ^end_date,
        select: %{
          total_sessions: sum(ds.sessions_completed),
          total_minutes: sum(ds.practice_minutes),
          total_shots: sum(ds.shots_attempted),
          total_on_goal: sum(ds.shots_on_goal),
          total_goals: sum(ds.goals_scored),
          total_xp: sum(ds.xp_earned)
        }
      )
      |> Repo.one()

    # Return default values if no stats exist
    result || %{
      total_sessions: 0,
      total_minutes: 0,
      total_shots: 0,
      total_on_goal: 0,
      total_goals: 0,
      total_xp: 0
    }
  end
end
