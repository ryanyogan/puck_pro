defmodule PuckPro.Video do
  @moduledoc """
  Video processing context for session video management.

  Handles video storage, frame extraction, and coordination with AI analysis.
  """

  import Ecto.Query
  alias PuckPro.Repo
  alias PuckPro.Training.{Session, SessionVideo}
  alias PuckPro.Video.{VideoFrame, FrameExtractor}
  alias PuckPro.Storage.R2
  alias PuckPro.AI

  @doc """
  Create a session video record for R2-stored video.
  """
  def create_session_video(session_id, attrs) do
    %SessionVideo{}
    |> SessionVideo.changeset(Map.put(attrs, :session_id, session_id))
    |> Repo.insert()
  end

  @doc """
  Update a session video record.
  """
  def update_session_video(%SessionVideo{} = video, attrs) do
    video
    |> SessionVideo.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Get a session video by ID with frames preloaded.
  """
  def get_session_video(id) do
    SessionVideo
    |> Repo.get(id)
    |> Repo.preload(:video_frames)
  end

  @doc """
  Get the session video for a session.
  """
  def get_video_for_session(session_id) do
    SessionVideo
    |> where([v], v.session_id == ^session_id)
    |> order_by([v], desc: v.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      video -> Repo.preload(video, :video_frames)
    end
  end

  @doc """
  List video frames for a session video.
  """
  def list_frames(session_video_id) do
    VideoFrame
    |> where([f], f.session_video_id == ^session_video_id)
    |> order_by([f], asc: f.frame_number)
    |> Repo.all()
  end

  @doc """
  Create a video frame record.
  """
  def create_frame(attrs) do
    %VideoFrame{}
    |> VideoFrame.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Process a completed session's video.

  1. Downloads video from R2 to temp file
  2. Extracts key frames using FFmpeg
  3. Uploads frames to R2
  4. Creates frame records
  5. Triggers AI analysis
  """
  def process_session_video(session_id) do
    Task.Supervisor.start_child(PuckPro.TaskSupervisor, fn ->
      do_process_video(session_id)
    end)
  end

  defp do_process_video(session_id) do
    session = Repo.get!(Session, session_id) |> Repo.preload([:player, :drill])
    video = get_video_for_session(session_id)

    if video && video.r2_key do
      try do
        # Update status to processing
        {:ok, video} = update_session_video(video, %{status: "processing"})

        # Create temp directory for this video
        temp_dir = Path.join(System.tmp_dir!(), "puck_pro_video_#{video.id}")
        File.mkdir_p!(temp_dir)
        temp_video_path = Path.join(temp_dir, "video.webm")

        # Download video from R2
        case R2.download(video.r2_key, temp_video_path) do
          {:ok, _} ->
            process_video_file(video, session, temp_video_path, temp_dir)

          {:error, reason} ->
            update_session_video(video, %{
              status: "failed",
              error_message: "Failed to download video: #{inspect(reason)}"
            })
        end
      rescue
        e ->
          update_session_video(video, %{
            status: "failed",
            error_message: "Processing error: #{Exception.message(e)}"
          })
      end
    end
  end

  defp process_video_file(video, session, video_path, temp_dir) do
    frames_dir = Path.join(temp_dir, "frames")
    File.mkdir_p!(frames_dir)

    # Update status to extracting
    {:ok, video} = update_session_video(video, %{status: "extracting"})

    # Extract frames
    case FrameExtractor.extract(video_path, max_frames: 20, output_dir: frames_dir) do
      {:ok, frame_paths} ->
        # Upload frames and create records
        frames = upload_and_record_frames(video, frame_paths)

        # Update video with frame count
        {:ok, video} = update_session_video(video, %{
          status: "ready",
          frame_count: length(frames),
          frames_extracted_at: DateTime.utc_now()
        })

        # Start AI analysis
        topic = "analysis:#{session.id}"
        AI.analyze_video_streaming(video, session, topic)

        # Cleanup temp files
        File.rm_rf!(temp_dir)

        {:ok, video}

      {:error, reason} ->
        update_session_video(video, %{
          status: "failed",
          error_message: "Frame extraction failed: #{inspect(reason)}"
        })

        File.rm_rf!(temp_dir)
        {:error, reason}
    end
  end

  defp upload_and_record_frames(video, frame_paths) do
    frame_paths
    |> Enum.with_index(1)
    |> Enum.map(fn {path, frame_number} ->
      # Read frame data
      {:ok, data} = File.read(path)
      file_size = byte_size(data)

      # Calculate timestamp from filename (frame_XXXX.jpg -> frame number * interval)
      timestamp_ms = frame_number * estimate_interval_ms(video, length(frame_paths))

      # Upload to R2
      case R2.upload_frame(data, video.id, frame_number) do
        {:ok, r2_key} ->
          # Create frame record
          {:ok, frame} = create_frame(%{
            session_video_id: video.id,
            frame_number: frame_number,
            timestamp_ms: timestamp_ms,
            storage_path: path,
            r2_key: r2_key,
            file_size: file_size
          })
          frame

        {:error, _reason} ->
          # Create local-only record on R2 failure
          {:ok, frame} = create_frame(%{
            session_video_id: video.id,
            frame_number: frame_number,
            timestamp_ms: timestamp_ms,
            storage_path: path,
            file_size: file_size
          })
          frame
      end
    end)
  end

  defp estimate_interval_ms(%SessionVideo{duration_seconds: nil}, frame_count) do
    # Default to 5 seconds per frame if duration unknown
    div(frame_count * 5000, max(frame_count, 1))
  end

  defp estimate_interval_ms(%SessionVideo{duration_seconds: duration}, frame_count) do
    div(duration * 1000, max(frame_count, 1))
  end
end
