defmodule CatEx.Stopping do
  @moduledoc """
  Early stopping mechanisms for Computer Adaptive Testing.

  This module provides three strategies for determining when to stop testing,
  each supporting logical operations (`:and`, `:or`, `:only`) for combining
  conditions across multiple CATs.

  ## Strategies

  | Module | Triggers When |
  |--------|---------------|
  | `StopAfterNItems` | A specified number of items have been administered |
  | `StopOnSEPlateau` | Standard error stabilizes (stops decreasing) |
  | `StopIfSEBelowThreshold` | Standard error drops below a target precision |

  ## Logical Operations

  | Operation | Behavior |
  |-----------|----------|
  | `:or` | Stop when **any** CAT meets its condition (default) |
  | `:and` | Stop when **all** CATs meet their conditions |
  | `:only` | Evaluate **only** the specified `cat_to_evaluate` |

  ## Examples

      # Stop after 20 items (any cat)
      stopping = CatEx.Stopping.StopAfterNItems.new(%{cat1: 20, cat2: 20})

      # Stop when SE plateaus (both cats must plateau)
      stopping = CatEx.Stopping.StopOnSEPlateau.new(
        %{cat1: 5, cat2: 5},        # patience
        %{cat1: 0.01, cat2: 0.01},  # tolerance
        logical_operation: :and
      )

      # Stop when SE is precise enough
      stopping = CatEx.Stopping.StopIfSEBelowThreshold.new(
        %{cat1: 0.3},
        patience: %{cat1: 3},
        tolerance: %{cat1: 0.05}
      )

  See the [Early Stopping guide](early-stopping.md) for full documentation.
  """

  alias CatEx.CAT

  defmodule StopAfterNItems do
    @moduledoc """
    Stop after administering a specified number of items.
    """

    defstruct [
      :required_items,
      :n_items,
      :early_stop,
      :logical_operation
    ]

    @type t :: %__MODULE__{
            required_items: %{String.t() => non_neg_integer()},
            n_items: %{String.t() => non_neg_integer()},
            early_stop: boolean(),
            logical_operation: :and | :or | :only
          }

    def new(required_items, opts \\ []) do
      logical_op = Keyword.get(opts, :logical_operation, :or)

      %__MODULE__{
        required_items: required_items,
        n_items: %{},
        early_stop: false,
        logical_operation: validate_logical_operation(logical_op)
      }
    end

    def update(%__MODULE__{} = stopping, cats, cat_to_evaluate \\ nil) do
      # Update n_items for each cat
      n_items =
        Map.new(cats, fn {name, cat} ->
          {name, CAT.n_items(cat)}
        end)

      stopping = %{stopping | n_items: n_items}

      # Evaluate stopping condition as a map of {cat_name => boolean}
      conditions =
        Map.new(stopping.required_items, fn {cat_name, required} ->
          actual = Map.get(n_items, cat_name, 0)
          {cat_name, actual >= required}
        end)

      early_stop = evaluate_conditions(conditions, stopping.logical_operation, cat_to_evaluate)

      %{stopping | early_stop: early_stop}
    end

    def evaluation_cats(%__MODULE__{} = stopping) do
      Map.keys(stopping.required_items)
    end

    defp validate_logical_operation(op) when op in [:and, :or, :only, "and", "or", "only"] do
      case op do
        :and -> :and
        :or -> :or
        :only -> :only
        "and" -> :and
        "or" -> :or
        "only" -> :only
      end
    end

    defp validate_logical_operation(op) do
      raise ArgumentError, "Invalid logical operation: #{op}. Expected :and, :or, or :only."
    end

    defp evaluate_conditions(conditions, :and, _),
      do: Enum.all?(Map.values(conditions))

    defp evaluate_conditions(conditions, :or, _),
      do: Enum.any?(Map.values(conditions))

    defp evaluate_conditions(_, :only, nil),
      do: raise(ArgumentError, "Must provide cat_to_evaluate for :only operation")

    defp evaluate_conditions(conditions, :only, cat),
      do: Map.get(conditions, cat, false)
  end

  defmodule StopOnSEPlateau do
    @moduledoc """
    Stop when the standard error of measurement remains stable.
    """

    defstruct [
      :patience,
      :tolerance,
      :se_measurements,
      :n_items,
      :early_stop,
      :logical_operation
    ]

    @type t :: %__MODULE__{
            patience: %{String.t() => non_neg_integer()},
            tolerance: %{String.t() => float()},
            se_measurements: %{String.t() => list(float())},
            n_items: %{String.t() => non_neg_integer()},
            early_stop: boolean(),
            logical_operation: :and | :or | :only
          }

    def new(patience, tolerance \\ %{}, opts \\ []) do
      logical_op = Keyword.get(opts, :logical_operation, :or)

      %__MODULE__{
        patience: patience,
        tolerance: tolerance,
        se_measurements: %{},
        n_items: %{},
        early_stop: false,
        logical_operation: validate_logical_operation(logical_op)
      }
    end

    def update(%__MODULE__{} = stopping, cats, cat_to_evaluate \\ nil) do
      # Update state for each cat
      {n_items, se_measurements} =
        Enum.reduce(cats, {%{}, %{}}, fn {name, cat}, {n_acc, se_acc} ->
          n = CAT.n_items(cat)
          se = cat.se_measurement

          prev_n = Map.get(stopping.n_items, name, 0)

          if n > prev_n do
            prev_se = Map.get(stopping.se_measurements, name, [])
            {Map.put(n_acc, name, n), Map.put(se_acc, name, prev_se ++ [se])}
          else
            {Map.put(n_acc, name, n),
             Map.put(se_acc, name, Map.get(stopping.se_measurements, name, []))}
          end
        end)

      stopping = %{stopping | n_items: n_items, se_measurements: se_measurements}

      # Evaluate stopping conditions as a map of {cat_name => boolean}
      conditions =
        Map.new(stopping.patience, fn {cat_name, patience_val} ->
          se_list = Map.get(se_measurements, cat_name, [])
          tolerance = Map.get(stopping.tolerance, cat_name, 0.0)

          result =
            if length(se_list) >= patience_val do
              recent_se = Enum.take(se_list, -patience_val)
              mean = Enum.sum(recent_se) / patience_val
              Enum.all?(recent_se, fn se -> abs(se - mean) <= tolerance end)
            else
              false
            end

          {cat_name, result}
        end)

      early_stop = evaluate_conditions(conditions, stopping.logical_operation, cat_to_evaluate)

      %{stopping | early_stop: early_stop}
    end

    def evaluation_cats(%__MODULE__{} = stopping) do
      (Map.keys(stopping.patience) ++ Map.keys(stopping.tolerance))
      |> Enum.uniq()
    end

    defp validate_logical_operation(op) when op in [:and, :or, :only, "and", "or", "only"] do
      case op do
        :and -> :and
        :or -> :or
        :only -> :only
        "and" -> :and
        "or" -> :or
        "only" -> :only
      end
    end

    defp validate_logical_operation(op) do
      raise ArgumentError, "Invalid logical operation: #{op}. Expected :and, :or, or :only."
    end

    defp evaluate_conditions(conditions, :and, _),
      do: Enum.all?(Map.values(conditions))

    defp evaluate_conditions(conditions, :or, _),
      do: Enum.any?(Map.values(conditions))

    defp evaluate_conditions(_, :only, nil),
      do: raise(ArgumentError, "Must provide cat_to_evaluate for :only operation")

    defp evaluate_conditions(conditions, :only, cat),
      do: Map.get(conditions, cat, false)
  end

  defmodule StopIfSEBelowThreshold do
    @moduledoc """
    Stop when the standard error of measurement drops below a threshold.
    """

    defstruct [
      :se_threshold,
      :patience,
      :tolerance,
      :se_measurements,
      :n_items,
      :early_stop,
      :logical_operation
    ]

    @type t :: %__MODULE__{
            se_threshold: %{String.t() => float()},
            patience: %{String.t() => non_neg_integer()},
            tolerance: %{String.t() => float()},
            se_measurements: %{String.t() => list(float())},
            n_items: %{String.t() => non_neg_integer()},
            early_stop: boolean(),
            logical_operation: :and | :or | :only
          }

    def new(se_threshold, opts \\ []) do
      patience = Keyword.get(opts, :patience, %{})
      tolerance = Keyword.get(opts, :tolerance, %{})
      logical_op = Keyword.get(opts, :logical_operation, :or)

      %__MODULE__{
        se_threshold: se_threshold,
        patience: patience,
        tolerance: tolerance,
        se_measurements: %{},
        n_items: %{},
        early_stop: false,
        logical_operation: validate_logical_operation(logical_op)
      }
    end

    def update(%__MODULE__{} = stopping, cats, cat_to_evaluate \\ nil) do
      # Update state
      {n_items, se_measurements} =
        Enum.reduce(cats, {%{}, %{}}, fn {name, cat}, {n_acc, se_acc} ->
          n = CAT.n_items(cat)
          se = cat.se_measurement

          prev_n = Map.get(stopping.n_items, name, 0)

          if n > prev_n do
            prev_se = Map.get(stopping.se_measurements, name, [])
            {Map.put(n_acc, name, n), Map.put(se_acc, name, prev_se ++ [se])}
          else
            {Map.put(n_acc, name, n),
             Map.put(se_acc, name, Map.get(stopping.se_measurements, name, []))}
          end
        end)

      stopping = %{stopping | n_items: n_items, se_measurements: se_measurements}

      # Evaluate conditions for all evaluation cats (union of threshold/patience/tolerance keys)
      all_cats = evaluation_cats(stopping)

      conditions =
        Map.new(all_cats, fn cat_name ->
          threshold = Map.get(stopping.se_threshold, cat_name, 0)
          se_list = Map.get(se_measurements, cat_name, [])
          patience = Map.get(stopping.patience, cat_name, 1)
          tolerance = Map.get(stopping.tolerance, cat_name, 0.0)

          result =
            if length(se_list) >= patience do
              recent_se = Enum.take(se_list, -patience)
              Enum.all?(recent_se, fn se -> se - threshold <= tolerance end)
            else
              false
            end

          {cat_name, result}
        end)

      early_stop = evaluate_conditions(conditions, stopping.logical_operation, cat_to_evaluate)

      %{stopping | early_stop: early_stop}
    end

    def evaluation_cats(%__MODULE__{} = stopping) do
      (Map.keys(stopping.se_threshold) ++
         Map.keys(stopping.patience) ++ Map.keys(stopping.tolerance))
      |> Enum.uniq()
    end

    defp validate_logical_operation(op) when op in [:and, :or, :only, "and", "or", "only"] do
      case op do
        :and -> :and
        :or -> :or
        :only -> :only
        "and" -> :and
        "or" -> :or
        "only" -> :only
      end
    end

    defp validate_logical_operation(op) do
      raise ArgumentError, "Invalid logical operation: #{op}. Expected :and, :or, or :only."
    end

    defp evaluate_conditions(conditions, :and, _),
      do: Enum.all?(Map.values(conditions))

    defp evaluate_conditions(conditions, :or, _),
      do: Enum.any?(Map.values(conditions))

    defp evaluate_conditions(_, :only, nil),
      do: raise(ArgumentError, "Must provide cat_to_evaluate for :only operation")

    defp evaluate_conditions(conditions, :only, cat),
      do: Map.get(conditions, cat, false)
  end
end
