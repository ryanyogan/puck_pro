defmodule PuckPro.Uploads.R2Writer do
  @moduledoc """
  Custom UploadWriter that streams video chunks directly to Cloudflare R2
  via multipart upload.

  This writer implements Phoenix.LiveView.UploadWriter behaviour to handle
  real-time video streaming from the browser's MediaRecorder API.

  ## Usage

  Configure in LiveView with:

      allow_upload(socket, :video_stream,
        accept: ~w(.webm),
        max_entries: 100,
        max_file_size: 50_000_000,
        auto_upload: true,
        writer: fn _name, _entry, socket ->
          {PuckPro.Uploads.R2Writer, session_id: socket.assigns.session.id}
        end
      )
  """

  @behaviour Phoenix.LiveView.UploadWriter

  alias PuckPro.Storage.R2

  # Minimum part size for R2/S3 multipart upload (5MB)
  @min_part_size 5 * 1024 * 1024

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    case R2.init_multipart_upload(session_id) do
      {:ok, %{key: key, upload_id: upload_id}} ->
        {:ok,
         %{
           key: key,
           upload_id: upload_id,
           parts: [],
           part_number: 1,
           buffer: <<>>,
           total_bytes: 0
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def meta(state) do
    %{
      r2_key: state.key,
      upload_id: state.upload_id,
      parts_uploaded: length(state.parts),
      total_bytes: state.total_bytes
    }
  end

  @impl true
  def write_chunk(data, state) do
    buffer = state.buffer <> data
    total_bytes = state.total_bytes + byte_size(data)

    if byte_size(buffer) >= @min_part_size do
      # Upload the buffer as a part
      case upload_part(state, buffer) do
        {:ok, etag} ->
          {:ok,
           %{
             state
             | buffer: <<>>,
               parts: [{state.part_number, etag} | state.parts],
               part_number: state.part_number + 1,
               total_bytes: total_bytes
           }}

        {:error, reason} ->
          {:error, reason, state}
      end
    else
      # Keep buffering until we have enough data
      {:ok, %{state | buffer: buffer, total_bytes: total_bytes}}
    end
  end

  @impl true
  def close(state, :done) do
    # Upload any remaining buffer as the final part
    result =
      if byte_size(state.buffer) > 0 do
        case upload_part(state, state.buffer) do
          {:ok, etag} ->
            parts = [{state.part_number, etag} | state.parts]
            R2.complete_multipart_upload(state.key, state.upload_id, Enum.reverse(parts))

          {:error, reason} ->
            # Try to abort the upload on error
            R2.abort_multipart_upload(state.key, state.upload_id)
            {:error, reason}
        end
      else
        # Complete with existing parts
        R2.complete_multipart_upload(state.key, state.upload_id, Enum.reverse(state.parts))
      end

    case result do
      {:ok, key} ->
        {:ok,
         %{
           r2_key: key,
           total_bytes: state.total_bytes,
           parts_count: length(state.parts) + (if byte_size(state.buffer) > 0, do: 1, else: 0)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def close(state, :cancel) do
    # Abort the multipart upload on cancel
    R2.abort_multipart_upload(state.key, state.upload_id)
    {:ok, nil}
  end

  def close(state, {:error, _reason}) do
    # Abort the multipart upload on error
    R2.abort_multipart_upload(state.key, state.upload_id)
    {:ok, nil}
  end

  # Private helpers

  defp upload_part(state, data) do
    R2.upload_part(state.key, state.upload_id, state.part_number, data)
  end
end
