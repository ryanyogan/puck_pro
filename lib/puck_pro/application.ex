defmodule PuckPro.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PuckProWeb.Telemetry,
      PuckPro.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:puck_pro, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:puck_pro, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PuckPro.PubSub},
      # Task supervisor for async AI operations
      {Task.Supervisor, name: PuckPro.TaskSupervisor},
      # Registry for shot tracker processes (one per session)
      {Registry, keys: :unique, name: PuckPro.ShotTrackerRegistry},
      # Start to serve requests, typically the last entry
      PuckProWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PuckPro.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PuckProWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
