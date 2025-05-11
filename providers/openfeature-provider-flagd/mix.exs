defmodule FlagdProvider.MixProject do
  use Mix.Project

  @git_repo "https://github.com/open-feature/elixir-sdk-contrib"

  @version "0.1.0"

  def project do
    [
      app: :open_feature_provider_flagd,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix]],

      # Docs
      name: "OpenFeature Flagd",
      source_url: @git_repo,
      homepage_url: "https://openfeature.dev",
      docs: docs(),

      # Hex
      description: "OpenFeature provider for flagd",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :docs, runtime: false},
      {:grpc, "~> 0.9.0"},
      {:open_feature, "~> 0.1"},
      {:mimic, "~> 1.11", only: :test, runtime: false},
      {:req, "~> 0.5"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "../../LICENSE", "../../CONTRIBUTING.md", "CHANGELOG.md"],
      skip_undefined_reference_warnings_on: ["OpenFeature.Provider.Flagd.GRPC.EventStream"]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @git_repo,
        "Changelog" => "https://hexdocs.pm/open_feature_flagd_provider/changelog.html"
      }
    ]
  end
end
