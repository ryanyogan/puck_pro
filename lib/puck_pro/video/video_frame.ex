defmodule PuckPro.Video.VideoFrame do
  @moduledoc """
  Individual frames extracted from session videos for AI analysis.

  Each frame captures a moment during practice that can be analyzed
  by Claude Vision for form feedback and shot detection.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "video_frames" do
    belongs_to :session_video, PuckPro.Training.SessionVideo

    field :frame_number, :integer
    field :timestamp_ms, :integer
    field :storage_path, :string
    field :r2_key, :string
    field :file_size, :integer

    # Elements detected in this frame by AI
    # e.g., %{shot_detected: true, shot_type: "wrist", player_position: "slot"}
    field :detected_elements, :map, default: %{}

    timestamps()
  end

  @cast_fields ~w(
    session_video_id frame_number timestamp_ms storage_path
    r2_key file_size detected_elements
  )a

  def changeset(frame, attrs) do
    frame
    |> cast(attrs, @cast_fields)
    |> validate_required([:session_video_id, :frame_number, :timestamp_ms, :storage_path])
    |> validate_number(:frame_number, greater_than_or_equal_to: 0)
    |> validate_number(:timestamp_ms, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:session_video_id)
    |> unique_constraint([:session_video_id, :frame_number])
  end

  @doc """
  Convert frame image to base64 for Claude Vision API.
  """
  def to_base64(%__MODULE__{storage_path: path}) when is_binary(path) do
    case File.read(path) do
      {:ok, data} -> {:ok, Base.encode64(data)}
      error -> error
    end
  end

  def to_base64(_), do: {:error, :no_storage_path}

  @doc """
  Calculate timestamp in human-readable format (MM:SS.mmm)
  """
  def timestamp_display(%__MODULE__{timestamp_ms: ms}) when is_integer(ms) do
    total_seconds = div(ms, 1000)
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    millis = rem(ms, 1000)

    mins = String.pad_leading("#{minutes}", 2, "0")
    secs = String.pad_leading("#{seconds}", 2, "0")
    ms_str = String.pad_leading("#{millis}", 3, "0")

    "#{mins}:#{secs}.#{ms_str}"
  end

  def timestamp_display(_), do: "00:00.000"
end
