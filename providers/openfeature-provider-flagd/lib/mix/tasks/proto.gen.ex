defmodule Mix.Tasks.Proto.Gen do
  @moduledoc """
  Mix task for downloading and compiling flagd protobuf definitions.

  This task:

    1. Downloads the `evaluation.proto` and `sync.proto` files from the official
       flagd Buf registry.
    2. Saves them to `priv/protos/`.
    3. Runs `protoc` to generate Elixir + gRPC modules into
       `lib/openfeature/provider/flagd/proto/`.

  ## Usage

  Run the following from the root of the project:

      mix proto.gen

  This is primarily intended for development workflows until `buf` supports Elixir
  as a target. Generated modules are checked in and used by the Flagd provider.
  """

  use Mix.Task

  @shortdoc "Downloads flagd protos and generates Elixir modules"

  @impl true
  def run(_args) do
    Application.ensure_all_started(:req)

    Mix.shell().info("Downloading protos...")
    Enum.each(buf_urls(), &download_proto!/1)

    Mix.shell().info("Generating Elixir modules with protoc...")

    protos =
      Path.wildcard("priv/protos/**/*.proto")
      |> Enum.join(" ")

    cmd =
      "protoc --proto_path=priv/protos " <>
        "--elixir_out=plugins=grpc:./lib/openfeature/provider/flagd/proto " <>
        protos

    Mix.shell().info("Running: #{cmd}")
    Mix.shell().cmd(cmd)

    Mix.shell().info("Formatting generated code...")
    Mix.Task.run("format")
  end

  defp download_proto!({url, path}) do
    File.mkdir_p!(Path.dirname(path))
    Mix.shell().info("Fetching: #{url}")

    case Req.get(url) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        File.write!(path, body)
        Mix.shell().info("✅ Wrote: #{path}")

      {:ok, %Req.Response{status: status}} ->
        Mix.raise("❌ Failed to fetch #{url} (status: #{status})")

      {:error, error} ->
        Mix.raise("❌ Req error fetching #{url}: #{inspect(error)}")
    end
  end

  defp buf_urls do
    [
      {"https://buf.build/open-feature/flagd/raw/main/-/flagd/evaluation/v1/evaluation.proto",
       "priv/protos/evaluation/v1/evaluation.proto"},
      {"https://buf.build/open-feature/flagd/raw/main/-/flagd/sync/v1/sync.proto", "priv/protos/sync/v1/sync.proto"}
    ]
  end
end
