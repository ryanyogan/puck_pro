defmodule PuckPro.Video.FrameExtractor do
  @moduledoc """
  Extract key frames from video files using FFmpeg.

  Extracts evenly-spaced frames optimized for Claude Vision analysis,
  resizing to appropriate dimensions and quality settings.
  """

  require Logger

  # Maximum dimension for Claude Vision (maintains aspect ratio)
  @max_dimension 1920

  # JPEG quality (1-31, lower is better)
  @jpeg_quality 2

  @doc """
  Extract key frames from a video file.

  ## Options

  - `:max_frames` - Maximum number of frames to extract (default: 20)
  - `:output_dir` - Directory to save frames (default: system temp dir)

  ## Returns

  - `{:ok, frame_paths}` - List of paths to extracted frame images
  - `{:error, reason}` - If extraction fails
  """
  def extract(video_path, opts \\ []) do
    max_frames = Keyword.get(opts, :max_frames, 20)
    output_dir = Keyword.get(opts, :output_dir, System.tmp_dir!())

    File.mkdir_p!(output_dir)

    with {:ok, duration} <- get_video_duration(video_path),
         {:ok, _} <- extract_frames(video_path, output_dir, duration, max_frames) do
      frame_paths =
        output_dir
        |> Path.join("frame_*.jpg")
        |> Path.wildcard()
        |> Enum.sort()

      {:ok, frame_paths}
    end
  end

  @doc """
  Get video duration in seconds.

  Handles videos without duration metadata (common with chunked webm recordings)
  by estimating from frame count and fps.
  """
  def get_video_duration(video_path) do
    # First try to get duration from format metadata
    args = [
      "-v", "error",
      "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1",
      video_path
    ]

    case System.cmd("ffprobe", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Float.parse(String.trim(output)) do
          {duration, _} when duration > 0 ->
            {:ok, duration}

          _ ->
            # Duration is N/A or invalid, try to estimate from stream info
            Logger.info("Duration metadata unavailable, estimating from stream...")
            estimate_duration_from_stream(video_path)
        end

      {error, _} ->
        Logger.error("FFprobe error: #{error}")
        {:error, {:ffprobe_failed, error}}
    end
  end

  defp estimate_duration_from_stream(video_path) do
    # Get frame count and frame rate to estimate duration
    args = [
      "-v", "error",
      "-select_streams", "v:0",
      "-count_packets",
      "-show_entries", "stream=nb_read_packets,r_frame_rate",
      "-of", "csv=p=0",
      video_path
    ]

    case System.cmd("ffprobe", args, stderr_to_stdout: true) do
      {output, 0} ->
        # Parse output - get the last line which has the actual data
        # (earlier lines might contain warnings)
        lines = output |> String.trim() |> String.split("\n")
        data_line = List.last(lines) || ""
        Logger.info("Stream info: #{data_line}")

        case String.split(data_line, ",") do
          [frame_rate_str, packet_count_str] ->
            fps = parse_frame_rate(String.trim(frame_rate_str))

            case Integer.parse(String.trim(packet_count_str)) do
              {packets, _} when packets > 0 and fps > 0 ->
                duration = packets / fps
                Logger.info("Estimated duration: #{duration}s (#{packets} frames at #{fps} fps)")
                {:ok, duration}

              _ ->
                Logger.warning("Could not calculate duration, using 10s fallback")
                {:ok, 10.0}
            end

          _ ->
            Logger.warning("Unexpected ffprobe output format, using 10s fallback")
            {:ok, 10.0}
        end

      {error, _} ->
        Logger.error("FFprobe stream analysis failed: #{error}")
        # Final fallback
        {:ok, 10.0}
    end
  end

  @doc """
  Get video metadata (dimensions, fps, codec).
  """
  def get_video_metadata(video_path) do
    args = [
      "-v", "error",
      "-select_streams", "v:0",
      "-show_entries", "stream=width,height,r_frame_rate,codec_name",
      "-of", "json",
      video_path
    ]

    case System.cmd("ffprobe", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"streams" => [stream | _]}} ->
            {:ok, %{
              width: stream["width"],
              height: stream["height"],
              fps: parse_frame_rate(stream["r_frame_rate"]),
              codec: stream["codec_name"]
            }}

          _ ->
            {:error, :no_video_stream}
        end

      {error, _} ->
        {:error, {:ffprobe_failed, error}}
    end
  end

  @doc """
  Extract a single frame at a specific timestamp.
  """
  def extract_frame_at(video_path, timestamp_seconds, output_path) do
    args = [
      "-ss", "#{timestamp_seconds}",
      "-i", video_path,
      "-vframes", "1",
      "-vf", scale_filter(),
      "-q:v", "#{@jpeg_quality}",
      "-y",
      output_path
    ]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_, 0} -> {:ok, output_path}
      {error, _} -> {:error, {:ffmpeg_failed, error}}
    end
  end

  @doc """
  Convert a frame image to base64 for Claude Vision API.
  """
  def to_base64(frame_path) do
    case File.read(frame_path) do
      {:ok, data} -> {:ok, Base.encode64(data)}
      error -> error
    end
  end

  @doc """
  Generate a thumbnail from a video at a specific percentage through.
  """
  def generate_thumbnail(video_path, output_path, opts \\ []) do
    position = Keyword.get(opts, :position, 0.1)  # 10% through by default
    size = Keyword.get(opts, :size, 320)

    case get_video_duration(video_path) do
      {:ok, duration} ->
        timestamp = duration * position

        args = [
          "-ss", "#{timestamp}",
          "-i", video_path,
          "-vframes", "1",
          "-vf", "scale=#{size}:-1",
          "-q:v", "#{@jpeg_quality}",
          "-y",
          output_path
        ]

        case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
          {_, 0} -> {:ok, output_path}
          {error, _} -> {:error, {:ffmpeg_failed, error}}
        end

      error ->
        error
    end
  end

  # Private functions

  defp extract_frames(video_path, output_dir, duration, max_frames) do
    # Calculate frame interval
    interval = duration / max_frames
    output_pattern = Path.join(output_dir, "frame_%04d.jpg")

    args = [
      "-i", video_path,
      "-vf", "fps=1/#{interval},#{scale_filter()}",
      "-q:v", "#{@jpeg_quality}",
      "-frames:v", "#{max_frames}",
      "-y",
      output_pattern
    ]

    case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {_, 0} -> {:ok, output_pattern}
      {error, code} ->
        Logger.error("FFmpeg extraction failed (code #{code}): #{error}")
        {:error, {:ffmpeg_failed, error}}
    end
  end

  defp scale_filter do
    "scale='min(#{@max_dimension},iw)':'min(#{@max_dimension},ih)':force_original_aspect_ratio=decrease"
  end

  defp parse_frame_rate(rate_string) when is_binary(rate_string) do
    case String.split(rate_string, "/") do
      [num, den] ->
        {n, _} = Integer.parse(num)
        {d, _} = Integer.parse(den)
        Float.round(n / d, 2)

      [single] ->
        case Float.parse(single) do
          {fps, _} -> fps
          :error -> 0.0
        end

      _ ->
        0.0
    end
  end

  defp parse_frame_rate(_), do: 0.0
end
