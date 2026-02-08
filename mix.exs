defmodule CatEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :cat_ex,
      version: "0.1.0",
      elixir: "~> 1.15",
      name: "CatEx",
      source_url: "https://github.com/lulucatinnovations/cat_ex",
      homepage_url: "https://github.com/lulucatinnovations/cat_ex",
      description: "Computer Adaptive Testing (CAT) library for Elixir - a port of jsCAT",
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "get-started",
      extras: [
        "guides/get-started.md",
        "guides/item-response-theory.md",
        "guides/clowder-multi-cat.md",
        "guides/early-stopping.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Core: [CatEx, CatEx.CAT],
        "Item Response Theory": [CatEx.Utils, CatEx.Optimization],
        "Multi-CAT": [CatEx.Clowder, CatEx.Corpus],
        "Early Stopping": [CatEx.Stopping, CatEx.Stopping.StopAfterNItems, CatEx.Stopping.StopOnSEPlateau, CatEx.Stopping.StopIfSEBelowThreshold]
      ]
    ]
  end

  defp package do
    [
      name: :cat_ex,
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/lulucatinnovations/cat_ex",
        "Original jsCAT" => "https://github.com/yeatmanlab/jsCAT"
      }
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
