# Flagd Provider for OpenFeature

An OpenFeature provider for `flagd`, enabling feature flag evaluation in Elixir using gRPC or HTTP.

This library integrates with the OpenFeature SDK for Elixir and supports remote evaluation via `flagd` using gRPC or HTTP.

## Installation

Add `open_feature_flagd_provider` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:open_feature_provider_flagd, "~> 0.1.0"}]
end
```

## Providers

This library supports:

- `OpenFeature.Provider.Flagd.HTTP`
- `OpenFeature.Provider.Flagd.GRPC`

All providers implement the `OpenFeature.Provider` behaviour and can be used with the OpenFeature SDK. This means you can swap between providers (e.g. `gRPC` or `HTTP`) with no changes to your application code beyond provider initialization.

## Usage

### gRPC Provider

```elixir
# Simple usage with defaults
provider = OpenFeature.Provider.Flagd.GRPC.new()

# With custom options
provider = OpenFeature.Provider.Flagd.GRPC.new(
  host: "flagd.example.com",
  port: 8013,
  tls: true,
  cacertfile: "/path/to/cert.pem"
)

{:ok, _} = OpenFeature.set_provider(provider)
client = OpenFeature.get_client()
OpenFeature.Client.get_boolean_value(client, "my-feature", false)
```

### Event Streaming

The gRPC provider supports event streaming via the EventStream module. This allows your application to receive `:ready` and `:configuration_changed` events from flagd.

To enable streaming, you must start the stream manually using `OpenFeature.Provider.Flagd.GRPC.EventStream.start_link(client)`. The stream runs as a long-lived `GenServer` and should be supervised using either static or dynamic supervision, depending on your needs.

For setup examples and supervision options, see the `EventStream` module documentation.

### HTTP Provider

```elixir
# Simple usage with defaults
provider = OpenFeature.Provider.Flagd.HTTP.new()

# With custom options
provider = OpenFeature.Provider.Flagd.HTTP.new(
  scheme: "https",
  host: "flagd.example.com",
  port: 8013
)

{:ok, _} = OpenFeature.set_provider(provider)
client = OpenFeature.get_client()
OpenFeature.Client.get_boolean_value(client, "my-feature", false)
```

## Regenerating gRPC Protos (Development Only)

This project includes a mix task to download and generate Elixir modules from the latest [`flagd`](https://buf.build/open-feature/flagd) protobuf definitions.

To regenerate:

```sh
mix proto.gen
```

> [!NOTE]
> You must have both `protoc` and `protoc-gen-elixir` available in your system `PATH` for this task to work. See the [official docs](https://hexdocs.pm/protobuf/readme.html#generate-elixir-code) for installation instructions.

## Roadmap

- [ ] Cache resolution details
- [ ] In-process provider using the flagd sync protocol
