defmodule CatEx.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :cat_ex,
      version: @version,
      elixir: "~> 1.15",
      name: "CatEx",
      source_url: "https://github.com/lulucatdev/cat_ex",
      homepage_url: "https://github.com/lulucatdev/cat_ex",
      description:
        "Computer Adaptive Testing (CAT) library for Elixir - a complete port of jsCAT",
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "get-started",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/get-started.md",
        "guides/item-response-theory.md",
        "guides/clowder-multi-cat.md",
        "guides/early-stopping.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: Path.wildcard("guides/*.md")
      ],
      groups_for_modules: [
        Core: [CatEx, CatEx.CAT],
        "Item Response Theory": [CatEx.Utils, CatEx.Optimization],
        "Multi-CAT": [CatEx.Clowder, CatEx.Corpus],
        "Early Stopping": [
          CatEx.Stopping,
          CatEx.Stopping.StopAfterNItems,
          CatEx.Stopping.StopOnSEPlateau,
          CatEx.Stopping.StopIfSEBelowThreshold
        ]
      ]
    ]
  end

  defp package do
    [
      name: "cat_ex",
      maintainers: ["lulucatdev"],
      licenses: ["MIT"],
      files: [
        "lib",
        "guides",
        "mix.exs",
        "Makefile",
        "README.md",
        "LICENSE"
      ],
      links: %{
        "GitHub" => "https://github.com/lulucatdev/cat_ex",
        "Original jsCAT" => "https://github.com/yeatmanlab/jsCAT",
        "jsCAT Paper" => "https://doi.org/10.3758/s13428-024-02578-y"
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
