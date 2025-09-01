defmodule OpenFeature.Provider.Flagd.GRPC.EventStream do
  @moduledoc """
  Handles gRPC event streaming for the Flagd provider.

  This module listens for lifecycle events from `flagd` (such as `provider_ready` and
  `configuration_change`) and emits them via `OpenFeature.EventEmitter`.

  This module is a `GenServer` and should be added to your supervision tree.

  ## Static Supervision Example

      # In your Application module
      client = OpenFeature.get_client("gRPC")

      children = [
        {OpenFeature.Provider.Flagd.GRPC.EventStream, client}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  ## Dynamic Supervision Example

      # In your Application module
      children = [
        {DynamicSupervisor, name: MyApp.EventStreamSupervisor, strategy: :one_for_one}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

      # Later at runtime
      client = OpenFeature.get_client("gRPC")

      DynamicSupervisor.start_child(MyApp.EventStreamSupervisor, {OpenFeature.Provider.Flagd.GRPC.EventStream, client})
  """
  @moduledoc since: "0.1.0"

  use GenServer
  require Logger

  alias Flagd.Evaluation.V1.EventStreamRequest
  alias Flagd.Evaluation.V1.Service.Stub
  alias OpenFeature.Client
  alias OpenFeature.EventEmitter
  alias OpenFeature.Provider.Flagd.GRPC, as: FlagdGRPC
  alias Protobuf.JSON.Encode

  @spec start_link(Client.t()) :: GenServer.on_start()
  def start_link(%Client{provider: %FlagdGRPC{channel: %GRPC.Channel{} = channel, domain: domain}}) do
    GenServer.start_link(__MODULE__, %{channel: channel, domain: domain})
  end

  def start_link(%Client{provider: %FlagdGRPC{} = provider}) do
    Logger.error(
      "EventStream.start_link/1 requires an initialized gRPC provider with a valid channel. Got: #{inspect(provider)}"
    )

    :error
  end

  def start_link(%Client{provider: provider}) do
    Logger.error("EventStream.start_link/1 called with client that doesn't use the gRPC provider: #{inspect(provider)}")

    :error
  end

  @spec child_spec(Client.t()) :: Supervisor.child_spec()
  def child_spec(%Client{provider: %FlagdGRPC{domain: domain}} = client) do
    %{
      id: {__MODULE__, domain},
      start: {__MODULE__, :start_link, [client]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  @impl true
  def init(state) do
    Logger.debug("Starting gRPC event stream for domain: #{state.domain}")
    {:ok, state, {:continue, :start_stream}}
  end

  @impl true
  def handle_continue(:start_stream, %{channel: channel, domain: domain} = state) do
    listen(channel, domain)
    {:noreply, state}
  end

  defp listen(channel, domain) do
    Logger.debug("Listening to flagd event stream on domain: #{domain}")

    case Stub.event_stream(channel, %EventStreamRequest{}) do
      {:ok, stream} ->
        for event <- stream do
          handle_event(event, domain)
        end

      {:error, err} ->
        Logger.warning("Event stream failed to start: #{inspect(err)}")
    end
  end

  defp handle_event({:ok, msg}, domain) do
    case Encode.encodable(msg, nil) do
      %{"type" => "keep_alive"} ->
        :ok

      %{"type" => "provider_ready"} ->
        EventEmitter.emit(domain, :ready, %{})

      %{"type" => "configuration_change", "data" => %{"flags" => flags}} ->
        Enum.each(flags, fn {flag, attrs} ->
          EventEmitter.emit(domain, :configuration_changed, %{
            flag_key: flag,
            type: attrs["type"],
            source: attrs["source"]
          })
        end)

      %{"type" => "provider_shutdown"} ->
        Logger.info("Received provider_shutdown event from flagd")

      other ->
        Logger.debug("Unknown or unsupported event: #{inspect(other)}")
    end
  end

  defp handle_event({:error, error}, _domain) do
    Logger.warning("Event stream error: #{inspect(error)}")
  end
end
