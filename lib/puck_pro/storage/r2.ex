defmodule PuckPro.Storage.R2 do
  @moduledoc """
  Cloudflare R2 storage operations for video files and frames.

  Uses ex_aws_s3 for S3-compatible API operations against Cloudflare R2.
  """

  @doc """
  Upload a video file to R2.

  Returns `{:ok, r2_key}` on success.
  """
  def upload_video(local_path, session_id) do
    key = video_key(session_id)

    local_path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(bucket(), key, content_type: "video/webm")
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Upload a frame image to R2.

  Returns `{:ok, r2_key}` on success.
  """
  def upload_frame(frame_data, video_id, frame_number) do
    key = frame_key(video_id, frame_number)

    ExAws.S3.put_object(bucket(), key, frame_data, content_type: "image/jpeg")
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Upload a thumbnail image to R2.
  """
  def upload_thumbnail(data, video_id) do
    key = thumbnail_key(video_id)

    ExAws.S3.put_object(bucket(), key, data, content_type: "image/jpeg")
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Download a file from R2 to a local path.
  """
  def download(r2_key, local_path) do
    ExAws.S3.download_file(bucket(), r2_key, local_path)
    |> ExAws.request()
  end

  @doc """
  Get a public URL for an R2 object.

  Uses the configured public URL endpoint if available.
  """
  def public_url(r2_key) do
    base = Application.get_env(:puck_pro, :r2_public_url)

    if base do
      "#{base}/#{r2_key}"
    else
      # Fallback to direct R2 URL (requires public bucket)
      "https://#{bucket()}.r2.dev/#{r2_key}"
    end
  end

  @doc """
  Generate a presigned URL for temporary access to a private object.

  Expires in 1 hour by default.
  """
  def presigned_url(r2_key, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, 3600)

    config = ExAws.Config.new(:s3)
    ExAws.S3.presigned_url(config, :get, bucket(), r2_key, expires_in: expires_in)
  end

  @doc """
  Delete an object from R2.
  """
  def delete(r2_key) do
    ExAws.S3.delete_object(bucket(), r2_key)
    |> ExAws.request()
  end

  @doc """
  Delete all objects under a prefix (e.g., all frames for a video).
  """
  def delete_prefix(prefix) do
    bucket()
    |> ExAws.S3.list_objects(prefix: prefix)
    |> ExAws.stream!()
    |> Stream.map(& &1.key)
    |> Stream.chunk_every(1000)
    |> Enum.each(fn keys ->
      ExAws.S3.delete_all_objects(bucket(), keys)
      |> ExAws.request()
    end)

    :ok
  end

  @doc """
  Check if an object exists in R2.
  """
  def exists?(r2_key) do
    case ExAws.S3.head_object(bucket(), r2_key) |> ExAws.request() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Initialize a multipart upload for streaming video.

  Returns `{:ok, upload_id}` on success.
  """
  def init_multipart_upload(session_id) do
    key = video_key(session_id)

    case ExAws.S3.initiate_multipart_upload(bucket(), key) |> ExAws.request() do
      {:ok, %{body: %{upload_id: upload_id}}} ->
        {:ok, %{key: key, upload_id: upload_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Upload a part in a multipart upload.

  Returns `{:ok, etag}` on success.
  """
  def upload_part(key, upload_id, part_number, data) do
    ExAws.S3.upload_part(bucket(), key, upload_id, part_number, data)
    |> ExAws.request()
    |> case do
      {:ok, %{headers: headers}} ->
        etag = get_header(headers, "etag")
        {:ok, etag}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Complete a multipart upload.

  `parts` should be a list of `{part_number, etag}` tuples in order.
  """
  def complete_multipart_upload(key, upload_id, parts) do
    ExAws.S3.complete_multipart_upload(bucket(), key, upload_id, parts)
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Abort a multipart upload.
  """
  def abort_multipart_upload(key, upload_id) do
    ExAws.S3.abort_multipart_upload(bucket(), key, upload_id)
    |> ExAws.request()
  end

  # Private helpers

  defp bucket do
    Application.get_env(:puck_pro, :r2_bucket)
  end

  defp video_key(session_id) do
    timestamp = :os.system_time(:millisecond)
    "videos/#{session_id}/#{timestamp}.webm"
  end

  defp frame_key(video_id, frame_number) do
    padded = String.pad_leading("#{frame_number}", 4, "0")
    "frames/#{video_id}/frame_#{padded}.jpg"
  end

  defp thumbnail_key(video_id) do
    "thumbnails/#{video_id}.jpg"
  end

  defp get_header(headers, name) do
    Enum.find_value(headers, fn
      {^name, value} -> value
      {key, value} when is_binary(key) -> if String.downcase(key) == name, do: value
      _ -> nil
    end)
  end
end
