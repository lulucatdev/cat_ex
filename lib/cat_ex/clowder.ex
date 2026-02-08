defmodule CatEx.Clowder do
  @moduledoc """
  Multi-CAT management for adaptive testing.

  A Clowder manages multiple `CatEx.CAT` instances simultaneously, sharing a
  corpus of stimuli where each item may have different IRT parameters for
  different constructs.

  ## Key Concepts

  - **Named CATs**: Each CAT measures a different construct (e.g., `:reading`, `:math`)
  - **Multi-zeta items**: A single stimulus can have IRT parameters for multiple CATs
  - **Unvalidated items**: Items without IRT parameters, selected randomly
  - **Early stopping**: Automatically checked during each `update_and_select/2` call

  ## Lifecycle

  1. Create a Clowder with `new/1`
  2. Loop: call `update_and_select/2` with responses and get the next item
  3. Check `stopping_reason` to know when to stop

  ## Example

      clowder = CatEx.Clowder.new(
        cats: %{
          reading: [method: "MLE", theta: 0.5],
          math: [method: "EAP", prior_dist: "norm", prior_par: [0, 1]]
        },
        corpus: corpus
      )

      {clowder, next_item} = CatEx.Clowder.update_and_select(clowder,
        cat_to_select: :math,
        cats_to_update: [:math, :reading],
        items: [previous_item],
        answers: [1]
      )

  See the [Multi-CAT guide](clowder-multi-cat.md) for full documentation.
  """

  alias CatEx.CAT
  alias CatEx.Corpus

  defstruct [
    :cats,
    :corpus,
    :remaining_items,
    :seen_items,
    :early_stopping,
    :stopping_reason,
    :random_seed
  ]

  @type t :: %__MODULE__{
          cats: %{atom() => CAT.t()},
          corpus: list(map()),
          remaining_items: list(map()),
          seen_items: list(map()),
          early_stopping: any(),
          stopping_reason: String.t() | nil,
          random_seed: String.t() | nil
        }

  @doc """
  Creates a new Clowder instance.

  ## Options

  - `:cats` - Map of cat names to CAT configuration maps
  - `:corpus` - List of multi-zeta stimuli
  - `:random_seed` - Optional seed for reproducibility
  - `:early_stopping` - Optional early stopping configuration
  """
  def new(opts \\ []) do
    cat_configs = Keyword.get(opts, :cats, %{})
    corpus = Keyword.get(opts, :corpus, [])
    random_seed = Keyword.get(opts, :random_seed)
    early_stopping = Keyword.get(opts, :early_stopping)

    # Validate corpus
    Corpus.check_no_duplicate_cat_names(corpus)

    # Initialize CATs
    cats =
      Map.new(cat_configs, fn {name, config} ->
        # config is already a keyword list, pass it directly to CAT.new
        cat = CAT.new(config)
        {name, cat}
      end)

    # Add unvalidated cat
    unvalidated_cat = CAT.new(item_select: "random", random_seed: random_seed)
    cats = Map.put(cats, :unvalidated, unvalidated_cat)

    %__MODULE__{
      cats: cats,
      corpus: corpus,
      remaining_items: corpus,
      seen_items: [],
      early_stopping: early_stopping,
      stopping_reason: nil,
      random_seed: random_seed
    }
  end

  @doc """
  Updates ability estimates for specified CATs and selects next item.

  ## Parameters

  - `clowder` - Clowder instance
  - `cat_to_select` - CAT to use for selection
  - `cats_to_update` - List of CATs to update (optional)
  - `items` - Previously presented items (optional)
  - `answers` - Corresponding answers (optional)
  - `method` - Optional override method
  - `item_select` - Optional override item selection method
  - `corpus_to_select_from` - Optional corpus to select from

  Returns `{updated_clowder, next_item}` where next_item may be nil.
  """
  def update_and_select(clowder, opts \\ []) do
    # Reset stopping reason for new selection attempt
    clowder = %{clowder | stopping_reason: nil}

    cat_to_select = Keyword.fetch!(opts, :cat_to_select)
    cats_to_update = Keyword.get(opts, :cats_to_update, [])
    items = Keyword.get(opts, :items, [])
    answers = Keyword.get(opts, :answers, [])
    method = Keyword.get(opts, :method)
    item_select = Keyword.get(opts, :item_select)
    corpus_to_select_from = Keyword.get(opts, :corpus_to_select_from, cat_to_select)

    cat_to_evaluate_early_stopping =
      Keyword.get(opts, :cat_to_evaluate_early_stopping, cat_to_select)

    return_undefined_on_exhaustion = Keyword.get(opts, :return_undefined_on_exhaustion, true)

    # Validate inputs
    validate_cat_name!(clowder, cat_to_select, true)
    validate_cat_name!(clowder, corpus_to_select_from, true)

    cats_to_update = if is_list(cats_to_update), do: cats_to_update, else: [cats_to_update]
    Enum.each(cats_to_update, fn cat -> validate_cat_name!(clowder, cat, false) end)

    items = if is_list(items), do: items, else: [items]
    answers = if is_list(answers), do: answers, else: [answers]

    if length(items) != length(answers) do
      raise ArgumentError, "Items and answers must have the same length"
    end

    # Update cats
    clowder = update_cats(clowder, cats_to_update, items, answers, method)

    # Check early stopping
    clowder = check_early_stopping(clowder, cat_to_evaluate_early_stopping)

    # Select next item if not stopped
    if clowder.stopping_reason do
      {clowder, nil}
    else
      next_item =
        select_next_item(
          clowder,
          cat_to_select,
          corpus_to_select_from,
          item_select,
          return_undefined_on_exhaustion
        )

      # Set stopping reason if no item found
      {clowder, next_item} =
        if next_item == nil do
          reason =
            if corpus_to_select_from == :unvalidated do
              "No unvalidated items remaining"
            else
              "No validated items remaining for the requested corpus #{corpus_to_select_from}"
            end

          {%{clowder | stopping_reason: reason}, nil}
        else
          # Clear stopping reason when we successfully get an item
          {%{clowder | stopping_reason: nil}, next_item}
        end

      {clowder, next_item}
    end
  end

  @doc """
  Gets theta estimates for all cats.
  """
  def thetas(clowder) do
    Map.new(clowder.cats, fn {name, cat} -> {name, cat.theta} end)
  end

  @doc """
  Gets SE measurements for all cats.
  """
  def se_measurements(clowder) do
    Map.new(clowder.cats, fn {name, cat} -> {name, cat.se_measurement} end)
  end

  @doc """
  Gets number of items for all cats.
  """
  def n_items(clowder) do
    Map.new(clowder.cats, fn {name, cat} -> {name, CAT.n_items(cat)} end)
  end

  # Private functions

  defp validate_cat_name!(clowder, name, allow_unvalidated) do
    cats = if allow_unvalidated, do: clowder.cats, else: Map.delete(clowder.cats, :unvalidated)

    if not Map.has_key?(cats, name) do
      raise ArgumentError,
            "Invalid cat name: #{name}. Expected one of: #{Enum.join(Map.keys(cats), ", ")}"
    end
  end

  defp update_cats(clowder, cats_to_update, items, answers, _method) do
    # Update seen items and remaining items
    seen_items = clowder.seen_items ++ items

    remaining_items =
      Enum.reject(clowder.remaining_items, fn item ->
        item in items
      end)

    # Update cats with responses
    cats =
      Enum.reduce(cats_to_update, clowder.cats, fn cat_name, acc_cats ->
        # Find items and answers for this cat
        items_for_cat =
          Enum.zip(items, answers)
          |> Enum.filter(fn {item, _} ->
            Enum.any?(item.zetas, fn zeta_map -> cat_name in zeta_map.cats end)
          end)

        if length(items_for_cat) > 0 do
          {zetas, answers_for_cat} =
            Enum.unzip(
              Enum.map(items_for_cat, fn {item, ans} ->
                zeta_map = Enum.find(item.zetas, fn zm -> cat_name in zm.cats end)
                {zeta_map.zeta, ans}
              end)
            )

          cat = Map.get(acc_cats, cat_name)
          updated_cat = CAT.update_ability_estimate(cat, zetas, answers_for_cat)
          Map.put(acc_cats, cat_name, updated_cat)
        else
          acc_cats
        end
      end)

    %{clowder | cats: cats, seen_items: seen_items, remaining_items: remaining_items}
  end

  defp check_early_stopping(clowder, cat_to_evaluate) do
    if clowder.early_stopping do
      # Get cats without unvalidated
      valid_cats = Map.delete(clowder.cats, :unvalidated)

      updated_stopping =
        apply_stopping_update(clowder.early_stopping, valid_cats, cat_to_evaluate)

      if updated_stopping.early_stop do
        %{clowder | early_stopping: updated_stopping, stopping_reason: "Early stopping"}
      else
        %{clowder | early_stopping: updated_stopping}
      end
    else
      clowder
    end
  end

  defp apply_stopping_update(stopping, cats, cat_to_evaluate) do
    module = stopping.__struct__
    apply(module, :update, [stopping, cats, cat_to_evaluate])
  end

  defp select_next_item(
         clowder,
         cat_to_select,
         corpus_to_select_from,
         item_select,
         return_undefined_on_exhaustion
       ) do
    # Filter available items
    %{available: available_for_corpus, missing: missing_for_corpus} =
      Corpus.filter_items_by_cat_parameter_availability(
        clowder.remaining_items,
        corpus_to_select_from
      )

    %{available: available, missing: missing_for_cat} =
      Corpus.filter_items_by_cat_parameter_availability(available_for_corpus, cat_to_select)

    missing = missing_for_corpus ++ missing_for_cat

    result =
      cond do
        corpus_to_select_from == :unvalidated ->
          # Select from unvalidated items
          unvalidated_items =
            Enum.filter(clowder.remaining_items, fn item ->
              item.zetas == [] or Enum.all?(item.zetas, fn zeta_map -> zeta_map.cats == [] end)
            end)

          if length(unvalidated_items) > 0 do
            Enum.random(unvalidated_items)
          else
            # No unvalidated items remaining
            if return_undefined_on_exhaustion do
              nil
            else
              # Return random item from missing
              if length(missing) > 0 do
                Enum.random(missing)
              else
                nil
              end
            end
          end

        length(available) == 0 ->
          if return_undefined_on_exhaustion do
            nil
          else
            # Return random item from missing
            if length(missing) > 0 do
              Enum.random(missing)
            else
              nil
            end
          end

        true ->
          # Convert to stimulus format for the selected cat
          available_cat_input =
            Enum.map(available, fn item ->
              zeta_map = Enum.find(item.zetas, fn zm -> cat_to_select in zm.cats end)
              zeta_map.zeta |> Map.merge(item |> Map.delete(:zetas))
            end)

          cat = Map.get(clowder.cats, cat_to_select)
          {next_stimulus, _} = CAT.find_next_item(cat, available_cat_input, item_select)

          # Find the original multi-zeta stimulus
          Enum.find(clowder.remaining_items, fn item ->
            clean_item = item |> Map.delete(:zetas)

            next_clean =
              next_stimulus
              |> Map.drop([:a, :b, :c, :d, :discrimination, :difficulty, :guessing, :slipping])

            clean_item == next_clean
          end)
      end

    result
  end
end
