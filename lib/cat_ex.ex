defmodule CatEx do
  @moduledoc """
  Computer Adaptive Testing (CAT) library for Elixir.

  CatEx is a complete port of [jsCAT](https://github.com/yeatmanlab/jsCAT),
  providing IRT-based adaptive testing for educational and psychological
  assessments.

  **Maintained by [Lulucat Innovations](https://github.com/lulucatinnovations)**

  ## Core Modules

  | Module | Purpose |
  |--------|---------|
  | `CatEx.CAT` | Ability estimation (MLE/EAP), item selection, and the main CAT loop |
  | `CatEx.Utils` | 4PL item response function, Fisher information, distributions |
  | `CatEx.Clowder` | Multi-CAT management with shared corpus |
  | `CatEx.Corpus` | Corpus preparation, validation, and format conversion |
  | `CatEx.Stopping` | Early stopping strategies (N items, SE plateau, SE threshold) |
  | `CatEx.Optimization` | Powell/Brent optimization for MLE |

  ## Quick Example

      # 1. Create a CAT
      cat = CatEx.CAT.new(method: "MLE", item_select: "MFI")

      # 2. Update ability with a response
      cat = CatEx.CAT.update_ability_estimate(cat, %{a: 1, b: 0, c: 0, d: 1}, 1)

      # 3. Select the next item
      {next_item, remaining} = CatEx.CAT.find_next_item(cat, stimuli)

      # 4. Check state
      cat.theta            # Current ability estimate
      cat.se_measurement   # Standard error
      CatEx.CAT.n_items(cat)  # Items administered

  See the [Get Started](get-started.md) guide for a full walkthrough.
  """

  @doc """
  Returns the current version of CatEx.

  ## Example

      iex> CatEx.version()
      "0.1.0"
  """
  def version do
    "0.1.0"
  end
end
