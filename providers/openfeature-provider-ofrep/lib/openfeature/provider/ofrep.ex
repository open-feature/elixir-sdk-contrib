defmodule OpenFeature.Provider.OFREP do
  @moduledoc """
  OpenFeature provider for the OpenFeature Remote Evaluation Protocol (OFREP).
  """

  @moduledoc since: "0.1.0"

  require Logger

  @behaviour OpenFeature.Provider

  alias OpenFeature.Provider.OFREP.Reason
  alias OpenFeature.ResolutionDetails

  defstruct name: "OFREP",
            base_url: nil,
            domain: nil,
            hooks: [],
            state: :not_ready,
            req: nil,
            req_opts: [],
            retry_after: nil

  @typedoc "OFREP provider"
  @type t() :: %__MODULE__{
          name: String.t(),
          base_url: String.t(),
          domain: String.t() | nil,
          hooks: [OpenFeature.Hook.t()],
          state: :not_ready | :ready,
          req: Req.Request.t() | nil,
          req_opts: keyword(),
          retry_after: DateTime.t() | nil
        }

  @config_opts [:base_url, :name, :domain, :hooks, :req_opts]

  @doc """
  Creates a new OFREP provider.

  ## Options

    * `:base_url` - (required) The base URL of the OFREP instance e.g. `"http://ofrep-service:8016"`
    * `:name` - (optional) Custom name for the provider (default: `"OFREP"`)
    * `:domain` - (optional) Domain name to differentiate between providers
    * `:hooks` - (optional) A list of OpenFeature hooks (%OpenFeature.Hook{})
    * `:req_opts` - (optional) Keyword list passed to `Req.new/1`

  ## Examples

  ```elixir
  provider = OpenFeature.Provider.OFREP.new(base_url: "http://ofrep-service:8016", domain: "my-service")
  ```
  """
  @doc since: "0.1.0"
  @spec new(opts :: Keyword.t()) :: t()
  def new(opts \\ []) do
    base_url = Keyword.fetch!(opts, :base_url)
    validate_base_url!(base_url)

    opts
    |> Keyword.take(@config_opts)
    |> then(&struct(__MODULE__, &1))
  end

  @impl true
  @spec initialize(provider :: t(), domain :: any(), context :: any()) ::
          {:ok, t()} | {:error, :provider_not_ready}
  def initialize(%__MODULE__{req: nil, req_opts: req_opts} = provider, domain, _context) do
    req = build_req(provider, req_opts)
    {:ok, %{provider | req: req, domain: domain, state: :ready}}
  rescue
    e ->
      Logger.error("Failed to initialize OFREP provider: #{inspect(e)}")
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
  def resolve_boolean_value(provider, key, default, context) do
    request(provider, key, default, context, :boolean)
  end

  @impl true
  @spec resolve_string_value(
          provider :: t(),
          key :: String.t(),
          default :: String.t(),
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_string_value(provider, key, default, context) do
    request(provider, key, default, context, :string)
  end

  @impl true
  @spec resolve_number_value(
          provider :: t(),
          key :: String.t(),
          default :: number,
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_number_value(provider, key, default, context) do
    request(provider, key, default, context, :number)
  end

  @impl true
  @spec resolve_map_value(
          provider :: t(),
          key :: String.t(),
          default :: map,
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_map_value(provider, key, default, context) do
    request(provider, key, default, context, :map)
  end

  @spec validate_base_url!(String.t()) :: :ok | no_return()
  defp validate_base_url!(base_url) do
    case URI.parse(base_url) do
      %{scheme: scheme, host: host, port: port}
      when scheme in ["http", "https"] and host != nil and port != nil ->
        :ok

      _ ->
        raise ArgumentError, "Invalid base URL: #{base_url}"
    end
  end

  @spec build_req(t(), keyword()) :: Req.Request.t()
  defp build_req(%__MODULE__{base_url: base_url}, req_opts) do
    Req.new(
      Keyword.merge(
        [
          base_url: base_url,
          method: :post,
          headers: [{"Content-Type", "application/json"}],
          connect_options: [timeout: 10_000]
        ],
        req_opts
      )
    )
  end

  @spec request(
          t(),
          String.t(),
          any(),
          any(),
          atom()
        ) :: OpenFeature.Provider.result()
  defp request(
         %__MODULE__{retry_after: retry_after} = provider,
         key,
         default,
         context,
         expected_type
       )
       when not is_nil(retry_after) do
    now = DateTime.utc_now()

    if DateTime.compare(now, retry_after) == :lt do
      retry_after_str = DateTime.to_iso8601(retry_after)
      Logger.warning("OFREP evaluation paused due to rate limiting until #{retry_after_str}")

      {:ok,
       %ResolutionDetails{
         value: default,
         error_code: :general,
         error_message: "Rate limited. Retry after: #{retry_after_str}",
         reason: :error
       }}
    else
      updated_provider = %{provider | retry_after: nil}
      OpenFeature.Store.set_provider(provider.domain, updated_provider)

      request(updated_provider, key, default, context, expected_type)
    end
  end

  defp request(provider, key, default, context, expected_type) do
    case Jason.encode(%{"context" => context}) do
      {:ok, json_body} ->
        do_request(provider, key, default, json_body, expected_type)

      {:error, error} ->
        {:error, :unexpected_error, error}
    end
  end

  @spec do_request(
          t(),
          String.t(),
          any(),
          String.t(),
          atom()
        ) :: OpenFeature.Provider.result()
  defp do_request(provider, key, default, json_body, expected_type) do
    method_path = "/ofrep/v1/evaluate/flags/#{key}"

    parse_options = %{
      provider: provider,
      default: default,
      expected_type: expected_type
    }

    provider.req
    |> Req.merge(url: method_path, body: json_body)
    |> Req.Request.run_request()
    |> parse_result(parse_options)
  rescue
    e -> {:error, :unexpected_error, e}
  end

  @spec parse_result(
          {Req.Request.t(), Req.Response.t()},
          %{provider: t(), default: any(), expected_type: atom()}
        ) :: OpenFeature.Provider.result()
  defp parse_result(
         {_req, %Req.Response{status: 200, body: body}},
         %{default: default, expected_type: expected_type}
       ) do
    value = body["value"]

    if type_of(value) == expected_type do
      {:ok,
       %ResolutionDetails{
         value: value,
         variant: body["variant"],
         reason: Reason.to_reason(body["reason"]),
         flag_metadata: body["flagMetadata"]
       }}
    else
      error_message =
        "Type mismatch: expected #{inspect(expected_type)}, got #{inspect(type_of(value))}"

      {:ok,
       %ResolutionDetails{
         value: default,
         error_code: :type_mismatch,
         error_message: error_message,
         reason: :error
       }}
    end
  end

  defp parse_result({_req, %Req.Response{status: 404}}, %{default: default}) do
    {:ok,
     %ResolutionDetails{
       value: default,
       error_code: :flag_not_found,
       error_message: "Flag not found",
       reason: :error
     }}
  end

  defp parse_result({_req, %Req.Response{status: 400, body: body}}, %{default: default}) do
    error_message = body["message"] || "Unknown error"

    {:ok,
     %ResolutionDetails{
       value: default,
       error_code: :general,
       error_message: error_message,
       reason: :error
     }}
  end

  defp parse_result({_req, %Req.Response{status: status, body: body}}, %{default: default})
       when status in [401, 403] do
    message = body["message"] || "Unknown"
    error_message = "Auth error: #{message}"

    {:ok,
     %ResolutionDetails{
       value: default,
       error_code: :provider_fatal,
       error_message: error_message,
       reason: :error
     }}
  end

  defp parse_result(
         {_req, %Req.Response{status: 429, headers: headers}},
         %{provider: provider, default: default}
       ) do
    retry_after_dt =
      headers
      |> get_retry_after()
      |> parse_retry_after()

    error_message = "Rate limited. Retry after: #{retry_after_dt}"

    updated_provider = %{provider | retry_after: retry_after_dt}
    OpenFeature.Store.set_provider(provider.domain, updated_provider)

    Logger.warning("Rate limited by OFREP service. Retry after: #{retry_after_dt}")

    {:ok,
     %ResolutionDetails{
       value: default,
       error_code: :general,
       error_message: error_message,
       reason: :error
     }}
  end

  defp parse_result({_req, %Req.Response{status: status, body: body}}, _) do
    message = body["message"] || "Unknown error"
    unexpected_error = %RuntimeError{message: "[#{status}] #{message}"}
    {:error, :unexpected_error, unexpected_error}
  end

  @spec type_of(any()) :: atom()
  defp type_of(value) when is_boolean(value), do: :boolean
  defp type_of(value) when is_binary(value), do: :string
  defp type_of(value) when is_number(value), do: :number
  defp type_of(value) when is_map(value), do: :map
  defp type_of(_), do: :unknown

  @spec get_retry_after(list()) :: String.t()
  defp get_retry_after(headers) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, value} -> value
      nil -> "unknown"
    end
  end

  @spec parse_retry_after(String.t()) :: DateTime.t()
  defp parse_retry_after(retry_after) do
    case Integer.parse(retry_after) do
      {seconds, ""} ->
        DateTime.utc_now() |> DateTime.add(seconds, :second)

      _ ->
        case DateTime.from_iso8601(retry_after) do
          {:ok, datetime, _} ->
            datetime

          _ ->
            DateTime.utc_now() |> DateTime.add(60, :second)
        end
    end
  end
end
