defmodule CymApp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CymAppWeb.Telemetry,
      # CymApp.Repo,
      {DNSCluster, query: Application.get_env(:cym_app, :dns_cluster_query) || :ignore},

      # Start the Finch HTTP client for sending emails
      # {Finch, name: CymApp.Finch},
      # Start a worker by calling: CymApp.Worker.start_link(arg)
      # {CymApp.Worker, arg},
      # Start to serve requests, typically the last entry
      {Phoenix.PubSub, name: CymApp.PubSub},
      CymAppWeb.Endpoint,
      # Start the OSC listener
      {CymApp.OSCListener, []},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CymApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CymAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
