defmodule OpenFeature.Provider.Flagd.HTTPTest do
  use ExUnit.Case
  use Mimic

  import ExUnit.CaptureLog

  setup :set_mimic_global
  setup :verify_on_exit!

  alias OpenFeature.Provider.Flagd.HTTP, as: FlagdHTTP

  setup do
    provider = FlagdHTTP.new(port: 8015)
    {:ok, provider: provider}
  end

  test "new/1 filters out non-config options" do
    provider =
      FlagdHTTP.new(
        port: 9000,
        # This should be filtered out
        state: :ready,
        # This should be filtered out
        req: :something
      )

    assert provider.port == 9000
    # Default value preserved
    assert provider.state == :not_ready
    # Default value preserved
    assert provider.req == nil
  end

  test "successfully initializes with valid options" do
    provider =
      FlagdHTTP.new(
        scheme: "https",
        host: "example.com",
        port: 9000,
        domain: "test-domain"
      )

    expect(Req, :new, fn opts ->
      assert Keyword.get(opts, :base_url) == "https://example.com:9000"
      assert Keyword.get(opts, :method) == :post
      %Req.Request{}
    end)

    {:ok, initialized} = FlagdHTTP.initialize(provider, "override-domain", %{})

    assert initialized.domain == "override-domain"
    assert initialized.state == :ready
    assert %Req.Request{} = initialized.req
  end

  test "handles initialization failure" do
    provider = FlagdHTTP.new()

    expect(Req, :new, fn _opts ->
      raise "Failed to create request"
    end)

    log =
      capture_log(fn ->
        assert {:error, :provider_not_ready} = FlagdHTTP.initialize(provider, "test", %{})
      end)

    assert log =~ "Failed to initialize HTTP provider"
  end

  test "uses user-provided req_opts and overrides defaults" do
    custom_headers = [{"X-Custom", "Value"}]

    provider =
      FlagdHTTP.new(
        host: "example.com",
        req_opts: [headers: custom_headers]
      )

    expect(Req, :new, fn opts ->
      headers = Keyword.fetch!(opts, :headers)
      # It should NOT include the default "Content-Type" since it was overridden
      refute {"Content-Type", "application/json"} in headers
      assert {"X-Custom", "Value"} in headers
      %Req.Request{}
    end)

    {:ok, _} = FlagdHTTP.initialize(provider, "test", %{})
  end

  test "successfully resolves boolean flag", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 200,
          body: %{
            "value" => true,
            "variant" => "on",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test-domain", %{})
    assert {:ok, result} = FlagdHTTP.resolve_boolean_value(provider, "bool-flag", false, %{})

    assert result.value == true
    assert result.reason == :static
    assert result.variant == "on"
  end

  test "handles not_found flag error", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 404,
          body: %{"code" => "not_found", "message" => "flag not found"}
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})

    assert {:error, :flag_not_found} =
             FlagdHTTP.resolve_boolean_value(provider, "missing", false, %{})
  end

  test "handles unexpected error with message", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 500,
          body: %{"code" => "server_error", "message" => "Boom"}
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})

    assert {:error, :unexpected_error, %RuntimeError{message: "[server_error] Boom"}} =
             FlagdHTTP.resolve_boolean_value(provider, "some-flag", false, %{})
  end

  test "successfully resolves string flag", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 200,
          body: %{
            "value" => "#FF00FF",
            "variant" => "magenta",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdHTTP.resolve_string_value(provider, "color", "red", %{})

    assert result.value == "#FF00FF"
    assert result.variant == "magenta"
    assert result.reason == :static
  end

  test "successfully resolves number flag (float)", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 200,
          body: %{
            "value" => 3.14,
            "variant" => "pi",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdHTTP.resolve_number_value(provider, "pi", 0.0, %{})
    assert result.value == 3.14
    assert result.variant == "pi"
  end

  test "successfully resolves number flag (int)", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 200,
          body: %{
            "value" => 42,
            "variant" => "default",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdHTTP.resolve_number_value(provider, "number-flag", 0, %{})
    assert result.value == 42
    assert result.variant == "default"
  end

  test "successfully resolves map flag", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 200,
          body: %{
            "value" => %{"enabled" => true, "limit" => 10},
            "variant" => "default",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdHTTP.resolve_map_value(provider, "config", %{}, %{})
    assert result.value["enabled"] == true
    assert result.value["limit"] == 10
  end

  test "handles response with nil reason and metadata", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 200,
          body: %{
            "value" => "some_value",
            "variant" => "default"
            # no reason or flagMetadata provided
          }
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})
    assert {:ok, result} = FlagdHTTP.resolve_string_value(provider, "some-flag", "fallback", %{})
    assert result.reason == :unknown
    assert result.flag_metadata == nil
  end

  test "handles invalid JSON body gracefully", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      raise Jason.DecodeError, data: "<html></html>", position: 0, token: "<"
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})

    assert {:error, :unexpected_error, %Jason.DecodeError{}} =
             FlagdHTTP.resolve_string_value(provider, "some-flag", "default", %{})
  end

  test "sends merged context from client and call", %{provider: provider} do
    expected_context = %{"env" => "prod", "user" => "alice"}

    expect(Req.Request, :run_request, fn req ->
      {:ok, payload} = Jason.decode(req.body)

      # Ensure merged context was sent
      assert payload["context"] == expected_context

      {
        req,
        %Req.Response{
          status: 200,
          body: %{
            "value" => true,
            "variant" => "v1",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})
    OpenFeature.set_provider(provider)

    # Simulate global + client context merging
    OpenFeature.set_global_context(%{"env" => "prod"})
    client = OpenFeature.get_client() |> OpenFeature.Client.set_context(%{"user" => "alice"})

    details = OpenFeature.Client.get_boolean_details(client, "merge-flag", false)

    assert %OpenFeature.EvaluationDetails{
             value: true,
             key: "merge-flag",
             reason: :static,
             variant: "v1",
             error_code: nil,
             error_message: nil
           } = details
  end

  test "handles network failure (e.g. timeout or SSL error)", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      raise RuntimeError, message: "connection refused"
    end)

    {:ok, provider} = FlagdHTTP.initialize(provider, "test", %{})

    assert {:error, :unexpected_error, %RuntimeError{message: "connection refused"}} =
             FlagdHTTP.resolve_boolean_value(provider, "network-flag", false, %{})
  end
end
