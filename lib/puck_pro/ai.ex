defmodule PuckPro.AI do
  @moduledoc """
  AI module for Claude-powered hockey training analysis and coaching.

  Supports both synchronous and streaming responses for real-time feedback.
  """
  import Ecto.Query
  alias PuckPro.Repo
  alias PuckPro.AI.Analysis
  alias PuckPro.AI.HockeyPrompts
  alias PuckPro.Training.{Session, SessionVideo, Drill}
  alias PuckPro.Video.FrameExtractor

  @anthropic_url "https://api.anthropic.com/v1/messages"
  @model "claude-opus-4-5-20251101"
  @vision_model "claude-opus-4-5-20251101"

  # ============================================================================
  # ANALYSIS CRUD
  # ============================================================================

  def list_analyses_for_session(session_id) do
    from(a in Analysis, where: a.session_id == ^session_id, order_by: [desc: a.inserted_at])
    |> Repo.all()
  end

  def get_analysis!(id), do: Repo.get!(Analysis, id)

  def create_analysis(attrs) do
    %Analysis{}
    |> Analysis.changeset(attrs)
    |> Repo.insert()
  end

  def update_analysis(%Analysis{} = analysis, attrs) do
    analysis
    |> Analysis.changeset(attrs)
    |> Repo.update()
  end

  # ============================================================================
  # CLAUDE API - Synchronous
  # ============================================================================

  @doc """
  Make a request to Claude API and return the complete response.
  """
  def complete(system_prompt, user_message) do
    body = %{
      model: @model,
      max_tokens: 2048,
      system: system_prompt,
      messages: [
        %{role: "user", content: user_message}
      ]
    }

    case http_adapter().post_json(@anthropic_url, body, headers()) do
      {:ok, %{"content" => [%{"text" => text} | _]}} ->
        {:ok, text}

      {:ok, response} ->
        {:error, {:unexpected_response, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # CLAUDE API - Streaming
  # ============================================================================

  @doc """
  Make a streaming request to Claude API.

  The callback function will be called with:
  - `{:text, chunk}` for each text chunk
  - `:done` when streaming is complete
  """
  def stream(system_prompt, user_message, callback) when is_function(callback) do
    body = %{
      model: @model,
      max_tokens: 2048,
      stream: true,
      system: system_prompt,
      messages: [
        %{role: "user", content: user_message}
      ]
    }

    buffer = ""

    stream_callback = fn
      {:data, data} ->
        # Parse SSE events
        {events, _remaining} = parse_sse_events(buffer <> data)
        Enum.each(events, fn event -> handle_stream_event(event, callback) end)

      :done ->
        callback.(:done)
    end

    http_adapter().stream_post(@anthropic_url, body, headers(), stream_callback)
  end

  defp parse_sse_events(data) do
    lines = String.split(data, "\n")

    events =
      lines
      |> Enum.filter(&String.starts_with?(&1, "data: "))
      |> Enum.map(&String.replace_prefix(&1, "data: ", ""))
      |> Enum.filter(&(&1 != "[DONE]"))
      |> Enum.map(fn json_str ->
        case Jason.decode(json_str) do
          {:ok, event} -> event
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {events, ""}
  end

  defp handle_stream_event(%{"type" => "content_block_delta", "delta" => %{"text" => text}}, callback) do
    callback.({:text, text})
  end

  defp handle_stream_event(_, _), do: :ok

  # ============================================================================
  # TRAINING ANALYSIS
  # ============================================================================

  @doc """
  Analyze a completed session and provide feedback.

  Returns {:ok, analysis} on success or {:error, reason} on failure.
  """
  def analyze_session(%Session{} = session) do
    session = Repo.preload(session, [:drill, :player])

    # Create analysis record in pending state
    {:ok, analysis} =
      create_analysis(%{
        session_id: session.id,
        status: "processing",
        started_at: DateTime.utc_now()
      })

    Task.Supervisor.start_child(PuckPro.TaskSupervisor, fn ->
      do_analyze_session(session, analysis)
    end)

    {:ok, analysis}
  end

  @doc """
  Analyze a session with streaming feedback to a PubSub topic.
  """
  def analyze_session_streaming(%Session{} = session, topic) do
    session = Repo.preload(session, [:drill, :player])

    {:ok, analysis} =
      create_analysis(%{
        session_id: session.id,
        status: "processing",
        started_at: DateTime.utc_now()
      })

    Task.Supervisor.start_child(PuckPro.TaskSupervisor, fn ->
      do_analyze_session_streaming(session, analysis, topic)
    end)

    {:ok, analysis}
  end

  defp do_analyze_session(session, analysis) do
    system = training_coach_system_prompt(session.player)
    user = session_analysis_prompt(session)

    case complete(system, user) do
      {:ok, response} ->
        parsed = parse_analysis_response(response)

        update_analysis(analysis, %{
          status: "completed",
          completed_at: DateTime.utc_now(),
          model_used: @model,
          strengths: parsed.strengths,
          improvements: parsed.improvements,
          metrics: parsed.metrics,
          overall_score: parsed.overall_score,
          summary: parsed.summary,
          raw_response: response
        })

      {:error, reason} ->
        update_analysis(analysis, %{
          status: "failed",
          completed_at: DateTime.utc_now(),
          raw_response: inspect(reason)
        })
    end
  end

  defp do_analyze_session_streaming(session, analysis, topic) do
    system = training_coach_system_prompt(session.player)
    user = session_analysis_prompt(session)
    _accumulated = ""

    callback = fn
      {:text, chunk} ->
        Phoenix.PubSub.broadcast(PuckPro.PubSub, topic, {:ai_chunk, chunk})

      :done ->
        Phoenix.PubSub.broadcast(PuckPro.PubSub, topic, :ai_done)
    end

    case stream(system, user, callback) do
      {:ok, :streamed} ->
        # Note: For streaming, we'd need to accumulate the response
        # For now, we mark as completed
        update_analysis(analysis, %{
          status: "completed",
          completed_at: DateTime.utc_now(),
          model_used: @model
        })

      {:error, reason} ->
        update_analysis(analysis, %{
          status: "failed",
          completed_at: DateTime.utc_now(),
          raw_response: inspect(reason)
        })
    end
  end

  # ============================================================================
  # VIDEO ANALYSIS (Vision)
  # ============================================================================

  @doc """
  Analyze a session video using Claude Vision.

  Extracts frames from the video, sends them to Claude Vision API,
  and streams the analysis results via PubSub.
  """
  def analyze_video_streaming(%SessionVideo{} = video, %Session{} = session, topic) do
    session = Repo.preload(session, [:drill, :player])
    # Force reload video with fresh frames (they may have just been created)
    video = Repo.get!(SessionVideo, video.id) |> Repo.preload(:video_frames)

    {:ok, analysis} =
      create_analysis(%{
        session_id: session.id,
        session_video_id: video.id,
        analysis_type: "video",
        status: "processing",
        started_at: DateTime.utc_now()
      })

    Task.Supervisor.start_child(PuckPro.TaskSupervisor, fn ->
      do_analyze_video_streaming(video, session, analysis, topic)
    end)

    {:ok, analysis}
  end

  defp do_analyze_video_streaming(video, session, analysis, topic) do
    frames = video.video_frames

    if Enum.empty?(frames) do
      update_analysis(analysis, %{
        status: "failed",
        completed_at: DateTime.utc_now(),
        raw_response: "No frames available for analysis"
      })

      Phoenix.PubSub.broadcast(PuckPro.PubSub, topic, {:analysis_error, "No video frames found"})
    else
      # Build vision content with images
      content = build_vision_content(frames, session.drill)
      system = HockeyPrompts.video_analysis_system(session.player, session.drill)

      callback = fn
        {:text, chunk} ->
          Phoenix.PubSub.broadcast(PuckPro.PubSub, topic, {:analysis_chunk, chunk})
          chunk

        :done ->
          Phoenix.PubSub.broadcast(PuckPro.PubSub, topic, :analysis_done)
          nil
      end

      case stream_vision(system, content, callback) do
        {:ok, full_response} ->
          parsed = parse_vision_analysis_response(full_response)

          update_analysis(analysis, %{
            status: "completed",
            completed_at: DateTime.utc_now(),
            model_used: @vision_model,
            analysis_type: "video",
            frames_analyzed: length(frames),
            form_metrics: parsed.form_metrics,
            technique_scores: parsed.technique_scores,
            detected_shots: parsed.detected_shots,
            recommended_drills: parsed.recommended_drills,
            strengths: parsed.strengths,
            improvements: parsed.improvements,
            overall_score: parsed.overall_score,
            summary: parsed.summary,
            raw_response: full_response
          })

          Phoenix.PubSub.broadcast(PuckPro.PubSub, topic, {:analysis_complete, parsed})

        {:error, reason} ->
          update_analysis(analysis, %{
            status: "failed",
            completed_at: DateTime.utc_now(),
            raw_response: inspect(reason)
          })

          Phoenix.PubSub.broadcast(PuckPro.PubSub, topic, {:analysis_error, inspect(reason)})
      end
    end
  end

  defp build_vision_content(frames, drill) do
    alias PuckPro.Storage.R2

    # Build image content blocks
    image_blocks =
      frames
      |> Enum.take(20)  # Max 20 images for Claude Vision
      |> Enum.map(fn frame ->
        # Try local file first, then R2
        base64 = cond do
          File.exists?(frame.storage_path) ->
            case File.read(frame.storage_path) do
              {:ok, data} -> Base.encode64(data)
              _ -> nil
            end

          frame.r2_key ->
            # Download from R2
            temp_path = Path.join(System.tmp_dir!(), "frame_#{frame.id}.jpg")
            case R2.download(frame.r2_key, temp_path) do
              {:ok, _} ->
                case File.read(temp_path) do
                  {:ok, data} ->
                    File.rm(temp_path)
                    Base.encode64(data)
                  _ ->
                    nil
                end
              _ ->
                nil
            end

          true ->
            nil
        end

        if base64 do
          %{
            "type" => "image",
            "source" => %{
              "type" => "base64",
              "media_type" => "image/jpeg",
              "data" => base64
            }
          }
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Add text prompt
    text_block = %{
      "type" => "text",
      "text" => HockeyPrompts.video_analysis_user(length(image_blocks), drill)
    }

    image_blocks ++ [text_block]
  end

  @doc """
  Make a streaming vision request to Claude API.
  """
  def stream_vision(system_prompt, content, callback) when is_function(callback) do
    body = %{
      model: @vision_model,
      max_tokens: 4096,
      stream: true,
      system: system_prompt,
      messages: [
        %{role: "user", content: content}
      ]
    }

    stream_callback = fn
      {:data, data} ->
        {events, _remaining} = parse_sse_events(data)

        chunks =
          Enum.map(events, fn event ->
            case handle_stream_event_with_return(event) do
              {:text, text} ->
                callback.({:text, text})
                text

              nil ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.join("")

        # Return chunks so they get accumulated by the HTTP adapter
        chunks

      :done ->
        callback.(:done)
        nil
    end

    case http_adapter().stream_post(@anthropic_url, body, headers(), stream_callback) do
      {:ok, response} when is_binary(response) ->
        {:ok, response}

      error ->
        error
    end
  end

  defp handle_stream_event_with_return(%{"type" => "content_block_delta", "delta" => %{"text" => text}}) do
    {:text, text}
  end

  defp handle_stream_event_with_return(_), do: nil

  defp parse_vision_analysis_response(response) do
    # Try to extract JSON from the response
    json_match = Regex.run(~r/\{[\s\S]*\}/, response)

    parsed =
      case json_match do
        [json_str] ->
          case Jason.decode(json_str) do
            {:ok, json} -> json
            _ -> %{}
          end

        _ ->
          %{}
      end

    %{
      form_metrics: Map.get(parsed, "form_metrics", %{}),
      technique_scores: Map.get(parsed, "technique_scores", %{}),
      detected_shots: Map.get(parsed, "detected_shots", []),
      recommended_drills: Map.get(parsed, "recommended_drills", []),
      strengths: Map.get(parsed, "strengths", []),
      improvements: Map.get(parsed, "improvements", []),
      overall_score: Map.get(parsed, "overall_score"),
      summary: Map.get(parsed, "summary", response)
    }
  end

  # ============================================================================
  # DRILL GENERATION
  # ============================================================================

  @doc """
  Generate a custom drill based on player needs.
  """
  def generate_custom_drill(player, focus_area, difficulty) do
    system = drill_generator_system_prompt()

    user = """
    Generate a hockey drill for a #{player.age}-year-old player with #{player.experience_years} years of experience.

    Focus area: #{focus_area}
    Difficulty: #{difficulty}
    Position: #{player.position}

    The drill should be suitable for indoor practice with synthetic ice and a net.
    """

    case complete(system, user) do
      {:ok, response} ->
        parse_drill_response(response)

      error ->
        error
    end
  end

  @doc """
  Get coaching tips for a specific drill.
  """
  def get_drill_tips(%Drill{} = drill) do
    system = """
    You are an expert hockey coach specializing in youth development.
    Provide helpful, encouraging tips that are age-appropriate for young players.
    Keep tips actionable and easy to understand.
    """

    user = """
    Provide 3-5 coaching tips for this drill:

    Name: #{drill.name}
    Description: #{drill.description}
    Instructions: #{drill.instructions}
    Difficulty: #{drill.difficulty}

    Focus on proper technique, common mistakes to avoid, and how to make progress.
    """

    complete(system, user)
  end

  # ============================================================================
  # PROMPTS
  # ============================================================================

  defp training_coach_system_prompt(player) do
    """
    You are Coach AI, a friendly and encouraging hockey coach for young players.
    You specialize in helping #{player.age}-year-old players improve their skills.

    Your coaching style is:
    - Positive and encouraging - always start with what they did well
    - Specific and actionable - give concrete tips they can work on
    - Age-appropriate - use simple language a kid can understand
    - Fun - make hockey enjoyable, use hockey analogies they'll love

    When analyzing a session, provide:
    1. 2-3 specific strengths (what they did great!)
    2. 2-3 areas to improve (presented as "level up" opportunities)
    3. An overall score from 1-100
    4. A brief, encouraging summary

    Format your response as JSON with this structure:
    {
      "strengths": [{"title": "...", "detail": "..."}],
      "improvements": [{"title": "...", "detail": "...", "tip": "..."}],
      "metrics": {"technique": 0-100, "effort": 0-100, "consistency": 0-100},
      "overall_score": 0-100,
      "summary": "..."
    }
    """
  end

  defp session_analysis_prompt(session) do
    drill_info =
      if session.drill do
        """
        Drill: #{session.drill.name}
        Description: #{session.drill.description}
        Focus: #{session.drill.skill_category_id && "Skill category ##{session.drill.skill_category_id}"}
        """
      else
        "Free practice session"
      end

    """
    Please analyze this practice session:

    #{drill_info}

    Session Stats:
    - Duration: #{Session.duration_minutes(session)} minutes
    - Shots attempted: #{session.shots_attempted}
    - Shots on goal: #{session.shots_on_goal}
    - Goals scored: #{session.goals_scored}
    - Shooting percentage: #{Session.shooting_percentage(session)}%
    - Accuracy: #{Session.accuracy_percentage(session)}%

    Player notes: #{session.notes || "None"}

    Provide your analysis in the JSON format specified.
    """
  end

  defp drill_generator_system_prompt do
    """
    You are an expert hockey drill designer specializing in youth development.
    Create drills that are:
    - Safe and appropriate for the player's age and skill level
    - Effective for developing specific skills
    - Engaging and fun
    - Suitable for indoor practice with synthetic ice

    Format your response as JSON:
    {
      "name": "...",
      "description": "...",
      "instructions": "Step-by-step instructions...",
      "tips": "Coaching tips...",
      "duration_minutes": 10,
      "equipment_needed": ["pucks", "cones", etc],
      "focus_skill": "shooting/skating/stickhandling/etc"
    }
    """
  end

  defp parse_analysis_response(response) do
    case Jason.decode(response) do
      {:ok, json} ->
        %{
          strengths: Map.get(json, "strengths", []),
          improvements: Map.get(json, "improvements", []),
          metrics: Map.get(json, "metrics", %{}),
          overall_score: Map.get(json, "overall_score"),
          summary: Map.get(json, "summary")
        }

      {:error, _} ->
        # If not valid JSON, create a basic response
        %{
          strengths: [],
          improvements: [],
          metrics: %{},
          overall_score: nil,
          summary: response
        }
    end
  end

  defp parse_drill_response(response) do
    case Jason.decode(response) do
      {:ok, json} -> {:ok, json}
      {:error, _} -> {:ok, %{"description" => response}}
    end
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  defp headers do
    api_key = Application.get_env(:puck_pro, :anthropic_api_key)

    [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]
  end

  defp http_adapter do
    PuckPro.HTTP.Adapter.adapter()
  end
end
