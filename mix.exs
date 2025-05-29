defmodule Drinkup.MixProject do
  use Mix.Project

  def project do
    [
      app: :drinkup,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:car, "~> 0.1.0"},
      {:cbor, "~> 1.0.0"},
      {:certifi, "~> 2.15"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:gun, "~> 2.2"},
      {:typedstruct, "~> 0.5"}
    ]
  end
end
