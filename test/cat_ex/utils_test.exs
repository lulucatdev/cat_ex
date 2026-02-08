defmodule CatEx.UtilsTest do
  use ExUnit.Case
  doctest CatEx.Utils

  alias CatEx.Utils

  describe "item_response_function" do
    test "correctly calculates probability" do
      assert_in_delta Utils.item_response_function(0, %{a: 1, b: -0.3, c: 0.35, d: 1}),
                      0.7234,
                      0.01

      assert_in_delta Utils.item_response_function(0, %{a: 1, b: 0, c: 0, d: 1}), 0.5, 0.01
      assert_in_delta Utils.item_response_function(0, %{a: 0.5, b: 0, c: 0.25, d: 1}), 0.625, 0.01
    end
  end

  describe "fisher_information" do
    test "correctly calculates information" do
      assert_in_delta Utils.fisher_information(0, %{a: 1.53, b: -0.5, c: 0.5, d: 1}), 0.206, 0.01
      assert_in_delta Utils.fisher_information(2.35, %{a: 1, b: 2, c: 0.3, d: 1}), 0.1401, 0.01
    end
  end

  describe "find_closest_index" do
    setup do
      stimuli = [
        %{difficulty: 1, discrimination: 1, guessing: 0.25, slipping: 0.75},
        %{difficulty: 4, discrimination: 1, guessing: 0.25, slipping: 0.75},
        %{difficulty: 10, discrimination: 1, guessing: 0.25, slipping: 0.75},
        %{difficulty: 11, discrimination: 1, guessing: 0.25, slipping: 0.75}
      ]

      %{stimuli: stimuli}
    end

    test "correctly selects first item when target is below all", %{stimuli: stimuli} do
      assert Utils.find_closest_index(stimuli, 0) == 0
    end

    test "correctly selects last item when target is above all", %{stimuli: stimuli} do
      assert Utils.find_closest_index(stimuli, 1000) == 3
    end

    test "correctly selects middle item when exact match", %{stimuli: stimuli} do
      assert Utils.find_closest_index(stimuli, 10) == 2
    end

    test "correctly selects closest when less than", %{stimuli: _} do
      stimuli_with_decimal = [
        %{difficulty: 1.1, discrimination: 1, guessing: 0.25, slipping: 0.75},
        %{difficulty: 4.2, discrimination: 1, guessing: 0.25, slipping: 0.75},
        %{difficulty: 10.3, discrimination: 1, guessing: 0.25, slipping: 0.75},
        %{difficulty: 11.4, discrimination: 1, guessing: 0.25, slipping: 0.75}
      ]

      assert Utils.find_closest_index(stimuli_with_decimal, 5.1) == 1
    end

    test "correctly selects closest when greater than", %{stimuli: _} do
      stimuli_with_decimal = [
        %{difficulty: 1.1, discrimination: 1, guessing: 0.25, slipping: 0.75},
        %{difficulty: 4.2, discrimination: 1, guessing: 0.25, slipping: 0.75},
        %{difficulty: 10.3, discrimination: 1, guessing: 0.25, slipping: 0.75},
        %{difficulty: 11.4, discrimination: 1, guessing: 0.25, slipping: 0.75}
      ]

      assert Utils.find_closest_index(stimuli_with_decimal, 9.1) == 2
    end
  end

  describe "normal_distribution" do
    test "creates normal distribution with default parameters" do
      dist = Utils.normal_distribution()
      assert length(dist) > 0
      assert [{x, y} | _] = dist
      assert is_float(x)
      assert is_float(y)

      # Peak should be at 0
      max_y = Enum.max_by(dist, fn {_, y} -> y end)
      assert_in_delta elem(max_y, 0), 0, 0.1
    end

    test "creates normal distribution with custom mean" do
      dist = Utils.normal_distribution(2, 0.5)
      max_y = Enum.max_by(dist, fn {_, y} -> y end)
      assert_in_delta elem(max_y, 0), 2, 0.1
    end

    test "respects custom min and max range" do
      dist = Utils.normal_distribution(0, 1, -2, 2)
      {min_x, _} = hd(dist)
      {max_x, _} = List.last(dist)
      assert_in_delta min_x, -2, 0.1
      assert_in_delta max_x, 2, 0.1
    end

    test "uses custom step size" do
      dist = Utils.normal_distribution(0, 1, -4, 4, 0.5)
      # Check step size between consecutive points
      dist
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [{x1, _}, {x2, _}] ->
        assert_in_delta x2 - x1, 0.5, 0.001
      end)
    end
  end

  describe "uniform_distribution" do
    test "outputs correct probabilities and boundaries" do
      result = Utils.uniform_distribution(-2, 2, -3, 3, 0.5)
      probs = Enum.map(result, fn {_, p} -> p end)
      xs = Enum.map(result, fn {x, _} -> x end)

      # Probabilities sum to 1
      assert_in_delta Enum.sum(probs), 1.0, 0.0001

      # Boundaries have nonzero probability
      assert Enum.at(probs, Enum.find_index(xs, &(&1 == -2))) > 0
      assert Enum.at(probs, Enum.find_index(xs, &(&1 == 2))) > 0

      # Outside bounds are zero
      assert Enum.at(probs, Enum.find_index(xs, &(&1 == -3))) == 0.0
      assert Enum.at(probs, Enum.find_index(xs, &(&1 == 3))) == 0.0
    end

    test "probabilities are uniform within support" do
      result = Utils.uniform_distribution(-1, 1, -2, 2, 0.5)

      probs_in_support =
        result
        |> Enum.filter(fn {x, _} -> x >= -1 and x <= 1 end)
        |> Enum.map(fn {_, p} -> p end)

      # All probabilities in support should be equal
      first_prob = hd(probs_in_support)

      Enum.each(probs_in_support, fn p ->
        assert_in_delta p, first_prob, 0.0001
      end)
    end
  end

  describe "log_likelihood" do
    test "calculates log likelihood correctly" do
      zetas = [%{a: 1, b: 0, c: 0, d: 1}]
      resps = [1]

      ll = Utils.log_likelihood(0, zetas, resps)
      # At theta=0, item with b=0 gives P=0.5, log(0.5) ≈ -0.693
      assert_in_delta ll, :math.log(0.5), 0.01
    end

    test "handles incorrect responses" do
      zetas = [%{a: 1, b: 0, c: 0, d: 1}]
      resps = [0]

      ll = Utils.log_likelihood(0, zetas, resps)
      # log(1-0.5) = log(0.5)
      assert_in_delta ll, :math.log(0.5), 0.01
    end
  end

  describe "fill_zeta_defaults" do
    test "fills missing parameters with defaults" do
      zeta = %{difficulty: 0.5}
      filled = Utils.fill_zeta_defaults(zeta)

      assert filled.a == 1.0
      assert filled.b == 0.5
      assert filled.c == 0.0
      assert filled.d == 1.0
    end

    test "preserves existing parameters" do
      zeta = %{a: 2, b: 1, c: 0.3, d: 0.9}
      filled = Utils.fill_zeta_defaults(zeta)

      assert filled.a == 2.0
      assert filled.b == 1.0
      assert filled.c == 0.3
      assert filled.d == 0.9
    end
  end

  describe "get_difficulty" do
    test "gets symbolic difficulty" do
      assert Utils.get_difficulty(%{b: 0.5}) == 0.5
    end

    test "gets semantic difficulty" do
      assert Utils.get_difficulty(%{difficulty: 0.5}) == 0.5
    end

    test "defaults to 0 when not found" do
      assert Utils.get_difficulty(%{}) == 0.0
    end
  end
end
