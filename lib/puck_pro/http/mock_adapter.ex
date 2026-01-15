defmodule PuckPro.HTTP.MockAdapter do
  @moduledoc """
  Mock HTTP adapter for testing.
  Uses an Agent to store expected responses.
  """
  @behaviour PuckPro.HTTP.Adapter

  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc "Set a mock response for a URL"
  def set_response(url, response) do
    Agent.update(__MODULE__, fn state -> Map.put(state, url, response) end)
  end

  @doc "Clear all mock responses"
  def clear do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end

  @impl true
  def get_json(url), do: get_json(url, [])

  @impl true
  def get_json(url, _headers) do
    get_response(url)
  end

  @impl true
  def post_json(url, _body), do: post_json(url, %{}, [])

  @impl true
  def post_json(url, _body, _headers) do
    get_response(url)
  end

  @impl true
  def stream_post(url, _body, _headers, callback) when is_function(callback) do
    case get_response(url) do
      {:ok, response} ->
        # Simulate streaming by sending response in chunks
        chunks = chunk_response(response)
        Enum.each(chunks, fn chunk -> callback.({:data, chunk}) end)
        callback.(:done)
        {:ok, :streamed}

      error ->
        error
    end
  end

  defp get_response(url) do
    case Agent.get(__MODULE__, fn state -> Map.get(state, url) end) do
      nil -> {:error, :not_found}
      response -> response
    end
  end

  defp chunk_response(response) when is_map(response) do
    [Jason.encode!(response)]
  end

  defp chunk_response(response) when is_binary(response) do
    [response]
  end
end
