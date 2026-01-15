# PuckPro - Hockey Training Application

A gamified hockey training application built with Elixir, Phoenix LiveView, and Claude AI for video analysis.

## Quick Start

```bash
# Install dependencies
mix deps.get

# Create and migrate database
mix ecto.create
mix ecto.migrate

# Seed the database with drills, plans, and achievements
mix run priv/repo/seeds.exs

# Start the Phoenix server
mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) to access the application.

## Build Commands

```bash
mix compile          # Compile the project
mix test             # Run test suite
mix format           # Format code
mix dialyzer         # Run type checking (if configured)
```

## Project Structure

```
lib/
├── puck_pro/
│   ├── training.ex          # Main training context (metaprogrammed CRUD)
│   ├── progress.ex          # Achievements and skill progress tracking
│   ├── ai.ex                # Claude AI integration with streaming
│   ├── http/
│   │   ├── adapter.ex       # HTTP behaviour for testability
│   │   ├── req_adapter.ex   # Production HTTP client
│   │   └── mock_adapter.ex  # Test mock adapter
│   └── training/            # Ecto schemas
│       ├── player.ex
│       ├── drill.ex
│       ├── training_plan.ex
│       ├── session.ex
│       └── ...
├── puck_pro_web/
│   ├── live/
│   │   ├── dashboard_live.ex    # Main dashboard with async stats
│   │   ├── drills_live.ex       # Drill library with filtering
│   │   ├── plans_live.ex        # Training plan enrollment
│   │   ├── practice_live.ex     # Active practice session
│   │   └── stubs.ex             # Additional LiveViews
│   └── components/
│       ├── layouts.ex           # Navigation and page layouts
│       └── core_components.ex   # Reusable components
```

## Architecture Patterns

### Metaprogramming for CRUD Operations

The `Training` context uses metaprogramming to generate common CRUD functions:

```elixir
@schemas [
  {:player, Player},
  {:drill, Drill},
  {:training_plan, TrainingPlan},
  {:session, Session}
]

for {name, schema} <- @schemas do
  def unquote(:"list_#{name}s")(), do: Repo.all(unquote(schema))
  def unquote(:"get_#{name}")(id), do: Repo.get(unquote(schema), id)
  # ... creates list_*, get_*, create_*, update_*, delete_* for each schema
end
```

### Behaviour-Based HTTP Adapter

For testability, HTTP calls use a behaviour pattern:

```elixir
# In config/test.exs
config :puck_pro, :http_adapter, PuckPro.HTTP.MockAdapter

# In config/runtime.exs (production)
config :puck_pro, :http_adapter, PuckPro.HTTP.ReqAdapter
```

### Async Assigns in LiveView

Dashboard uses async assigns for non-blocking data loading:

```elixir
socket
|> assign_async(:stats, fn -> {:ok, %{stats: calculate_stats(player)}} end)
|> assign_async(:recent_sessions, fn -> {:ok, %{recent_sessions: load_sessions()}} end)
```

### LiveView Streams

Lists use streams for efficient DOM updates:

```elixir
|> stream(:drills, Training.list_drills_with_categories())
```

## Database Schema

- **players** - User profiles with XP, level, streak tracking
- **skill_categories** - Shooting, Stickhandling, Skating, Passing, Goalie
- **drills** - Individual practice exercises with difficulty ratings
- **training_plans** - Multi-week structured programs
- **plan_drills** - Junction table linking drills to plans with scheduling
- **player_plans** - Tracks player enrollment and progress in plans
- **sessions** - Practice session records with stats
- **session_videos** - Uploaded video files for AI analysis
- **ai_analyses** - Claude AI feedback on videos
- **achievements** - Gamification badges
- **skill_progress** - Per-skill proficiency tracking
- **daily_stats** - Day-by-day practice metrics

## AI Integration

The `PuckPro.AI` module integrates with Claude for:

1. **Video Analysis** - Analyzes uploaded practice videos for form feedback
2. **Session Review** - Provides personalized coaching based on session stats
3. **Streaming Responses** - Uses SSE streaming for real-time feedback display

```elixir
# Streaming AI analysis
PuckPro.AI.analyze_session_streaming(session, player, fn chunk ->
  send(self(), {:ai_chunk, chunk})
end)
```

## Design System

Uses daisyUI with custom ice-rink inspired dark theme:

- **Primary**: Ice blue (`oklch(65% 0.18 230)`)
- **Accent**: Gold/amber (`oklch(78% 0.16 85)`)
- **Success**: Rink green (`oklch(70% 0.15 145)`)
- **Base colors**: Dark slate grays

Custom CSS animations: `pulse-slow`, `slide-up`, `fade-in`

## Environment Variables

```bash
ANTHROPIC_API_KEY=your_api_key_here  # Required for AI features
```

## Testing

```bash
# Run all tests
mix test

# Run specific test file
mix test test/puck_pro/training_test.exs

# Run with coverage
mix test --cover
```

Mock the HTTP adapter in tests:

```elixir
# test/test_helper.exs
Application.put_env(:puck_pro, :http_adapter, PuckPro.HTTP.MockAdapter)
```

## Routes

| Path | LiveView | Description |
|------|----------|-------------|
| `/` | DashboardLive | Main dashboard with stats and quick actions |
| `/drills` | DrillsLive | Browse drill library with filters |
| `/drills/:slug` | DrillLive | Individual drill details |
| `/plans` | PlansLive | Training plan catalog |
| `/plans/:slug` | PlanLive | Training plan with drill schedule |
| `/practice` | PracticeLive | Start/track practice sessions |
| `/sessions` | SessionsLive | Practice history |
| `/sessions/:id` | SessionLive | Session details and AI analysis |
| `/progress` | ProgressLive | Skill progress and stats |
| `/achievements` | AchievementsLive | Badge collection |
| `/random` | RandomPracticeLive | Random drill selector |

## XP and Leveling System

Players earn XP from:
- Completing drills (base XP per drill)
- Goals scored during practice (+2 XP each)
- Time spent practicing (+1 XP per minute)
- Unlocking achievements (bonus XP)

Level formula: `floor(:math.sqrt(xp / 100)) + 1`
