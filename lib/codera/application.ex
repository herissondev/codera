defmodule Codera.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CoderaWeb.Telemetry,
      Codera.Repo,
      {DNSCluster, query: Application.get_env(:codera, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Codera.PubSub},
      # Thread management
      {Registry, keys: :unique, name: Codera.AI.ThreadRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Codera.AI.ThreadSupervisor},
      # Start a worker by calling: Codera.Worker.start_link(arg)
      # {Codera.Worker, arg},
      # Start to serve requests, typically the last entry
      CoderaWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Codera.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CoderaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
