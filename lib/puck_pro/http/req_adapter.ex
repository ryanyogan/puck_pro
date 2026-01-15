defmodule PuckPro.HTTP.ReqAdapter do
  @moduledoc """
  Production HTTP adapter using Req library.
  """
  @behaviour PuckPro.HTTP.Adapter

  @impl true
  def get_json(url), do: get_json(url, [])

  @impl true
  def get_json(url, headers) do
    case Req.get(url, headers: headers) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def post_json(url, body), do: post_json(url, body, [])

  @impl true
  def post_json(url, body, headers) do
    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def stream_post(url, body, headers, callback) when is_function(callback) do
    # Use Process dictionary to accumulate response across callback invocations
    Process.put(:stream_response, "")

    into_fn = fn {:data, data}, {req, resp} ->
      # Call callback and accumulate any returned text
      case callback.({:data, data}) do
        chunk when is_binary(chunk) ->
          current = Process.get(:stream_response, "")
          Process.put(:stream_response, current <> chunk)
        _ ->
          :ok
      end
      {:cont, {req, resp}}
    end

    case Req.post(url, json: body, headers: headers, into: into_fn) do
      {:ok, %{status: status}} when status in 200..299 ->
        callback.(:done)
        accumulated = Process.get(:stream_response, "")
        Process.delete(:stream_response)
        {:ok, accumulated}

      {:ok, %{status: status, body: body}} ->
        Process.delete(:stream_response)
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Process.delete(:stream_response)
        {:error, reason}
    end
  end
end
