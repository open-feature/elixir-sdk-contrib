defmodule OpenFeature.Provider.OFREPTest do
  use ExUnit.Case
  use Mimic

  import ExUnit.CaptureLog

  setup :set_mimic_global
  setup :verify_on_exit!

  alias OpenFeature.Provider.OFREP

  setup do
    provider = OFREP.new(base_url: "http://localhost:8016")
    {:ok, provider: provider}
  end

  test "new/1 filters out non-config options" do
    provider =
      OFREP.new(
        base_url: "http://example.com:9000",
        # This should be filtered out
        state: :ready,
        # This should be filtered out
        req: :something
      )

    assert provider.base_url == "http://example.com:9000"
    # Default value preserved
    assert provider.state == :not_ready
    # Default value preserved
    assert provider.req == nil
  end

  test "new/1 validates base_url" do
    assert_raise ArgumentError, ~r/Invalid base URL/, fn ->
      OFREP.new(base_url: "invalid")
    end
  end

  test "successfully initializes with valid options" do
    provider =
      OFREP.new(
        base_url: "https://example.com:9000",
        domain: "test-domain"
      )

    expect(Req, :new, fn opts ->
      assert Keyword.get(opts, :base_url) == "https://example.com:9000"
      assert Keyword.get(opts, :method) == :post
      %Req.Request{}
    end)

    {:ok, initialized} = OFREP.initialize(provider, "override-domain", %{})

    assert initialized.domain == "override-domain"
    assert initialized.state == :ready
    assert %Req.Request{} = initialized.req
  end

  test "uses user-provided req_opts and overrides defaults" do
    custom_headers = [{"X-Custom", "Value"}]

    provider =
      OFREP.new(
        base_url: "http://example.com:9000",
        req_opts: [headers: custom_headers]
      )

    expect(Req, :new, fn opts ->
      headers = Keyword.fetch!(opts, :headers)
      # It should NOT include the default "Content-Type" since it was overridden
      refute {"Content-Type", "application/json"} in headers
      assert {"X-Custom", "Value"} in headers
      %Req.Request{}
    end)

    {:ok, _} = OFREP.initialize(provider, "test", %{})
  end

  test "handles initialization failure", %{provider: provider} do
    expect(Req, :new, fn _opts ->
      raise "Failed to create request"
    end)

    log =
      capture_log(fn ->
        assert {:error, :provider_not_ready} = OFREP.initialize(provider, "test", %{})
      end)

    assert log =~ "Failed to initialize OFREP provider"
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

    {:ok, provider} = OFREP.initialize(provider, "test-domain", %{})
    assert {:ok, result} = OFREP.resolve_boolean_value(provider, "bool-flag", false, %{})

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

    {:ok, provider} = OFREP.initialize(provider, "test", %{})

    {:ok, resolution_details} =
      OFREP.resolve_boolean_value(provider, "missing", false, %{})

    assert %OpenFeature.ResolutionDetails{
             reason: :error,
             value: false,
             error_code: :flag_not_found,
             error_message: "Flag not found",
             variant: nil,
             flag_metadata: nil
           } = resolution_details
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

    {:ok, provider} = OFREP.initialize(provider, "test", %{})

    assert {:error, :unexpected_error, %RuntimeError{message: "[500] Boom"}} =
             OFREP.resolve_boolean_value(provider, "some-flag", false, %{})
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

    {:ok, provider} = OFREP.initialize(provider, "test", %{})
    assert {:ok, result} = OFREP.resolve_string_value(provider, "color", "red", %{})

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

    {:ok, provider} = OFREP.initialize(provider, "test", %{})
    assert {:ok, result} = OFREP.resolve_number_value(provider, "pi", 0.0, %{})
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

    {:ok, provider} = OFREP.initialize(provider, "test", %{})
    assert {:ok, result} = OFREP.resolve_number_value(provider, "number-flag", 0, %{})
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

    {:ok, provider} = OFREP.initialize(provider, "test", %{})
    assert {:ok, result} = OFREP.resolve_map_value(provider, "config", %{}, %{})
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
          }
        }
      }
    end)

    {:ok, provider} = OFREP.initialize(provider, "test", %{})
    assert {:ok, result} = OFREP.resolve_string_value(provider, "some-flag", "fallback", %{})
    assert result.reason == :unknown
    assert result.flag_metadata == nil
  end

  test "handles invalid JSON body", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      raise Jason.DecodeError, data: "<html></html>", position: 0, token: "<"
    end)

    {:ok, provider} = OFREP.initialize(provider, "test", %{})

    assert {:error, :unexpected_error, %Jason.DecodeError{}} =
             OFREP.resolve_string_value(provider, "some-flag", "default", %{})
  end

  test "handles network failure (e.g. timeout or SSL error)", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      raise RuntimeError, message: "connection refused"
    end)

    {:ok, provider} = OFREP.initialize(provider, "test", %{})

    assert {:error, :unexpected_error, %RuntimeError{message: "connection refused"}} =
             OFREP.resolve_boolean_value(provider, "network-flag", false, %{})
  end

  test "handles type mismatch", %{provider: provider} do
    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 200,
          body: %{
            "value" => "not a boolean",
            "variant" => "default",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, provider} = OFREP.initialize(provider, "test", %{})

    {:ok, resolution_details} =
      OFREP.resolve_boolean_value(provider, "type-mismatch", false, %{})

    assert %OpenFeature.ResolutionDetails{
             reason: :error,
             value: false,
             error_code: :type_mismatch,
             error_message: "Type mismatch: expected :boolean, got :string",
             variant: nil,
             flag_metadata: nil
           } = resolution_details
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
            "reason" => "targeting_match"
          }
        }
      }
    end)

    {:ok, provider} = OFREP.initialize(provider, "test", %{})
    OpenFeature.set_provider(provider)

    # Simulate global + client context merging
    OpenFeature.set_global_context(%{"env" => "prod"})
    client = OpenFeature.get_client() |> OpenFeature.Client.set_context(%{"user" => "alice"})

    details = OpenFeature.Client.get_boolean_details(client, "merge-flag", false)

    assert %OpenFeature.EvaluationDetails{
             value: true,
             key: "merge-flag",
             reason: :targeting_match,
             variant: "v1",
             error_code: nil,
             error_message: nil
           } = details
  end

  test "formats request URL correctly", %{provider: provider} do
    flag_key = "test-flag"

    expect(Req.Request, :run_request, fn req ->
      assert req.url.path == "/ofrep/v1/evaluate/flags/#{flag_key}"

      {
        req,
        %Req.Response{
          status: 200,
          body: %{
            "value" => true,
            "variant" => "default",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, provider} = OFREP.initialize(provider, "test", %{})
    assert {:ok, _} = OFREP.resolve_boolean_value(provider, flag_key, false, %{})
  end

  test "initial 429 response updates provider with retry-after time", %{provider: provider} do
    now = DateTime.utc_now()
    retry_after = DateTime.add(now, 30, :second)

    {:ok, provider} = OFREP.initialize(provider, "test-domain", %{})
    {:ok, _} = OpenFeature.set_provider("test-domain", provider)

    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 429,
          body: %{"message" => "Rate limit exceeded"},
          headers: [{"retry-after", DateTime.to_iso8601(retry_after)}]
        }
      }
    end)

    log =
      capture_log(fn ->
        {:ok, result} = OFREP.resolve_boolean_value(provider, "rate-limited-flag", false, %{})

        assert result.value == false
        assert result.error_code == :general
        assert result.error_message =~ "Rate limited"
        assert result.reason == :error
      end)

    assert log =~ "Rate limited by OFREP service"

    updated_provider = OpenFeature.get_provider("test-domain")

    assert updated_provider.retry_after != nil
    assert DateTime.compare(updated_provider.retry_after, now) == :gt
  end

  test "requests during rate-limit cooldown period return error without HTTP request", %{
    provider: provider
  } do
    now = DateTime.utc_now()
    retry_after = DateTime.add(now, 30, :second)

    {:ok, provider} = OFREP.initialize(provider, "test-domain", %{})

    rate_limited_provider = %{provider | retry_after: retry_after}
    {:ok, _} = OpenFeature.set_provider("test-domain", rate_limited_provider)

    log =
      capture_log(fn ->
        {:ok, result} =
          OFREP.resolve_boolean_value(rate_limited_provider, "another-flag", false, %{})

        assert result.value == false
        assert result.error_code == :general
        assert result.error_message =~ "Rate limited"
        assert result.reason == :error
      end)

    assert log =~ "OFREP evaluation paused due to rate limiting until"
  end

  test "provider resumes normal operation after rate-limit cooldown expires", %{
    provider: provider
  } do
    now = DateTime.utc_now()
    {:ok, provider} = OFREP.initialize(provider, "test-domain", %{})

    expired_retry_after = DateTime.add(now, -10, :second)
    expired_provider = %{provider | retry_after: expired_retry_after}
    {:ok, _} = OpenFeature.set_provider("test-domain", expired_provider)

    expect(Req.Request, :run_request, fn _req ->
      {
        %Req.Request{},
        %Req.Response{
          status: 200,
          body: %{
            "value" => true,
            "variant" => "default",
            "reason" => "STATIC"
          }
        }
      }
    end)

    {:ok, result} =
      OFREP.resolve_boolean_value(expired_provider, "post-rate-limit-flag", false, %{})

    assert result.value == true
    assert result.error_code == nil
    assert result.error_message == nil
    assert result.reason == :static
    assert result.variant == "default"

    final_provider = OpenFeature.get_provider("test-domain")
    assert final_provider.retry_after == nil
  end
end
