defmodule Buzy.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/dualohq/buzy"

  def project do
    [
      app: :buzy,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      docs: docs(),
      deps: deps(),
      package: package(),
      description: description()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {Buzy.Application, []}
    ]
  end

  defp deps do
    [
      # {:peri, "~> 0.3.2"},
      # fork to support defining a description for a field and a new api to generate open api and json schema definitions.
      {:peri, "~> 0.3.2", github: "michaelbearne/peri"},
      {:req_client_base, "~> 0.1.0", organization: "dualo"},
      {:test_llm, "~> 0.1.0", organization: "dualo", only: :test},
      {:ecto_ulid, "~> 0.3.0", optional: true},
      {:elixir_uuid, "~> 1.2", optional: true},
      {:pockets, "~> 1.6"},
      {:murmur, "~> 2.0"}
    ]
  end

  defp description do
    "Framework for building LLM-powered applications, inspired by Langchain and Langgraph."
  end

  # https://hexdocs.pm/hex/Mix.Tasks.Hex.Build.html#module-package-configuration
  defp package do
    [
      name: "buzy",
      maintainers: ["Michael Bearne"],
      links: %{"GitHub" => @source_url},
      licenses: ["SEE LICENSE IN LICENSE"],
      organization: "dualo"
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
