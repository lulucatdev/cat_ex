defmodule CatEx.CAT do
  @moduledoc """
  Core Computer Adaptive Testing (CAT) functionality.

  This module implements the main adaptive testing loop:

  1. **Create** a CAT instance with `new/1`
  2. **Update** the ability estimate after each response with `update_ability_estimate/3`
  3. **Select** the next item with `find_next_item/3`

  ## Estimation Methods

  | Method | Description | Best For |
  |--------|-------------|----------|
  | `"MLE"` | Maximum Likelihood Estimation via Powell optimization | 3+ responses |
  | `"EAP"` | Expected A Posteriori with prior distribution | Early stages / few responses |

  ## Item Selection Methods

  | Method | Description |
  |--------|-------------|
  | `"MFI"` | Maximum Fisher Information at current theta (default) |
  | `"closest"` | Item with difficulty closest to theta + 0.481 |
  | `"random"` | Random selection |
  | `"fixed"` | Sequential corpus order |
  | `"middle"` | From middle of difficulty range (useful for start items) |

  ## Examples

      # Create and run a basic CAT
      cat = CatEx.CAT.new(method: "MLE", item_select: "MFI")
      cat = CatEx.CAT.update_ability_estimate(cat, %{a: 1, b: 0, c: 0, d: 1}, 1)
      {next_item, remaining} = CatEx.CAT.find_next_item(cat, stimuli)

      # EAP with normal prior
      cat = CatEx.CAT.new(method: "EAP", prior_dist: "norm", prior_par: [0, 1])

      # Batch update with multiple items
      cat = CatEx.CAT.update_ability_estimate(cat, [zeta1, zeta2, zeta3], [1, 0, 1])
  """

  alias CatEx.Utils

  @type t :: %__MODULE__{
          method: String.t(),
          item_select: String.t(),
          n_start_items: non_neg_integer(),
          start_select: String.t(),
          theta: float(),
          min_theta: float(),
          max_theta: float(),
          prior_dist: String.t(),
          prior_par: list(float()),
          zetas: list(map()),
          resps: list(0 | 1),
          se_measurement: float(),
          prior: list({float(), float()}),
          random_seed: String.t() | nil
        }

  defstruct [
    :method,
    :item_select,
    :n_start_items,
    :start_select,
    :theta,
    :min_theta,
    :max_theta,
    :prior_dist,
    :prior_par,
    :zetas,
    :resps,
    :se_measurement,
    :prior,
    :random_seed
  ]

  @valid_methods ["mle", "eap"]
  @valid_item_selectors ["mfi", "random", "closest", "fixed", "middle"]
  @valid_start_selectors ["random", "middle", "fixed"]

  @doc """
  Creates a new CAT instance.

  ## Options

  - `:method` - Ability estimator ("MLE" or "EAP"), default: "MLE"
  - `:item_select` - Item selection method ("MFI", "random", "closest", "fixed"), default: "MFI"
  - `:n_start_items` - Number of non-adaptive start items, default: 0
  - `:start_select` - Selection method for start items ("random", "middle", "fixed"), default: "middle"
  - `:theta` - Initial ability estimate, default: 0.0
  - `:min_theta` - Minimum theta value, default: -6.0
  - `:max_theta` - Maximum theta value, default: 6.0
  - `:prior_dist` - Prior distribution type for EAP ("norm" or "unif"), default: "norm"
  - `:prior_par` - Prior distribution parameters, default: [0, 1] for norm, [-4, 4] for unif
  - `:random_seed` - Seed for reproducible randomization, default: nil

  ## Examples

      cat = CatEx.CAT.new(method: "MLE", item_select: "MFI")
      cat = CatEx.CAT.new(method: "EAP", prior_dist: "norm", prior_par: [0, 1])
  """
  def new(opts \\ []) do
    method = validate_method(Keyword.get(opts, :method, "MLE"))
    prior_dist = Keyword.get(opts, :prior_dist, "norm")
    prior_par = Keyword.get(opts, :prior_par, default_prior_par(prior_dist))
    min_theta = Keyword.get(opts, :min_theta, -6.0)
    max_theta = Keyword.get(opts, :max_theta, 6.0)

    prior =
      if method == "eap" do
        validate_prior(prior_dist, prior_par, min_theta, max_theta)
      else
        []
      end

    %__MODULE__{
      method: method,
      item_select: validate_item_select(Keyword.get(opts, :item_select, "MFI")),
      n_start_items: Keyword.get(opts, :n_start_items, 0),
      start_select: validate_start_select(Keyword.get(opts, :start_select, "middle")),
      theta: Keyword.get(opts, :theta, 0.0),
      min_theta: min_theta,
      max_theta: max_theta,
      prior_dist: prior_dist,
      prior_par: prior_par,
      zetas: [],
      resps: [],
      se_measurement: :infinity,
      prior: prior,
      random_seed: Keyword.get(opts, :random_seed)
    }
  end

  @doc """
  Updates the ability estimate based on new responses.

  ## Parameters

  - `cat` - The CAT instance
  - `zeta` - Item parameters (single or list)
  - `answer` - Response(s) (0 or 1, single or list)

  ## Examples

      cat = CatEx.CAT.update_ability_estimate(cat, %{a: 1, b: 0, c: 0, d: 1}, 1)
      cat = CatEx.CAT.update_ability_estimate(cat, [zeta1, zeta2], [1, 0])
  """
  def update_ability_estimate(cat, zeta, answer) do
    zeta_list = if is_list(zeta), do: zeta, else: [zeta]
    answer_list = if is_list(answer), do: answer, else: [answer]

    if length(zeta_list) != length(answer_list) do
      raise ArgumentError, "Unmatched length between answers and item params"
    end

    zetas = cat.zetas ++ zeta_list
    resps = cat.resps ++ answer_list

    theta =
      case cat.method do
        "eap" -> estimate_ability_eap(zetas, resps, cat.prior)
        "mle" -> estimate_ability_mle(zetas, resps, cat.min_theta, cat.max_theta)
      end

    theta = clamp(theta, cat.min_theta, cat.max_theta)
    se = calculate_se(theta, zetas)

    %{cat | zetas: zetas, resps: resps, theta: theta, se_measurement: se}
  end

  @doc """
  Finds the next item from the available stimuli.

  Returns `{next_stimulus, remaining_stimuli}`.

  ## Parameters

  - `cat` - The CAT instance
  - `stimuli` - List of available stimuli
  - `item_select` - Override item selection method (optional)

  ## Examples

      {next_item, remaining} = CatEx.CAT.find_next_item(cat, stimuli)
  """
  def find_next_item(cat, stimuli, item_select \\ nil) do
    n_items = length(cat.resps)

    selector =
      if n_items < cat.n_start_items do
        cat.start_select
      else
        item_select || cat.item_select
      end
      |> validate_item_select()

    # Fill zeta defaults for each stimulus but preserve original stimulus
    stimuli_with_defaults =
      Enum.map(stimuli, fn stim ->
        {Utils.fill_zeta_defaults(stim), stim}
      end)

    case selector do
      "mfi" -> selector_mfi(cat.theta, stimuli_with_defaults)
      "random" -> selector_random(stimuli_with_defaults, cat.random_seed)
      "closest" -> selector_closest(cat.theta, stimuli_with_defaults)
      "fixed" -> selector_fixed(stimuli_with_defaults)
      "middle" -> selector_middle(stimuli_with_defaults, cat.n_start_items)
    end
  end

  @doc """
  Returns the number of items administered.
  """
  def n_items(%__MODULE__{resps: resps}), do: length(resps)
  def n_items(%{n_items: n}) when is_integer(n), do: n

  # Private functions

  defp validate_method(method) do
    method = String.downcase(method)

    if method in @valid_methods,
      do: method,
      else: raise(ArgumentError, "Invalid method: #{method}")
  end

  defp validate_item_select(selector) do
    selector = String.downcase(selector)

    if selector in @valid_item_selectors,
      do: selector,
      else: raise(ArgumentError, "Invalid item selector: #{selector}")
  end

  defp validate_start_select(selector) do
    selector = String.downcase(selector)

    if selector in @valid_start_selectors,
      do: selector,
      else: raise(ArgumentError, "Invalid start selector: #{selector}")
  end

  defp default_prior_par("norm"), do: [0.0, 1.0]
  defp default_prior_par("unif"), do: [-4.0, 4.0]

  defp default_prior_par(dist) do
    raise ArgumentError, "priorDist must be unif or norm, got: #{inspect(dist)}"
  end

  defp validate_prior(dist, prior_par, _min_theta, _max_theta)
       when not is_list(prior_par) or length(prior_par) != 2 do
    raise ArgumentError,
          "prior_par must be an array of two numbers, got: #{inspect(prior_par)} for dist: #{dist}"
  end

  defp validate_prior("norm", [mean, sd], min_theta, max_theta) do
    if sd <= 0,
      do: raise(ArgumentError, "The positive standard deviation of the prior must be positive")

    if mean < min_theta or mean > max_theta do
      raise(ArgumentError, "The prior distribution mean must be within theta bounds")
    end

    Utils.normal_distribution(mean, sd, min_theta, max_theta)
  end

  defp validate_prior("unif", [min_s, max_s], min_theta, max_theta) do
    if min_s >= max_s, do: raise(ArgumentError, "Invalid uniform bounds")

    if min_s < min_theta or max_s > max_theta do
      raise(ArgumentError, "Uniform bounds must be within theta bounds")
    end

    Utils.uniform_distribution(min_s, max_s, min_theta, max_theta)
  end

  defp estimate_ability_eap(zetas, resps, prior) do
    {num, den} =
      Enum.reduce(prior, {0, 0}, fn {theta, prob}, {n, d} ->
        like = :math.exp(Utils.log_likelihood(theta, zetas, resps))
        {n + theta * like * prob, d + like * prob}
      end)

    if den == 0, do: 0, else: num / den
  end

  defp estimate_ability_mle(zetas, resps, min_theta, max_theta) do
    # Use Powell's optimization method to maximize log-likelihood
    neg_log_likelihood = fn theta ->
      -Utils.log_likelihood(theta, zetas, resps)
    end

    # Start from current theta estimate (0 or previous value)
    # Try multiple starting points to find global maximum
    starting_points = [0.0, min_theta / 2, max_theta / 2, (min_theta + max_theta) / 2]

    {best_theta, _} =
      starting_points
      |> Enum.map(fn start ->
        {theta, neg_ll} =
          CatEx.Optimization.powell_minimize(neg_log_likelihood, start, 1.0e-6, 100)

        {theta, -neg_ll}
      end)
      |> Enum.max_by(fn {_, ll} -> ll end)

    # Clamp to bounds
    clamp(best_theta, min_theta, max_theta)
  end

  defp calculate_se(theta, zetas) do
    sum =
      Enum.reduce(zetas, 0, fn zeta, acc ->
        acc + Utils.fisher_information(theta, zeta)
      end)

    if sum > 0, do: 1.0 / :math.sqrt(sum), else: :infinity
  end

  defp selector_mfi(_theta, []), do: {nil, []}

  defp selector_mfi(theta, stimuli_with_defaults) do
    # stimuli_with_defaults is a list of {zeta, stim} tuples
    stimuli_with_fi =
      Enum.map(stimuli_with_defaults, fn {zeta, stim} ->
        fi = Utils.fisher_information(theta, zeta)
        {fi, stim}
      end)

    [{_, next_stimulus} | rest] = Enum.sort_by(stimuli_with_fi, fn {fi, _} -> -fi end)

    remaining =
      Enum.map(rest, fn {_, stim} -> stim end)
      |> Enum.sort_by(fn stim -> Utils.get_difficulty(stim) end)

    {next_stimulus, remaining}
  end

  defp selector_random([], _seed), do: {nil, []}

  defp selector_random(stimuli_with_defaults, _seed) do
    index = :rand.uniform(length(stimuli_with_defaults)) - 1
    {{_, next}, remaining} = List.pop_at(stimuli_with_defaults, index)
    {next, Enum.map(remaining, fn {_, stim} -> stim end)}
  end

  defp selector_closest(_theta, []), do: {nil, []}

  defp selector_closest(theta, stimuli_with_defaults) do
    sorted = Enum.sort_by(stimuli_with_defaults, fn {_, stim} -> Utils.get_difficulty(stim) end)
    target = theta + 0.481

    index = Utils.find_closest_index(Enum.map(sorted, fn {_, stim} -> stim end), target)
    {{_, next}, remaining} = List.pop_at(sorted, index)
    {next, Enum.map(remaining, fn {_, stim} -> stim end)}
  end

  defp selector_fixed([]), do: {nil, []}
  defp selector_fixed([{_, next} | rest]), do: {next, Enum.map(rest, fn {_, stim} -> stim end)}

  defp selector_middle([], _n_start), do: {nil, []}

  defp selector_middle(stimuli_with_defaults, n_start) do
    index = div(length(stimuli_with_defaults), 2)

    offset =
      if length(stimuli_with_defaults) >= n_start do
        # Match jsCAT: randomInteger(-floor(n/2), floor(n/2))
        half = div(n_start, 2)
        :rand.uniform(2 * half + 1) - half - 1
      else
        0
      end

    index = max(0, min(index + offset, length(stimuli_with_defaults) - 1))
    {{_, next}, remaining} = List.pop_at(stimuli_with_defaults, index)
    {next, Enum.map(remaining, fn {_, stim} -> stim end)}
  end

  defp clamp(value, min, _max) when value < min, do: min
  defp clamp(value, _min, max) when value > max, do: max
  defp clamp(value, _min, _max), do: value
end
