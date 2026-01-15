# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :puck_pro,
  ecto_repos: [PuckPro.Repo],
  generators: [timestamp_type: :utc_datetime],
  http_adapter: PuckPro.HTTP.ReqAdapter,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  # Cloudflare R2 defaults (configured in runtime.exs)
  r2_bucket: nil,
  r2_public_url: nil

# Cloudflare R2 (S3-compatible storage)
config :ex_aws,
  json_codec: Jason,
  http_client: ExAws.Request.Hackney

# Configures the endpoint
config :puck_pro, PuckProWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PuckProWeb.ErrorHTML, json: PuckProWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PuckPro.PubSub,
  live_view: [signing_salt: "tbt8xvfj"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  puck_pro: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  puck_pro: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
