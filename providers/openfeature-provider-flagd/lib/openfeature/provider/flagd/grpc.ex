defmodule OpenFeature.Provider.Flagd.GRPC do
  @moduledoc """
  OpenFeature provider for flagd that communicates with a `flagd` instance over gRPC.

  This is a remote flagd provider that uses the gRPC evaluation API to resolve flag values.
  """
  @moduledoc since: "0.1.0"

  require Logger

  @behaviour OpenFeature.Provider

  alias Flagd.Evaluation.V1, as: Eval
  alias Google.Protobuf.Struct
  alias OpenFeature.Provider.Flagd.Reason
  alias OpenFeature.ResolutionDetails
  alias Protobuf.JSON.Decode
  alias Protobuf.JSON.Encode

  defstruct name: "FlagdGRPC",
            host: "localhost",
            port: 8013,
            tls: false,
            cacertfile: nil,
            cacerts: nil,
            domain: nil,
            hooks: [],
            state: :not_ready,
            channel: nil

  @typedoc "GRPC provider for flagd"
  @type t() :: %__MODULE__{
          name: String.t(),
          host: String.t(),
          port: pos_integer(),
          tls: boolean(),
          cacertfile: String.t() | nil,
          cacerts: term() | nil,
          domain: String.t() | nil,
          hooks: [OpenFeature.Hook.t()],
          state: :not_ready | :ready,
          channel: GRPC.Channel.t() | nil
        }

  @config_opts [:host, :port, :tls, :cacertfile, :cacerts, :name, :domain, :hooks]

  @doc """
  Creates a new flagd gRPC provider.

  ## Options

    * `:host` - The hostname or IP address of the flagd instance (default: `"localhost"`)
    * `:port` - The port number (default: `8013`)
    * `:tls` - Whether to use TLS for connections (default: `false`)
    * `:cacertfile` - (optional) Path to a custom TLS certificate file
    * `:cacerts` - (optional) CA certificates as PEM-encoded binaries
    * `:name` - (optional) Custom name for the provider (default: `"FlagdGRPC"`)
    * `:domain` - (optional) Domain name to differentiate between providers
    * `:hooks` - (optional) A list of OpenFeature hooks (%OpenFeature.Hook{})

  ## Examples

  ```elixir
  # Simple usage with defaults
  provider = OpenFeature.Provider.Flagd.GRPC.new()

  # With custom options
  provider = OpenFeature.Provider.Flagd.GRPC.new(port: 8013, domain: "my-service")

  # With TLS enabled
  provider = OpenFeature.Provider.Flagd.GRPC.new(
    host: "flagd.example.com",
    tls: true,
    cacertfile: "/path/to/cert.pem"
  )
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
  def initialize(provider, domain, _context) do
    target = "#{provider.host}:#{provider.port}"
    opts = grpc_connection_opts(provider)

    case GRPC.Stub.connect(target, opts) do
      {:ok, channel} ->
        {:ok, %{provider | domain: domain, state: :ready, channel: channel}}

      {:error, reason} ->
        Logger.error("Failed to initialize GRPC provider: #{inspect(reason)}")
        {:error, :provider_not_ready}
    end
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
    request = %Eval.ResolveBooleanRequest{flag_key: key, context: to_protobuf_struct(context)}

    case Eval.Service.Stub.resolve_boolean(provider.channel, request) do
      {:ok, %Eval.ResolveBooleanResponse{} = res} -> {:ok, to_result(res)}
      {:error, _} -> {:error, :flag_not_found}
    end
  end

  @impl true
  @spec resolve_string_value(
          provider :: t(),
          key :: String.t(),
          default :: String.t(),
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_string_value(provider, key, _default, context) do
    request = %Eval.ResolveStringRequest{flag_key: key, context: to_protobuf_struct(context)}

    case Eval.Service.Stub.resolve_string(provider.channel, request) do
      {:ok, %Eval.ResolveStringResponse{} = res} -> {:ok, to_result(res)}
      {:error, _} -> {:error, :flag_not_found}
    end
  end

  @impl true
  @spec resolve_number_value(
          provider :: t(),
          key :: String.t(),
          default :: number,
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_number_value(provider, key, default, context) do
    {fun, request} =
      if is_integer(default) do
        {:resolve_int, %Eval.ResolveIntRequest{flag_key: key, context: to_protobuf_struct(context)}}
      else
        {:resolve_float, %Eval.ResolveFloatRequest{flag_key: key, context: to_protobuf_struct(context)}}
      end

    case apply(Eval.Service.Stub, fun, [provider.channel, request]) do
      {:ok, res} -> {:ok, to_result(res)}
      {:error, _} -> {:error, :flag_not_found}
    end
  end

  @impl true
  @spec resolve_map_value(
          provider :: t(),
          key :: String.t(),
          default :: map,
          context :: any()
        ) :: OpenFeature.Provider.result()
  def resolve_map_value(provider, key, _default, context) do
    request = %Eval.ResolveObjectRequest{flag_key: key, context: to_protobuf_struct(context)}

    case Eval.Service.Stub.resolve_object(provider.channel, request) do
      {:ok, %Eval.ResolveObjectResponse{} = res} -> {:ok, to_result(res)}
      {:error, _} -> {:error, :flag_not_found}
    end
  end

  defp grpc_connection_opts(%__MODULE__{tls: true, cacerts: cacerts})
       when not is_nil(cacerts) do
    [cred: GRPC.Credential.new(ssl: [cacerts: cacerts])]
  end

  defp grpc_connection_opts(%__MODULE__{tls: true, cacertfile: cacertfile})
       when is_binary(cacertfile) do
    [cred: GRPC.Credential.new(ssl: [cacertfile: cacertfile])]
  end

  defp grpc_connection_opts(%__MODULE__{tls: true}) do
    # Try to use system certificate store if available (OTP 25+)

    if function_exported?(:public_key, :cacerts_get, 0) do
      cacerts = :public_key.cacerts_get()
      [cred: GRPC.Credential.new(ssl: [cacerts: cacerts])]
    else
      Logger.info("System CA certificate store unavailable (requires OTP 25+)")
      [cred: GRPC.Credential.new(ssl: true)]
    end
  rescue
    _ ->
      Logger.warning("Could not load system CA certificates, using default SSL configuration")
      [cred: GRPC.Credential.new(ssl: true)]
  end

  defp grpc_connection_opts(_provider), do: []

  defp to_result(res) do
    %ResolutionDetails{
      value: decode_struct_value(res.value),
      variant: res.variant,
      reason: Reason.to_reason(res.reason),
      flag_metadata: decode_struct_value(res.metadata)
    }
  end

  defp decode_struct_value(%Struct{} = struct), do: Encode.encodable(struct, nil)
  defp decode_struct_value(val), do: val

  defp to_protobuf_struct(context) do
    context
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.into(%{})
    |> Decode.from_json_data(Google.Protobuf.Struct)
  end
end
