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
      {:cbor, "~> 1.0.0"},
      {:car, "~> 0.1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:typedstruct, "~> 0.5"},
      {:websockex, "~> 0.5.0", hex: :websockex_wt}
    ]
  end
end
