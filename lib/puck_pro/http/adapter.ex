defmodule PuckPro.HTTP.Adapter do
  @moduledoc """
  Behaviour for HTTP adapters - allows swapping implementations for testing.
  """

  @type headers :: [{String.t(), String.t()}]
  @type body :: String.t() | map()
  @type response :: {:ok, map()} | {:error, term()}

  @doc "Make a GET request and return JSON"
  @callback get_json(url :: String.t()) :: response()
  @callback get_json(url :: String.t(), headers :: headers()) :: response()

  @doc "Make a POST request with JSON body"
  @callback post_json(url :: String.t(), body :: body()) :: response()
  @callback post_json(url :: String.t(), body :: body(), headers :: headers()) :: response()

  @doc "Stream a POST request (for AI streaming responses)"
  @callback stream_post(url :: String.t(), body :: body(), headers :: headers(), callback :: function()) :: response()

  @doc "Get the configured adapter"
  def adapter do
    Application.get_env(:puck_pro, :http_adapter, PuckPro.HTTP.ReqAdapter)
  end
end
