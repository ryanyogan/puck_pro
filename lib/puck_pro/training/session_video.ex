defmodule PuckPro.Training.SessionVideo do
  @moduledoc """
  Video recordings of practice sessions for AI analysis.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(uploading uploaded processing extracting ready failed)

  schema "session_videos" do
    belongs_to :session, PuckPro.Training.Session
    has_many :video_frames, PuckPro.Video.VideoFrame

    field :filename, :string
    field :content_type, :string
    field :file_size, :integer
    field :storage_path, :string

    # Cloudflare R2 storage
    field :r2_key, :string
    field :r2_url, :string
    field :thumbnail_path, :string
    field :thumbnail_r2_key, :string

    # Frame extraction
    field :frame_count, :integer, default: 0
    field :frames_extracted_at, :utc_datetime

    # Video metadata
    field :duration_seconds, :integer
    field :width, :integer
    field :height, :integer
    field :fps, :float

    field :status, :string, default: "uploaded"
    field :error_message, :string

    timestamps()
  end

  @cast_fields ~w(
    session_id filename content_type file_size storage_path
    r2_key r2_url thumbnail_path thumbnail_r2_key
    frame_count frames_extracted_at
    duration_seconds width height fps status error_message
  )a

  def changeset(video, attrs) do
    video
    |> cast(attrs, @cast_fields)
    |> validate_required([:session_id, :filename])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:session_id)
  end

  @doc "Human-readable file size"
  def human_size(%__MODULE__{file_size: nil}), do: "Unknown"
  def human_size(%__MODULE__{file_size: bytes}) when bytes < 1024, do: "#{bytes} B"
  def human_size(%__MODULE__{file_size: bytes}) when bytes < 1024 * 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end
  def human_size(%__MODULE__{file_size: bytes}) do
    "#{Float.round(bytes / (1024 * 1024), 1)} MB"
  end
end
