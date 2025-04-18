defmodule OpenFeature.Provider.Flagd.HTTP do
  @moduledoc """
  OpenFeature provider for flagd that communicates with a `flagd` instance over HTTP.

  This is a remote flagd provider that uses the HTTP evaluation API (JSON) to resolve flag values.
  """
  @moduledoc since: "0.1.0"

  require Logger

  @behaviour OpenFeature.Provider

  alias OpenFeature.Provider.Flagd.Reason
  alias OpenFeature.ResolutionDetails

  defstruct name: "FlagdHTTP",
            scheme: "http",
            host: "localhost",
            port: 8013,
            domain: nil,
            hooks: [],
            state: :not_ready,
            req: nil,
            req_opts: []

  @typedoc "HTTP provider for flagd"
  @type t() :: %__MODULE__{
          name: String.t(),
          scheme: String.t(),
          host: String.t(),
          port: pos_integer(),
          domain: String.t() | nil,
          hooks: [OpenFeature.Hook.t()],
          state: :not_ready | :ready,
          req: Req.Request.t() | nil,
          req_opts: keyword()
        }

  @config_opts [:scheme, :host, :port, :name, :domain, :hooks, :req_opts]

  @doc """
  Creates a new flagd HTTP provider.

  ## Options

    * `:scheme` - The URL scheme (default: `"http"`)
    * `:host` - The hostname or IP address of the flagd instance (default: `"localhost"`)
    * `:port` - The port number (default: `8013`)
    * `:name` - (optional) Custom name for the provider (default: `"FlagdHTTP"`)
    * `:domain` - (optional) Domain name to differentiate between providers
    * `:hooks` - (optional) A list of OpenFeature hooks (%OpenFeature.Hook{})
    * `:req_opts` - (optional) Keyword list passed to `Req.new/1`

  ## Examples

  ```elixir
  # Simple usage with defaults
  provider = OpenFeature.Provider.Flagd.HTTP.new()

  # With custom options
  provider = OpenFeature.Provider.Flagd.HTTP.new(port: 8013, domain: "my-service")

  # With HTTPS
  provider = OpenFeature.Provider.Flagd.HTTP.new(scheme: "https", host: "flagd.example.com")
  ```
  """
  @doc since: "0.1.0"
  @spec new(opts :: Keyword.t()) :: t()
  def new(opts \\ []) do
    filtered_opts = Keyword.take(opts, @config_opts)
    struct(__MODULE__, filtered_opts)
  end

  @impl true
  @spec initialize(provider :: t(), domain :: any(), context :: any()) ::
          {:ok, t()} | {:error, :provider_not_ready}
  def initialize(%__MODULE__{req: nil, req_opts: req_opts} = provider, domain, _context) do
    req = build_req(provider, req_opts)
    {:ok, %{provider | req: req, domain: domain, state: :ready}}
  rescue
    e ->
      Logger.error("Failed to initialize HTTP provider: #{inspect(e)}")
      {:error, :provider_not_ready}
  end

  @impl true
  def initialize(%__MODULE__{} = provider, domain, _context) do
    {:ok, %{provider | domain: domain, state: :ready}}
  end

  @impl true
  @spec shutdown(any()) :: :ok
  def shutdown(_), do: :ok

  @impl true
  @spec resolve_boolean_value(
          provider :: t(),
          key :: String.t(),
          default :: boolean,
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_boolean_value(provider, key, _default, context) do
    request(provider, key, context, "ResolveBoolean")
  end

  @impl true
  @spec resolve_string_value(
          provider :: t(),
          key :: String.t(),
          default :: String.t(),
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_string_value(provider, key, _default, context) do
    request(provider, key, context, "ResolveString")
  end

  @impl true
  @spec resolve_number_value(
          provider :: t(),
          key :: String.t(),
          default :: number,
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_number_value(provider, key, _default, context) do
    request(provider, key, context, "ResolveNumber")
  end

  @impl true
  @spec resolve_map_value(
          provider :: t(),
          key :: String.t(),
          default :: map,
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_map_value(provider, key, _default, context) do
    request(provider, key, context, "ResolveObject")
  end

  defp build_req(%__MODULE__{scheme: scheme, host: host, port: port}, req_opts) do
    Req.new(
      Keyword.merge(
        [
          base_url: "#{scheme}://#{host}:#{port}",
          method: :post,
          headers: [{"Content-Type", "application/json"}]
        ],
        req_opts
      )
    )
  end

  defp request(provider, key, context, method_name) do
    case encode_payload(key, context) do
      {:ok, json_body} ->
        do_request(provider, method_name, json_body)

      {:error, error} ->
        {:error, :unexpected_error, error}
    end
  end

  defp encode_payload(key, context) do
    payload = %{"flagKey" => key, "context" => context}
    Jason.encode(payload)
  end

  defp do_request(provider, method_name, json_body) do
    service = "flagd.evaluation.v1.Service"
    method_path = "/#{service}/#{method_name}"

    provider.req
    |> Req.merge(url: method_path, body: json_body)
    |> Req.Request.run_request()
    |> parse_result()
  rescue
    e -> {:error, :unexpected_error, e}
  end

  defp parse_result({_req, %Req.Response{status: 200, body: body}}) do
    {:ok,
     %ResolutionDetails{
       value: body["value"],
       variant: body["variant"],
       reason: Reason.to_reason(body["reason"]),
       flag_metadata: body["flagMetadata"]
     }}
  end

  defp parse_result({_req, %Req.Response{body: body}}) do
    message = body["message"] || "Unknown error"
    code = body["code"] || "general"

    case code do
      "not_found" -> {:error, :flag_not_found}
      _ -> {:error, :unexpected_error, %RuntimeError{message: "[#{code}] #{message}"}}
    end
  end
end
