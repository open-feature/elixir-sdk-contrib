defmodule OpenFeature.Provider.Flagd.GRPCTest do
  use ExUnit.Case
  use Mimic

  import ExUnit.CaptureLog

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Flagd.Evaluation.V1.ResolveBooleanResponse
  alias Flagd.Evaluation.V1.ResolveFloatResponse
  alias Flagd.Evaluation.V1.ResolveIntResponse
  alias Flagd.Evaluation.V1.ResolveObjectResponse
  alias Flagd.Evaluation.V1.ResolveStringResponse
  alias Flagd.Evaluation.V1.Service.Stub
  alias OpenFeature.Provider.Flagd.GRPC, as: FlagdGRPC
  alias Protobuf.JSON.Encode

  setup do
    provider = FlagdGRPC.new(port: 8013)
    {:ok, provider: provider}
  end

  test "new/1 filters out non-config options" do
    provider =
      FlagdGRPC.new(
        port: 9000,
        # This should be filtered out
        state: :ready,
        # This should be filtered out
        channel: :something
      )

    assert provider.port == 9000
    # Default value preserved
    assert provider.state == :not_ready
    # Default value preserved
    assert provider.channel == nil
  end

  test "successfully initializes with valid options" do
    provider =
      FlagdGRPC.new(
        host: "example.com",
        port: 9000
      )

    expect(GRPC.Stub, :connect, fn target, opts ->
      assert target == "example.com:9000"
      assert opts == []
      {:ok, :test_channel}
    end)

    {:ok, initialized} = FlagdGRPC.initialize(provider, "override-domain", %{})

    assert initialized.channel == :test_channel
    assert initialized.domain == "override-domain"
    assert initialized.state == :ready
  end

  test "handles initialization failure" do
    provider = FlagdGRPC.new()

    expect(GRPC.Stub, :connect, fn _target, _opts ->
      {:error, "connection refused"}
    end)

    log =
      capture_log(fn ->
        assert {:error, :provider_not_ready} = FlagdGRPC.initialize(provider, "test", %{})
      end)

    assert log =~ "Failed to initialize GRPC provider"
  end

  test "successfully resolves a boolean flag", %{provider: provider} do
    expect(GRPC.Stub, :connect, fn _target, _opts -> {:ok, :channel} end)

    expect(Stub, :resolve_boolean, fn :channel, req ->
      assert req.flag_key == "bool-flag"
      {:ok, %ResolveBooleanResponse{value: true, variant: "on", reason: "STATIC"}}
    end)

    {:ok, provider} = FlagdGRPC.initialize(provider, "test", %{})

    assert {:ok, result} =
             FlagdGRPC.resolve_boolean_value(provider, "bool-flag", false, %{})

    assert result.value == true
    assert result.variant == "on"
    assert result.reason == :static
  end

  test "returns error when flag is not found", %{provider: provider} do
    expect(GRPC.Stub, :connect, fn _target, _opts -> {:ok, :channel} end)

    expect(Stub, :resolve_boolean, fn :channel, _ ->
      {:error, :not_found}
    end)

    {:ok, provider} = FlagdGRPC.initialize(provider, "test", %{})

    assert {:error, :flag_not_found} =
             FlagdGRPC.resolve_boolean_value(provider, "missing-flag", false, %{})
  end

  test "successfully resolves string flag", %{provider: provider} do
    expect(GRPC.Stub, :connect, fn _target, _opts -> {:ok, :channel} end)

    expect(Stub, :resolve_string, fn :channel, req ->
      assert req.flag_key == "color"

      {:ok,
       %ResolveStringResponse{
         value: "#FF00FF",
         variant: "magenta",
         reason: "STATIC"
       }}
    end)

    {:ok, provider} = FlagdGRPC.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdGRPC.resolve_string_value(provider, "color", "red", %{})

    assert result.value == "#FF00FF"
    assert result.variant == "magenta"
    assert result.reason == :static
  end

  test "successfully resolves integer flag", %{provider: provider} do
    expect(GRPC.Stub, :connect, fn _target, _opts -> {:ok, :channel} end)

    expect(Stub, :resolve_int, fn :channel, req ->
      assert req.flag_key == "count"

      {:ok,
       %ResolveIntResponse{
         value: 42,
         variant: "answer",
         reason: "STATIC"
       }}
    end)

    {:ok, provider} = FlagdGRPC.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdGRPC.resolve_number_value(provider, "count", 0, %{})

    assert result.value == 42
    assert result.variant == "answer"
    assert result.reason == :static
  end

  test "successfully resolves float flag", %{provider: provider} do
    expect(GRPC.Stub, :connect, fn _target, _opts -> {:ok, :channel} end)

    expect(Stub, :resolve_float, fn :channel, req ->
      assert req.flag_key == "pi"

      {:ok,
       %ResolveFloatResponse{
         value: 3.14,
         variant: "pi",
         reason: "STATIC"
       }}
    end)

    {:ok, provider} = FlagdGRPC.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdGRPC.resolve_number_value(provider, "pi", 1.0, %{})

    assert result.value == 3.14
    assert result.variant == "pi"
    assert result.reason == :static
  end

  test "successfully resolves map flag", %{provider: provider} do
    map_value = %{"enabled" => true, "limit" => 10}
    struct_mock = %Google.Protobuf.Struct{}

    expect(GRPC.Stub, :connect, fn _target, _opts -> {:ok, :channel} end)

    expect(Stub, :resolve_object, fn :channel, req ->
      assert req.flag_key == "config"

      {:ok,
       %ResolveObjectResponse{
         value: struct_mock,
         variant: "default",
         reason: "STATIC"
       }}
    end)

    expect(Encode, :encodable, fn ^struct_mock, nil -> map_value end)

    {:ok, provider} = FlagdGRPC.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdGRPC.resolve_map_value(provider, "config", %{}, %{})

    assert result.value["enabled"] == true
    assert result.value["limit"] == 10
    assert result.variant == "default"
    assert result.reason == :static
  end

  test "handles response with nil reason and metadata", %{provider: provider} do
    expect(GRPC.Stub, :connect, fn _target, _opts -> {:ok, :channel} end)

    expect(Stub, :resolve_string, fn :channel, _ ->
      {:ok,
       %ResolveStringResponse{
         value: "some_value",
         variant: "default"
         # No reason or metadata provided
       }}
    end)

    {:ok, provider} = FlagdGRPC.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdGRPC.resolve_string_value(provider, "some-flag", "fallback", %{})

    assert result.reason == :unknown
    assert result.flag_metadata == nil
  end

  test "converts context to protobuf struct", %{provider: provider} do
    expect(GRPC.Stub, :connect, fn _target, _opts -> {:ok, :channel} end)

    expect(Stub, :resolve_boolean, fn :channel, req ->
      # Check that context was converted to a proper protobuf struct
      assert %Google.Protobuf.Struct{} = req.context

      {:ok, %ResolveBooleanResponse{value: true}}
    end)

    {:ok, provider} = FlagdGRPC.initialize(provider, "test", %{})

    test_context = %{"env" => "prod", "user" => "alice"}
    assert {:ok, _} = FlagdGRPC.resolve_boolean_value(provider, "test-flag", false, test_context)
  end

  test "properly handles TLS configuration with cacertfile" do
    provider =
      FlagdGRPC.new(
        host: "secure.example.com",
        tls: true,
        cacertfile: "/path/to/cert.pem"
      )

    expect(GRPC.Credential, :new, fn opts ->
      assert Keyword.get(opts, :ssl)[:cacertfile] == "/path/to/cert.pem"
      :tls_credential
    end)

    expect(GRPC.Stub, :connect, fn target, opts ->
      assert target == "secure.example.com:8013"
      assert Keyword.get(opts, :cred) == :tls_credential
      {:ok, :secure_channel}
    end)

    {:ok, initialized} = FlagdGRPC.initialize(provider, "test", %{})
    assert initialized.channel == :secure_channel
  end
end
