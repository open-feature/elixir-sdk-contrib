defmodule Flagd.Evaluation.V1.ResolveAllRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:context, 1, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.ResolveAllResponse.FlagsEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: Flagd.Evaluation.V1.AnyFlag)
end

defmodule Flagd.Evaluation.V1.ResolveAllResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:flags, 1,
    repeated: true,
    type: Flagd.Evaluation.V1.ResolveAllResponse.FlagsEntry,
    map: true
  )

  field(:metadata, 2, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.AnyFlag do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  oneof(:value, 0)

  field(:reason, 1, type: :string)
  field(:variant, 2, type: :string)
  field(:bool_value, 3, type: :bool, json_name: "boolValue", oneof: 0)
  field(:string_value, 4, type: :string, json_name: "stringValue", oneof: 0)
  field(:double_value, 5, type: :double, json_name: "doubleValue", oneof: 0)
  field(:object_value, 6, type: Google.Protobuf.Struct, json_name: "objectValue", oneof: 0)
  field(:metadata, 7, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.ResolveBooleanRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:flag_key, 1, type: :string, json_name: "flagKey")
  field(:context, 2, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.ResolveBooleanResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:value, 1, type: :bool)
  field(:reason, 2, type: :string)
  field(:variant, 3, type: :string)
  field(:metadata, 4, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.ResolveStringRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:flag_key, 1, type: :string, json_name: "flagKey")
  field(:context, 2, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.ResolveStringResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:value, 1, type: :string)
  field(:reason, 2, type: :string)
  field(:variant, 3, type: :string)
  field(:metadata, 4, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.ResolveFloatRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:flag_key, 1, type: :string, json_name: "flagKey")
  field(:context, 2, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.ResolveFloatResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:value, 1, type: :double)
  field(:reason, 2, type: :string)
  field(:variant, 3, type: :string)
  field(:metadata, 4, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.ResolveIntRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:flag_key, 1, type: :string, json_name: "flagKey")
  field(:context, 2, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.ResolveIntResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:value, 1, type: :int64)
  field(:reason, 2, type: :string)
  field(:variant, 3, type: :string)
  field(:metadata, 4, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.ResolveObjectRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:flag_key, 1, type: :string, json_name: "flagKey")
  field(:context, 2, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.ResolveObjectResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:value, 1, type: Google.Protobuf.Struct)
  field(:reason, 2, type: :string)
  field(:variant, 3, type: :string)
  field(:metadata, 4, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.EventStreamResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:type, 1, type: :string)
  field(:data, 2, type: Google.Protobuf.Struct)
end

defmodule Flagd.Evaluation.V1.EventStreamRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3
end

defmodule Flagd.Evaluation.V1.Service.Service do
  @moduledoc false

  use GRPC.Service, name: "flagd.evaluation.v1.Service", protoc_gen_elixir_version: "0.14.1"

  rpc(:ResolveAll, Flagd.Evaluation.V1.ResolveAllRequest, Flagd.Evaluation.V1.ResolveAllResponse)

  rpc(
    :ResolveBoolean,
    Flagd.Evaluation.V1.ResolveBooleanRequest,
    Flagd.Evaluation.V1.ResolveBooleanResponse
  )

  rpc(
    :ResolveString,
    Flagd.Evaluation.V1.ResolveStringRequest,
    Flagd.Evaluation.V1.ResolveStringResponse
  )

  rpc(
    :ResolveFloat,
    Flagd.Evaluation.V1.ResolveFloatRequest,
    Flagd.Evaluation.V1.ResolveFloatResponse
  )

  rpc(:ResolveInt, Flagd.Evaluation.V1.ResolveIntRequest, Flagd.Evaluation.V1.ResolveIntResponse)

  rpc(
    :ResolveObject,
    Flagd.Evaluation.V1.ResolveObjectRequest,
    Flagd.Evaluation.V1.ResolveObjectResponse
  )

  rpc(
    :EventStream,
    Flagd.Evaluation.V1.EventStreamRequest,
    stream(Flagd.Evaluation.V1.EventStreamResponse)
  )
end

defmodule Flagd.Evaluation.V1.Service.Stub do
  @moduledoc false

  use GRPC.Stub, service: Flagd.Evaluation.V1.Service.Service
end
