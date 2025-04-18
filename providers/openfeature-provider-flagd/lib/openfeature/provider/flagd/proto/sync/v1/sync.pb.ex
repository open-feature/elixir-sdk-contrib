defmodule Flagd.Sync.V1.SyncFlagsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:provider_id, 1, type: :string, json_name: "providerId")
  field(:selector, 2, type: :string)
end

defmodule Flagd.Sync.V1.SyncFlagsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:flag_configuration, 1, type: :string, json_name: "flagConfiguration")
end

defmodule Flagd.Sync.V1.FetchAllFlagsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:provider_id, 1, type: :string, json_name: "providerId")
  field(:selector, 2, type: :string)
end

defmodule Flagd.Sync.V1.FetchAllFlagsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:flag_configuration, 1, type: :string, json_name: "flagConfiguration")
end

defmodule Flagd.Sync.V1.GetMetadataRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3
end

defmodule Flagd.Sync.V1.GetMetadataResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:metadata, 2, type: Google.Protobuf.Struct)
end

defmodule Flagd.Sync.V1.FlagSyncService.Service do
  @moduledoc false

  use GRPC.Service, name: "flagd.sync.v1.FlagSyncService", protoc_gen_elixir_version: "0.14.1"

  rpc(:SyncFlags, Flagd.Sync.V1.SyncFlagsRequest, stream(Flagd.Sync.V1.SyncFlagsResponse))

  rpc(:FetchAllFlags, Flagd.Sync.V1.FetchAllFlagsRequest, Flagd.Sync.V1.FetchAllFlagsResponse)

  rpc(:GetMetadata, Flagd.Sync.V1.GetMetadataRequest, Flagd.Sync.V1.GetMetadataResponse)
end

defmodule Flagd.Sync.V1.FlagSyncService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Flagd.Sync.V1.FlagSyncService.Service
end
