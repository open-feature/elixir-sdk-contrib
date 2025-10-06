defmodule OpenFeature.Provider.OFREP.Reason do
  @moduledoc """
  Converts string reasons from OFREP into OpenFeature reason atoms.
  """
  @moduledoc since: "0.1.0"

  @reasons %{
    "static" => :static,
    "default" => :default,
    "targeting_match" => :targeting_match,
    "split" => :split,
    "cached" => :cached,
    "disabled" => :disabled,
    "unknown" => :unknown,
    "stale" => :stale,
    "error" => :error
  }

  @spec to_reason(String.t() | nil) :: OpenFeature.Types.reason()
  def to_reason(nil), do: :unknown

  def to_reason(reason) do
    Map.get(@reasons, String.downcase(reason), :unknown)
  end
end
