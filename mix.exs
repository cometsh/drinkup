defmodule Drinkup.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/cometsh/drinkup"

  def project do
    [
      app: :drinkup,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Drinkup",
      description: "ATProtocol firehose & subscription listener",
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Drinkup.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:car, "~> 0.1.0"},
      {:cbor, "~> 1.0.0"},
      {:certifi, "~> 2.15"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:ezstd, "~> 1.1"},
      {:gun, "~> 2.2"},
      {:typedstruct, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5.0"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      extras: [
        LICENSE: [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end
end
