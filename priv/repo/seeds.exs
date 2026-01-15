# PuckPro Seeds - Hockey Training Data
# Run with: mix run priv/repo/seeds.exs

alias PuckPro.Repo
alias PuckPro.Training.{SkillCategory, Drill, TrainingPlan, PlanDrill}
alias PuckPro.Progress.Achievement

IO.puts("Seeding PuckPro database...")

# ============================================================================
# SKILL CATEGORIES
# ============================================================================
IO.puts("Creating skill categories...")

categories = [
  %{
    name: "Shooting",
    slug: "shooting",
    description: "Master your shot - wrist shots, slap shots, snap shots, and accuracy",
    icon: "hero-fire",
    color: "text-error",
    sort_order: 1
  },
  %{
    name: "Stickhandling",
    slug: "stickhandling",
    description: "Control the puck like a pro - dekes, toe drags, and puck protection",
    icon: "hero-hand-raised",
    color: "text-primary",
    sort_order: 2
  },
  %{
    name: "Passing",
    slug: "passing",
    description: "Tape-to-tape passes - forehand, backhand, and saucer passes",
    icon: "hero-arrow-right",
    color: "text-success",
    sort_order: 3
  },
  %{
    name: "Skating",
    slug: "skating",
    description: "Edge work, crossovers, transitions, and speed skating",
    icon: "hero-bolt",
    color: "text-warning",
    sort_order: 4
  },
  %{
    name: "Hockey IQ",
    slug: "hockey-iq",
    description: "Read the play, positioning, and game awareness",
    icon: "hero-light-bulb",
    color: "text-info",
    sort_order: 5
  }
]

category_records =
  Enum.map(categories, fn attrs ->
    %SkillCategory{}
    |> SkillCategory.changeset(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :slug)
  end)

# Get categories by slug for referencing
get_category = fn slug ->
  Repo.get_by(SkillCategory, slug: slug)
end

# ============================================================================
# DRILLS
# ============================================================================
IO.puts("Creating drills...")

drills = [
  # SHOOTING DRILLS
  %{
    name: "Target Practice",
    slug: "target-practice",
    description: "Hit all four corners of the net with precision shots",
    instructions: """
    1. Set up 4 targets in the corners of the net (water bottles work great!)
    2. Start 10 feet from the net
    3. Take 10 wrist shots, alternating corners
    4. Track how many targets you hit
    5. Move back 5 feet and repeat
    """,
    tips: "Keep your eyes on the target, not the puck. Follow through toward your target.",
    duration_minutes: 15,
    difficulty: "beginner",
    equipment_needed: ["pucks", "targets", "net"],
    xp_reward: 15,
    skill_category_id: get_category.("shooting").id,
    scoring_criteria: %{
      "accuracy" => "Count targets hit out of 10 shots",
      "distance" => "Track shooting distance progression"
    }
  },
  %{
    name: "Quick Release Drill",
    slug: "quick-release",
    description: "Work on getting your shot off faster",
    instructions: """
    1. Stand in the slot area (15 feet from net)
    2. Receive a pass from your phone/tablet playing pass sounds OR imagine receiving
    3. Get your shot off within 1 second of receiving
    4. Focus on quick hands and getting puck on net
    5. 20 reps, then switch shooting positions
    """,
    tips: "Pre-load your stick - have it ready to shoot before the puck arrives.",
    duration_minutes: 10,
    difficulty: "intermediate",
    equipment_needed: ["pucks", "net"],
    xp_reward: 20,
    skill_category_id: get_category.("shooting").id
  },
  %{
    name: "One-Timer Practice",
    slug: "one-timer",
    description: "Master the one-timer shot from different angles",
    instructions: """
    1. Set up pucks in a row along the hash marks
    2. Practice one-timers from your forehand side
    3. Focus on timing and stick position
    4. Aim for specific targets in the net
    5. 15 reps, then switch to backhand side
    """,
    tips: "Open your body to the puck. Keep your top hand away from your body.",
    duration_minutes: 12,
    difficulty: "advanced",
    equipment_needed: ["pucks", "net"],
    xp_reward: 25,
    skill_category_id: get_category.("shooting").id
  },

  # STICKHANDLING DRILLS
  %{
    name: "Figure 8 Stickhandling",
    slug: "figure-8",
    description: "Build soft hands with the classic figure 8 pattern",
    instructions: """
    1. Place 2 pucks or cones about 2 feet apart
    2. Stickhandle around them in a figure 8 pattern
    3. Keep your head up - don't look at the puck!
    4. Start slow, increase speed as you get comfortable
    5. Try with your eyes closed for 10 seconds
    """,
    tips: "Keep the puck in front of your body. Roll your wrists, don't just push the puck.",
    duration_minutes: 8,
    difficulty: "beginner",
    equipment_needed: ["puck", "cones"],
    xp_reward: 10,
    skill_category_id: get_category.("stickhandling").id
  },
  %{
    name: "Toe Drag Challenge",
    slug: "toe-drag",
    description: "Learn the toe drag move to beat defenders",
    instructions: """
    1. Start with puck on your backhand
    2. Pull puck toward you with toe of blade
    3. Move puck across your body to forehand
    4. Practice at walking speed first
    5. Add a shot after the toe drag
    """,
    tips: "Cup the puck with your blade. The toe drag is all about patience.",
    duration_minutes: 10,
    difficulty: "intermediate",
    equipment_needed: ["pucks", "cones"],
    xp_reward: 18,
    skill_category_id: get_category.("stickhandling").id
  },
  %{
    name: "Chaos Puck Handling",
    slug: "chaos-handling",
    description: "Handle multiple pucks to improve hand speed",
    instructions: """
    1. Scatter 5-6 pucks in a small area
    2. Stickhandle through all pucks without losing control
    3. Keep moving, change directions constantly
    4. If you lose a puck, pick it up and continue
    5. Time yourself - try to beat your record
    """,
    tips: "Stay low in your stance. Quick, small movements are better than big sweeping ones.",
    duration_minutes: 8,
    difficulty: "advanced",
    equipment_needed: ["pucks"],
    xp_reward: 22,
    skill_category_id: get_category.("stickhandling").id
  },

  # PASSING DRILLS
  %{
    name: "Wall Pass Drill",
    slug: "wall-pass",
    description: "Use the wall as your passing partner",
    instructions: """
    1. Stand 10 feet from a wall or rebounder
    2. Pass the puck firmly against the wall
    3. Receive and immediately pass back
    4. 20 forehand passes, then 20 backhand
    5. Move closer/farther to change difficulty
    """,
    tips: "Follow through toward your target. Cushion the puck when receiving.",
    duration_minutes: 10,
    difficulty: "beginner",
    equipment_needed: ["pucks", "wall/rebounder"],
    xp_reward: 12,
    skill_category_id: get_category.("passing").id
  },
  %{
    name: "Saucer Pass Practice",
    slug: "saucer-pass",
    description: "Learn to lift passes over obstacles",
    instructions: """
    1. Place a stick or obstacle on the ice
    2. Practice lifting the puck over it to a target
    3. Start close, move back as you improve
    4. Focus on flat rotation of the puck
    5. Try to land the puck softly at the target
    """,
    tips: "Open your blade and lift from under the puck. Less is more with the follow through.",
    duration_minutes: 12,
    difficulty: "intermediate",
    equipment_needed: ["pucks", "obstacle", "target"],
    xp_reward: 18,
    skill_category_id: get_category.("passing").id
  },

  # SKATING DRILLS
  %{
    name: "Edge Work Basics",
    slug: "edge-work",
    description: "Master inside and outside edges",
    instructions: """
    1. Start on inside edges, glide in a C-cut pattern
    2. Then switch to outside edges
    3. Practice single-leg balance on each edge
    4. Try figure 8s using only edges (no pushing)
    5. Hold each edge for 3-5 seconds
    """,
    tips: "Bend your knees! Good knee bend = better edges.",
    duration_minutes: 10,
    difficulty: "beginner",
    equipment_needed: [],
    xp_reward: 12,
    skill_category_id: get_category.("skating").id
  },
  %{
    name: "Crossover Circuit",
    slug: "crossover-circuit",
    description: "Build crossover speed and power",
    instructions: """
    1. Set up 4 cones in a square pattern
    2. Skate around the square using crossovers
    3. Focus on crossing over, not just stepping
    4. 5 laps clockwise, 5 laps counter-clockwise
    5. Time your laps and try to improve
    """,
    tips: "Push with the outside leg during crossovers. Keep your shoulders level.",
    duration_minutes: 12,
    difficulty: "intermediate",
    equipment_needed: ["cones"],
    xp_reward: 18,
    skill_category_id: get_category.("skating").id
  },

  # HOCKEY IQ DRILLS
  %{
    name: "Vision Training",
    slug: "vision-training",
    description: "Train your eyes to see the whole ice",
    instructions: """
    1. Stand in one spot with a puck
    2. Stickhandle while keeping your head up
    3. Call out objects around the room as you see them
    4. Have someone move around - track their position
    5. Practice for 3-5 minute intervals
    """,
    tips: "Use your peripheral vision. The puck should feel like an extension of your stick.",
    duration_minutes: 8,
    difficulty: "beginner",
    equipment_needed: ["puck"],
    xp_reward: 10,
    skill_category_id: get_category.("hockey-iq").id
  },
  %{
    name: "Shot Selection Drill",
    slug: "shot-selection",
    description: "Learn when to shoot vs pass vs hold",
    instructions: """
    1. Set up targets representing teammates and open net areas
    2. Start with puck at different positions
    3. Practice making quick decisions:
       - Open net? SHOOT!
       - Teammate open? PASS!
       - Nothing open? PROTECT!
    4. Have someone call out the situation
    """,
    tips: "Good players shoot when they should, great players also know when NOT to shoot.",
    duration_minutes: 15,
    difficulty: "intermediate",
    equipment_needed: ["pucks", "targets"],
    xp_reward: 20,
    skill_category_id: get_category.("hockey-iq").id
  }
]

drill_records =
  Enum.map(drills, fn attrs ->
    %Drill{}
    |> Drill.changeset(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :slug)
  end)

get_drill = fn slug ->
  Repo.get_by(Drill, slug: slug)
end

# ============================================================================
# TRAINING PLANS
# ============================================================================
IO.puts("Creating training plans...")

plans = [
  %{
    name: "Sniper School",
    slug: "sniper-school",
    description: "4-week program to become a scoring machine. Focus on shooting accuracy, release speed, and finishing.",
    difficulty: "beginner",
    estimated_weeks: 4,
    icon: "hero-fire",
    color: "text-error",
    xp_reward: 500,
    badge_name: "Sharpshooter",
    badge_icon: "hero-fire"
  },
  %{
    name: "Silky Mitts",
    slug: "silky-mitts",
    description: "Master stickhandling with this 3-week hands-focused program. Dangling defenders has never been easier!",
    difficulty: "beginner",
    estimated_weeks: 3,
    icon: "hero-hand-raised",
    color: "text-primary",
    xp_reward: 400,
    badge_name: "Silky Hands",
    badge_icon: "hero-hand-raised"
  },
  %{
    name: "Playmaker Pro",
    slug: "playmaker-pro",
    description: "Learn to see the ice and make tape-to-tape passes. Become the player everyone wants on their line!",
    difficulty: "intermediate",
    estimated_weeks: 3,
    icon: "hero-arrow-right",
    color: "text-success",
    xp_reward: 450,
    badge_name: "Playmaker",
    badge_icon: "hero-arrow-right"
  },
  %{
    name: "Speed Demon",
    slug: "speed-demon",
    description: "4-week skating intensive. Edge work, crossovers, and explosive speed. Leave defenders in your dust!",
    difficulty: "intermediate",
    estimated_weeks: 4,
    icon: "hero-bolt",
    color: "text-warning",
    xp_reward: 550,
    badge_name: "Speed Demon",
    badge_icon: "hero-bolt"
  },
  %{
    name: "Complete Player",
    slug: "complete-player",
    description: "The ultimate 6-week program covering all skills. Graduate as a well-rounded hockey player!",
    difficulty: "advanced",
    estimated_weeks: 6,
    icon: "hero-star",
    color: "text-accent",
    xp_reward: 1000,
    badge_name: "Complete Player",
    badge_icon: "hero-star",
    prerequisites: ["sniper-school", "silky-mitts"]
  }
]

Enum.each(plans, fn attrs ->
  %TrainingPlan{}
  |> TrainingPlan.changeset(attrs)
  |> Repo.insert!(on_conflict: :nothing, conflict_target: :slug)
end)

# Add drills to plans
IO.puts("Linking drills to training plans...")

# Sniper School plan
sniper = Repo.get_by(TrainingPlan, slug: "sniper-school")
if sniper do
  [
    {get_drill.("target-practice"), 1, 1},
    {get_drill.("target-practice"), 1, 3},
    {get_drill.("quick-release"), 2, 1},
    {get_drill.("quick-release"), 2, 3},
    {get_drill.("target-practice"), 3, 1},
    {get_drill.("quick-release"), 3, 3},
    {get_drill.("one-timer"), 4, 1},
    {get_drill.("one-timer"), 4, 3}
  ]
  |> Enum.with_index()
  |> Enum.each(fn {{drill, week, day}, index} ->
    if drill do
      %PlanDrill{}
      |> PlanDrill.changeset(%{
        training_plan_id: sniper.id,
        drill_id: drill.id,
        week_number: week,
        day_of_week: day,
        sort_order: index
      })
      |> Repo.insert!(on_conflict: :nothing)
    end
  end)
end

# Silky Mitts plan
silky = Repo.get_by(TrainingPlan, slug: "silky-mitts")
if silky do
  [
    {get_drill.("figure-8"), 1, 1},
    {get_drill.("figure-8"), 1, 3},
    {get_drill.("toe-drag"), 2, 1},
    {get_drill.("toe-drag"), 2, 3},
    {get_drill.("chaos-handling"), 3, 1},
    {get_drill.("chaos-handling"), 3, 3}
  ]
  |> Enum.with_index()
  |> Enum.each(fn {{drill, week, day}, index} ->
    if drill do
      %PlanDrill{}
      |> PlanDrill.changeset(%{
        training_plan_id: silky.id,
        drill_id: drill.id,
        week_number: week,
        day_of_week: day,
        sort_order: index
      })
      |> Repo.insert!(on_conflict: :nothing)
    end
  end)
end

# ============================================================================
# ACHIEVEMENTS
# ============================================================================
IO.puts("Creating achievements...")

achievements = [
  # Session milestones
  %{
    name: "First Timer",
    slug: "first-timer",
    description: "Complete your first practice session",
    icon: "hero-rocket-launch",
    color: "text-primary",
    xp_reward: 25,
    criteria: %{"total_sessions" => 1},
    rarity: "common"
  },
  %{
    name: "Getting Started",
    slug: "getting-started",
    description: "Complete 5 practice sessions",
    icon: "hero-play",
    color: "text-success",
    xp_reward: 50,
    criteria: %{"total_sessions" => 5},
    rarity: "common"
  },
  %{
    name: "Dedicated",
    slug: "dedicated",
    description: "Complete 25 practice sessions",
    icon: "hero-heart",
    color: "text-error",
    xp_reward: 100,
    criteria: %{"total_sessions" => 25},
    rarity: "uncommon"
  },
  %{
    name: "Practice Makes Perfect",
    slug: "practice-perfect",
    description: "Complete 100 practice sessions",
    icon: "hero-trophy",
    color: "text-accent",
    xp_reward: 250,
    criteria: %{"total_sessions" => 100},
    rarity: "rare"
  },

  # Goal milestones
  %{
    name: "Goal Scorer",
    slug: "goal-scorer",
    description: "Score 10 goals in practice",
    icon: "hero-fire",
    color: "text-warning",
    xp_reward: 30,
    criteria: %{"total_goals" => 10},
    rarity: "common"
  },
  %{
    name: "Sniper",
    slug: "sniper",
    description: "Score 50 goals in practice",
    icon: "hero-fire",
    color: "text-error",
    xp_reward: 75,
    criteria: %{"total_goals" => 50},
    rarity: "uncommon"
  },
  %{
    name: "Goal Machine",
    slug: "goal-machine",
    description: "Score 200 goals in practice",
    icon: "hero-fire",
    color: "text-accent",
    xp_reward: 200,
    criteria: %{"total_goals" => 200},
    rarity: "rare"
  },

  # Streak achievements
  %{
    name: "On Fire",
    slug: "on-fire",
    description: "Maintain a 3-day practice streak",
    icon: "hero-fire",
    color: "text-warning",
    xp_reward: 40,
    criteria: %{"streak_days" => 3},
    rarity: "common"
  },
  %{
    name: "Week Warrior",
    slug: "week-warrior",
    description: "Maintain a 7-day practice streak",
    icon: "hero-calendar",
    color: "text-primary",
    xp_reward: 100,
    criteria: %{"streak_days" => 7},
    rarity: "uncommon"
  },
  %{
    name: "Unstoppable",
    slug: "unstoppable",
    description: "Maintain a 30-day practice streak",
    icon: "hero-bolt",
    color: "text-accent",
    xp_reward: 500,
    criteria: %{"streak_days" => 30},
    rarity: "epic"
  },

  # Level achievements
  %{
    name: "Rising Star",
    slug: "rising-star",
    description: "Reach level 5",
    icon: "hero-star",
    color: "text-info",
    xp_reward: 50,
    criteria: %{"level" => 5},
    rarity: "common"
  },
  %{
    name: "All-Star",
    slug: "all-star",
    description: "Reach level 10",
    icon: "hero-star",
    color: "text-warning",
    xp_reward: 150,
    criteria: %{"level" => 10},
    rarity: "uncommon"
  },
  %{
    name: "Elite Player",
    slug: "elite-player",
    description: "Reach level 25",
    icon: "hero-star",
    color: "text-accent",
    xp_reward: 500,
    criteria: %{"level" => 25},
    rarity: "epic"
  },
  %{
    name: "Legend",
    slug: "legend",
    description: "Reach level 50",
    icon: "hero-sparkles",
    color: "text-accent",
    xp_reward: 1000,
    criteria: %{"level" => 50},
    rarity: "legendary"
  },

  # Time achievements
  %{
    name: "Hour of Power",
    slug: "hour-power",
    description: "Practice for a total of 60 minutes",
    icon: "hero-clock",
    color: "text-info",
    xp_reward: 40,
    criteria: %{"total_practice_minutes" => 60},
    rarity: "common"
  },
  %{
    name: "Committed",
    slug: "committed",
    description: "Practice for a total of 10 hours",
    icon: "hero-clock",
    color: "text-primary",
    xp_reward: 150,
    criteria: %{"total_practice_minutes" => 600},
    rarity: "uncommon"
  }
]

Enum.each(achievements, fn attrs ->
  %Achievement{}
  |> Achievement.changeset(attrs)
  |> Repo.insert!(on_conflict: :nothing, conflict_target: :slug)
end)

IO.puts("Seeding complete!")
IO.puts("Created #{length(categories)} skill categories")
IO.puts("Created #{length(drills)} drills")
IO.puts("Created #{length(plans)} training plans")
IO.puts("Created #{length(achievements)} achievements")
