defmodule CatEx.Utils do
  @moduledoc """
  Item Response Theory utility functions.

  This module provides the mathematical foundation for adaptive testing:

  - **`item_response_function/2`** - 4PL probability of correct response
  - **`fisher_information/2`** - Information an item provides at a given ability
  - **`log_likelihood/3`** - Log-likelihood of a response pattern
  - **`normal_distribution/5`** - Normal prior for EAP estimation
  - **`uniform_distribution/5`** - Uniform prior for EAP estimation
  - **`fill_zeta_defaults/1`** - Fill missing IRT parameters with defaults
  - **`find_closest_index/2`** - Binary search for closest difficulty match

  ## Parameter Formats

  Item parameters (zeta) can use either **symbolic** or **semantic** keys:

  | Symbolic | Semantic | Meaning | Default |
  |----------|----------|---------|---------|
  | `:a` | `:discrimination` | Slope / discrimination | 1.0 |
  | `:b` | `:difficulty` | Location / difficulty | 0.0 |
  | `:c` | `:guessing` | Lower asymptote / guessing | 0.0 |
  | `:d` | `:slipping` | Upper asymptote / slipping | 1.0 |

  Missing parameters are automatically filled with their defaults.
  """

  @doc """
  Calculates the 4PL Item Response Function.

  Returns the probability that someone with ability theta will answer correctly.

  ## Parameters

  - `theta` - Ability estimate
  - `zeta` - Item parameters (a, b, c, d)

  ## Formula

      P(theta) = c + (d - c) / (1 + exp(-a * (theta - b)))

  ## Examples

      iex> CatEx.Utils.item_response_function(0, %{a: 1, b: 0, c: 0, d: 1})
      0.5
  """
  def item_response_function(theta, zeta) do
    z = fill_zeta_defaults(zeta)
    z.c + (z.d - z.c) / (1 + :math.exp(-z.a * (theta - z.b)))
  end

  @doc """
  Calculates Fisher Information for an item.

  Fisher Information measures the amount of information an item provides
  about the ability estimate at a given theta value.

  ## Parameters

  - `theta` - Ability estimate
  - `zeta` - Item parameters

  ## Examples

      iex> CatEx.Utils.fisher_information(0, %{a: 1, b: 0, c: 0, d: 1})
      0.25
  """
  def fisher_information(theta, zeta) do
    z = fill_zeta_defaults(zeta)
    p = item_response_function(theta, z)
    q = 1 - p

    if p <= z.c or p >= z.d do
      0.0
    else
      :math.pow(z.a, 2) * (q / p) * (:math.pow(p - z.c, 2) / :math.pow(1 - z.c, 2))
    end
  end

  @doc """
  Calculates the log-likelihood of responses given ability and item parameters.

  ## Parameters

  - `theta` - Ability estimate
  - `zetas` - List of item parameters
  - `resps` - List of responses (0 or 1)
  """
  def log_likelihood(theta, zetas, resps) do
    Enum.zip(zetas, resps)
    |> Enum.reduce(0.0, fn {zeta, resp}, acc ->
      p = item_response_function(theta, zeta)

      if resp == 1 do
        acc + :math.log(max(p, 1.0e-10))
      else
        acc + :math.log(max(1 - p, 1.0e-10))
      end
    end)
  end

  @doc """
  Generates a normal distribution table.

  Returns a list of {theta, probability} tuples.

  ## Parameters

  - `mean` - Distribution mean
  - `std_dev` - Standard deviation
  - `min` - Minimum theta value
  - `max` - Maximum theta value
  - `step_size` - Grid step size (default: 0.1)
  """
  def normal_distribution(mean \\ 0.0, std_dev \\ 1.0, min \\ -4.0, max \\ 4.0, step_size \\ 0.1) do
    theta_values = generate_range(min, max, step_size)

    Enum.map(theta_values, fn theta ->
      prob =
        1 / (:math.sqrt(2 * :math.pi()) * std_dev) *
          :math.exp(-:math.pow(theta - mean, 2) / (2 * :math.pow(std_dev, 2)))

      {theta, prob}
    end)
  end

  @doc """
  Generates a uniform distribution table.

  Returns a list of {theta, probability} tuples.

  ## Parameters

  - `min_support` - Lower bound of uniform distribution
  - `max_support` - Upper bound of uniform distribution
  - `full_min` - Full range minimum
  - `full_max` - Full range maximum
  - `step_size` - Grid step size (default: 0.1)
  """
  def uniform_distribution(min_support, max_support, full_min, full_max, step_size \\ 0.1) do
    theta_values = generate_range(full_min, full_max, step_size)
    support_values = Enum.filter(theta_values, fn t -> t >= min_support and t <= max_support end)
    prob_mass = 1.0 / length(support_values)

    Enum.map(theta_values, fn theta ->
      prob = if theta >= min_support and theta <= max_support, do: prob_mass, else: 0.0
      {theta, prob}
    end)
  end

  @doc """
  Fills in default zeta parameters for a stimulus.

  Handles both symbolic (a, b, c, d) and semantic (discrimination, difficulty, guessing, slipping) formats.
  """
  def fill_zeta_defaults(zeta) do
    %{
      a: get_param(zeta, :a, :discrimination, 1.0),
      b: get_param(zeta, :b, :difficulty, 0.0),
      c: get_param(zeta, :c, :guessing, 0.0),
      d: get_param(zeta, :d, :slipping, 1.0)
    }
  end

  @doc """
  Gets the difficulty parameter from a stimulus.
  """
  def get_difficulty(zeta) do
    Map.get(zeta, :b) || Map.get(zeta, :difficulty) || 0.0
  end

  @doc """
  Finds the index of the item with difficulty closest to target.

  Assumes stimuli are sorted by difficulty.
  """
  def find_closest_index(stimuli, target) do
    cond do
      length(stimuli) == 0 ->
        0

      target <= get_difficulty(hd(stimuli)) ->
        0

      target >= get_difficulty(List.last(stimuli)) ->
        length(stimuli) - 1

      true ->
        # Binary search for closest
        find_closest_binary(stimuli, target, 0, length(stimuli) - 1)
    end
  end

  # Private functions

  defp get_param(map, key1, key2, default) do
    case Map.get(map, key1) do
      nil -> Map.get(map, key2, default)
      val -> val
    end
  end

  defp generate_range(min, max, step) do
    min_float = if is_float(min), do: min, else: min * 1.0
    n_steps = round((max - min) / step)

    Enum.map(0..n_steps, fn i ->
      Float.round(min_float + i * step, 10)
    end)
  end

  defp find_closest_binary(stimuli, target, low, high) when low >= high do
    # Compare with adjacent indices to find the truly closest
    candidates =
      [low - 1, low, low + 1]
      |> Enum.filter(fn i -> i >= 0 and i < length(stimuli) end)

    Enum.min_by(candidates, fn i ->
      abs(get_difficulty(Enum.at(stimuli, i)) - target)
    end)
  end

  defp find_closest_binary(stimuli, target, low, high) do
    mid = div(low + high, 2)
    mid_val = get_difficulty(Enum.at(stimuli, mid))

    cond do
      mid_val == target -> mid
      mid_val > target -> find_closest_binary(stimuli, target, low, mid - 1)
      true -> find_closest_binary(stimuli, target, mid + 1, high)
    end
  end
end
