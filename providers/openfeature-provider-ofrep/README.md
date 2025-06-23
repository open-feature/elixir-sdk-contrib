# OFREP Provider for OpenFeature

An OpenFeature provider for `OpenFeature Remote Evaluation Protocol (OFREP)`, enabling feature flag evaluation in Elixir over HTTP.

## Installation

Add `open_feature_provider_ofrep` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:open_feature_provider_ofrep, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
provider = OpenFeature.Provider.OFREP.new(base_url: "http://ofrep-service:8016")
{:ok, _} = OpenFeature.set_provider(provider)

client = OpenFeature.get_client()
OpenFeature.Client.get_boolean_value(client, "my-feature", false)
```
