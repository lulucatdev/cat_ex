defmodule CatEx.Corpus do
  @moduledoc """
  Corpus management and validation for multi-CAT assessments.

  This module provides utilities for:

  - **Format conversion**: Convert between symbolic (`:a`, `:b`, `:c`, `:d`) and
    semantic (`:discrimination`, `:difficulty`, `:guessing`, `:slipping`) parameter names
  - **Corpus preparation**: Transform flat stimulus data with prefixed parameters
    (e.g., `"math.a"`) into the multi-zeta format used by `CatEx.Clowder`
  - **Validation**: Check for duplicate cat names and redundant parameter keys
  - **Filtering**: Split items by availability of parameters for a specific CAT

  ## Multi-Zeta Format

  Each corpus item is a map with a `:zetas` key listing IRT parameters per CAT:

      %{
        id: "item1",
        stimulus: "What is 2+2?",
        zetas: [
          %{cats: [:math], zeta: %{a: 1.5, b: 0, c: 0.25, d: 1}},
          %{cats: [:reading], zeta: %{a: 0.8, b: -1, c: 0.2, d: 1}}
        ]
      }

  ## Preparing from Flat Data

      items = [%{"math.a" => 1, "math.b" => 0, stimulus: "item1"}]
      corpus = CatEx.Corpus.prepare_clowder_corpus(items, ["math"], ".", :symbolic)
  """

  @zeta_key_map %{
    a: :discrimination,
    b: :difficulty,
    c: :guessing,
    d: :slipping
  }

  @doc """
  Returns default zeta parameters.
  """
  def default_zeta(format \\ :symbolic) do
    default = %{a: 1, b: 0, c: 0, d: 1}
    convert_zeta(default, format)
  end

  @doc """
  Converts zeta parameter values to numbers, filtering out invalid values.
  """
  def ensure_zeta_numeric_values(zeta) do
    zeta
    |> Enum.filter(fn {_, value} ->
      case value do
        nil -> false
        "" -> false
        v when is_binary(v) -> String.upcase(v) != "NA"
        _ -> true
      end
    end)
    |> Enum.map(fn {key, value} ->
      num_value =
        case value do
          v when is_binary(v) ->
            case Float.parse(v) do
              {num, _} -> num
              :error -> nil
            end

          v when is_number(v) ->
            v

          _ ->
            nil
        end

      if num_value != nil and is_finite(num_value) do
        {key, num_value}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  @doc """
  Validates zeta parameters, ensuring no redundant keys.
  """
  def validate_zeta_params(zeta, require_all \\ false) do
    if Map.has_key?(zeta, :a) and Map.has_key?(zeta, :discrimination) do
      raise ArgumentError, "Item has both 'a' and 'discrimination' keys. Provide only one."
    end

    if Map.has_key?(zeta, :b) and Map.has_key?(zeta, :difficulty) do
      raise ArgumentError, "Item has both 'b' and 'difficulty' keys. Provide only one."
    end

    if Map.has_key?(zeta, :c) and Map.has_key?(zeta, :guessing) do
      raise ArgumentError, "Item has both 'c' and 'guessing' keys. Provide only one."
    end

    if Map.has_key?(zeta, :d) and Map.has_key?(zeta, :slipping) do
      raise ArgumentError, "Item has both 'd' and 'slipping' keys. Provide only one."
    end

    if require_all do
      if not (Map.has_key?(zeta, :a) or Map.has_key?(zeta, :discrimination)) do
        raise ArgumentError, "Item is missing 'a' or 'discrimination' key."
      end

      if not (Map.has_key?(zeta, :b) or Map.has_key?(zeta, :difficulty)) do
        raise ArgumentError, "Item is missing 'b' or 'difficulty' key."
      end

      if not (Map.has_key?(zeta, :c) or Map.has_key?(zeta, :guessing)) do
        raise ArgumentError, "Item is missing 'c' or 'guessing' key."
      end

      if not (Map.has_key?(zeta, :d) or Map.has_key?(zeta, :slipping)) do
        raise ArgumentError, "Item is missing 'd' or 'slipping' key."
      end
    end

    :ok
  end

  @doc """
  Fills in default zeta parameters for missing keys.
  """
  def fill_zeta_defaults(zeta, format \\ :symbolic) do
    default = default_zeta(format)
    converted = convert_zeta(zeta, format)

    Map.merge(default, converted)
  end

  @doc """
  Converts zeta parameters between symbolic and semantic formats.
  """
  def convert_zeta(zeta, :symbolic) do
    Map.new(zeta, fn {key, value} ->
      new_key =
        case key do
          :discrimination -> :a
          :difficulty -> :b
          :guessing -> :c
          :slipping -> :d
          k -> k
        end

      {new_key, value}
    end)
  end

  def convert_zeta(zeta, :semantic) do
    Map.new(zeta, fn {key, value} ->
      new_key = Map.get(@zeta_key_map, key, key)
      {new_key, value}
    end)
  end

  def convert_zeta(_zeta, format) do
    raise ArgumentError, "Invalid format: #{format}. Expected :symbolic or :semantic."
  end

  @doc """
  Checks corpus for duplicate cat names.
  """
  def check_no_duplicate_cat_names(corpus) do
    Enum.each(corpus, fn item ->
      cats = Enum.flat_map(item.zetas, & &1.cats)
      unique_cats = Enum.uniq(cats)

      if length(unique_cats) != length(cats) do
        duplicates =
          (cats -- unique_cats)
          |> Enum.uniq()
          |> Enum.join(", ")

        raise ArgumentError, "Duplicate cat names found: #{duplicates}"
      end
    end)

    :ok
  end

  @doc """
  Filters items by availability of parameters for a specific cat.

  Returns `{available, missing}` tuple.
  """
  def filter_items_by_cat_parameter_availability(items, cat_name) do
    {available, missing} =
      Enum.split_with(items, fn item ->
        Enum.any?(item.zetas, fn zeta_cat_map ->
          cat_name in zeta_cat_map.cats
        end)
      end)

    %{available: available, missing: missing}
  end

  @doc """
  Prepares a corpus for Clowder from stimuli items.

  Converts items with cat-specific prefixed parameters into MultiZetaStimulus format.
  """
  def prepare_clowder_corpus(items, cat_names, delimiter \\ ".", format \\ :symbolic) do
    Enum.map(items, fn item ->
      # Extract zetas for each cat
      zetas =
        Enum.flat_map(cat_names, fn cat ->
          prefix = cat <> delimiter

          zeta =
            item
            |> Enum.filter(fn {key, _} -> is_binary(key) and String.starts_with?(key, prefix) end)
            |> Enum.map(fn {key, value} ->
              param_key =
                String.replace_prefix(key, prefix, "")
                |> String.to_atom()

              {param_key, value}
            end)
            |> Map.new()
            |> ensure_zeta_numeric_values()
            |> convert_zeta(format)

          if map_size(zeta) > 0 do
            [%{cats: [cat], zeta: zeta}]
          else
            []
          end
        end)

      # Remove cat-specific keys
      clean_item =
        Enum.reject(item, fn {key, _} ->
          is_binary(key) and
            Enum.any?(cat_names, fn cat ->
              String.starts_with?(key, cat <> delimiter)
            end)
        end)
        |> Map.new()

      Map.put(clean_item, :zetas, zetas)
    end)
  end

  defp is_finite(num) when is_float(num) do
    not (num == :infinity or num == :neg_infinity or num == :nan)
  end

  defp is_finite(num) when is_integer(num), do: true
end
