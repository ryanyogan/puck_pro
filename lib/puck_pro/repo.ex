defmodule PuckPro.Repo do
  use Ecto.Repo,
    otp_app: :puck_pro,
    adapter: Ecto.Adapters.SQLite3
end
