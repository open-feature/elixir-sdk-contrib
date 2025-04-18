defmodule OpenFeature.Provider.Flagd.GRPC.EventStreamTest do
  use ExUnit.Case
  use Mimic

  import ExUnit.CaptureLog

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Flagd.Evaluation.V1.EventStreamRequest
  alias Flagd.Evaluation.V1.EventStreamResponse
  alias Flagd.Evaluation.V1.Service.Stub
  alias OpenFeature.EventEmitter
  alias OpenFeature.Provider.Flagd.GRPC, as: FlagdGRPC
  alias Protobuf.JSON.Decode

  defp json_struct(map) do
    Decode.from_json_data(map, Google.Protobuf.Struct)
  end

  setup do
    expect(GRPC.Stub, :connect, fn _target, _opts -> {:ok, :channel} end)

    provider = FlagdGRPC.new(port: 8013, domain: "test-domain")

    {:ok, _} = OpenFeature.set_provider("test-domain", provider)
    client = OpenFeature.get_client("test-domain")

    {:ok, client: client, provider: provider}
  end

  test "starts stream and emits :ready", %{client: client} do
    test_pid = self()

    msg = %EventStreamResponse{type: "provider_ready"}

    expect(Stub, :event_stream, fn _channel, %EventStreamRequest{} ->
      {:ok, [{:ok, msg}]}
    end)

    expect(EventEmitter, :emit, fn "test-domain", :ready, %{} ->
      send(test_pid, :ready_emitted)
      :ok
    end)

    {:ok, _pid} = FlagdGRPC.EventStream.start_link(client)

    assert_receive :ready_emitted, 100
  end

  test "logs warning on stream failure", %{client: client} do
    expect(Stub, :event_stream, fn _channel, _req -> {:error, :unavailable} end)

    log =
      capture_log(fn ->
        {:ok, _pid} = FlagdGRPC.EventStream.start_link(client)
        Process.sleep(20)
      end)

    assert log =~ "Event stream failed to start: :unavailable"
  end

  test "emits :configuration_changed", %{client: client} do
    test_pid = self()

    msg = %EventStreamResponse{
      type: "configuration_change",
      data:
        json_struct(%{
          "flags" => %{
            "test-flag" => %{"type" => "update", "source" => "core"}
          }
        })
    }

    expect(Stub, :event_stream, fn _channel, _req -> {:ok, [{:ok, msg}]} end)

    expect(EventEmitter, :emit, fn "test-domain",
                                   :configuration_changed,
                                   %{
                                     flag_key: "test-flag",
                                     type: "update",
                                     source: "core"
                                   } ->
      send(test_pid, :config_changed_emitted)
      :ok
    end)

    {:ok, _pid} = FlagdGRPC.EventStream.start_link(client)

    assert_receive :config_changed_emitted, 100
  end

  test "logs warning if started with non-GRPC client" do
    bad_client = %OpenFeature.Client{
      provider: %OpenFeature.Provider.NoOp{},
      domain: "test-domain"
    }

    log =
      capture_log(fn ->
        assert :error = FlagdGRPC.EventStream.start_link(bad_client)
      end)

    assert log =~ "doesn't use the gRPC provider"
  end
end
