defmodule CatEx.CATTest do
  use ExUnit.Case
  doctest CatEx.CAT

  alias CatEx.CAT

  describe "CAT basic functionality" do
    test "creates new CAT with default values" do
      cat = CAT.new()
      assert cat.method == "mle"
      assert cat.item_select == "mfi"
      assert cat.theta == 0.0
      assert cat.n_start_items == 0
    end

    test "creates CAT with EAP method" do
      cat = CAT.new(method: "EAP", prior_dist: "norm", prior_par: [0, 1])
      assert cat.method == "eap"
      assert cat.prior_dist == "norm"
      assert length(cat.prior) > 0
    end

    test "creates CAT with uniform prior" do
      cat = CAT.new(method: "EAP", prior_dist: "unif", prior_par: [-4, 4])
      assert cat.method == "eap"
      assert cat.prior_dist == "unif"
    end

    test "updates ability estimate with single response (MLE)" do
      cat = CAT.new()
      cat = CAT.update_ability_estimate(cat, %{a: 1, b: 0, c: 0, d: 1}, 1)

      assert CAT.n_items(cat) == 1
      assert is_float(cat.theta)
      # Should be positive after correct response
      assert cat.theta > 0
    end

    test "updates ability estimate with multiple responses (MLE)" do
      cat = CAT.new()

      zetas = [
        %{a: 2.225, b: -1.885, c: 0.21, d: 1},
        %{a: 1.174, b: -2.411, c: 0.212, d: 1},
        %{a: 2.104, b: -2.439, c: 0.192, d: 1}
      ]

      cat = CAT.update_ability_estimate(cat, zetas, [1, 0, 1])

      assert CAT.n_items(cat) == 3
      assert_in_delta cat.theta, -1.64, 0.1
      assert cat.se_measurement > 0
    end

    test "correctly updates ability estimate with different items" do
      cat = CAT.new()

      zetas = [
        %{a: 1, b: -0.447, c: 0.5, d: 1},
        %{a: 1, b: 2.869, c: 0.5, d: 1},
        %{a: 1, b: -0.469, c: 0.5, d: 1},
        %{a: 1, b: -0.576, c: 0.5, d: 1},
        %{a: 1, b: -1.43, c: 0.5, d: 1},
        %{a: 1, b: -1.607, c: 0.5, d: 1},
        %{a: 1, b: 0.529, c: 0.5, d: 1}
      ]

      cat = CAT.update_ability_estimate(cat, zetas, [0, 1, 0, 1, 1, 1, 1])

      assert CAT.n_items(cat) == 7
      assert_in_delta cat.theta, -1.27, 0.1
      assert_in_delta cat.se_measurement, 1.71, 0.1
    end

    test "correctly updates ability estimate through EAP" do
      cat = CAT.new(method: "EAP")

      cat =
        CAT.update_ability_estimate(
          cat,
          [
            %{a: 1, b: -4.0, c: 0.5, d: 1},
            %{a: 1, b: -3.0, c: 0.5, d: 1}
          ],
          [0, 0]
        )

      # EAP should be less extreme than MLE
      assert_in_delta cat.theta, -1.65, 0.1
    end

    test "updates ability estimate with EAP uniform prior" do
      cat =
        CAT.new(
          method: "EAP",
          prior_dist: "unif",
          prior_par: [-4, 4],
          min_theta: -6,
          max_theta: 6
        )

      cat =
        CAT.update_ability_estimate(
          cat,
          [
            %{a: 1, b: -4.0, c: 0.5, d: 1},
            %{a: 1, b: -3.0, c: 0.5, d: 1}
          ],
          [0, 0]
        )

      # Should be negative after incorrect responses to easy items
      assert cat.theta < 0
    end

    test "theta estimate increases with correct response to easy item (EAP norm)" do
      cat = CAT.new(method: "EAP")

      cat =
        CAT.update_ability_estimate(
          cat,
          [
            %{a: 1, b: -4.0, c: 0.5, d: 1},
            %{a: 1, b: -3.0, c: 0.5, d: 1}
          ],
          [0, 0]
        )

      initial_theta = cat.theta

      cat = CAT.update_ability_estimate(cat, %{a: 1, b: -2.5, c: 0.2, d: 1}, 1)

      # Theta should increase after correct response
      assert cat.theta > initial_theta
    end

    test "throws error if zeta and answers length mismatch" do
      cat = CAT.new()

      assert_raise ArgumentError, ~r/Unmatched length/, fn ->
        CAT.update_ability_estimate(cat, [%{a: 1, b: 0}, %{a: 1, b: 0}], [1, 0, 1])
      end
    end

    test "throws error for invalid method" do
      assert_raise ArgumentError, ~r/Invalid method/, fn ->
        CAT.new(method: "invalid")
      end
    end

    test "throws error for invalid item_select" do
      assert_raise ArgumentError, ~r/Invalid item selector/, fn ->
        CAT.new(item_select: "invalid")
      end

      cat = CAT.new()

      assert_raise ArgumentError, ~r/Invalid item selector/, fn ->
        CAT.find_next_item(cat, [], "invalid")
      end
    end

    test "throws error for invalid start_select" do
      assert_raise ArgumentError, ~r/Invalid start selector/, fn ->
        CAT.new(start_select: "invalid")
      end
    end

    test "validates prior parameters" do
      # Normal prior with non-positive std dev
      assert_raise ArgumentError, ~r/positive.*standard deviation/, fn ->
        CAT.new(method: "EAP", prior_dist: "norm", prior_par: [0, -1])
      end

      # Normal prior with mean outside theta bounds
      assert_raise ArgumentError, ~r/prior distribution mean/, fn ->
        CAT.new(
          method: "EAP",
          prior_dist: "norm",
          prior_par: [10, 1],
          min_theta: -6,
          max_theta: 6
        )
      end

      # Uniform prior with min >= max
      assert_raise ArgumentError, ~r/Invalid uniform bounds/, fn ->
        CAT.new(method: "EAP", prior_dist: "unif", prior_par: [2, 1])
      end

      # Uniform prior with bounds outside theta range
      assert_raise ArgumentError, ~r/within theta bounds/, fn ->
        CAT.new(
          method: "EAP",
          prior_dist: "unif",
          prior_par: [-10, 10],
          min_theta: -6,
          max_theta: 6
        )
      end

      # Wrong number of prior parameters
      assert_raise ArgumentError, ~r/two numbers/, fn ->
        CAT.new(method: "EAP", prior_dist: "norm", prior_par: [0])
      end
    end

    test "accepts valid prior parameters" do
      # Valid normal prior
      cat = CAT.new(method: "EAP", prior_dist: "norm", prior_par: [0, 1])
      assert cat.prior_dist == "norm"

      # Normal prior at boundaries
      cat =
        CAT.new(
          method: "EAP",
          prior_dist: "norm",
          prior_par: [-6, 1],
          min_theta: -6,
          max_theta: 6
        )

      assert cat.prior_dist == "norm"

      cat =
        CAT.new(method: "EAP", prior_dist: "norm", prior_par: [6, 1], min_theta: -6, max_theta: 6)

      assert cat.prior_dist == "norm"

      # Valid uniform prior
      cat = CAT.new(method: "EAP", prior_dist: "unif", prior_par: [-2, 2])
      assert cat.prior_dist == "unif"
    end

    test "handles empty stimuli in find_next_item" do
      cat = CAT.new()
      {next_stimulus, _} = CAT.find_next_item(cat, [])

      assert next_stimulus == nil
    end
  end

  describe "Item selection methods" do
    setup do
      s1 = %{difficulty: 0.5, guessing: 0.5, discrimination: 1, slipping: 1, word: "looking"}
      s2 = %{difficulty: 3.5, guessing: 0.5, discrimination: 1, slipping: 1, word: "opaque"}
      s3 = %{difficulty: 2, guessing: 0.5, discrimination: 1, slipping: 1, word: "right"}
      s4 = %{difficulty: -2.5, guessing: 0.5, discrimination: 1, slipping: 1, word: "yes"}
      s5 = %{difficulty: -1.8, guessing: 0.5, discrimination: 1, slipping: 1, word: "mom"}
      stimuli = [s1, s2, s3, s4, s5]

      cat = CAT.new()

      cat =
        CAT.update_ability_estimate(
          cat,
          [
            %{a: 2.225, b: -1.885, c: 0.21, d: 1},
            %{a: 1.174, b: -2.411, c: 0.212, d: 1},
            %{a: 2.104, b: -2.439, c: 0.192, d: 1}
          ],
          [1, 0, 1]
        )

      %{stimuli: stimuli, cat: cat}
    end

    test "correctly suggests next item with MFI method", %{stimuli: stimuli} do
      cat = CAT.new(n_start_items: 0)

      {next_stimulus, remaining} = CAT.find_next_item(cat, stimuli, "MFI")

      assert next_stimulus != nil
      assert length(remaining) == 4
    end

    test "correctly suggests next item with closest method", %{stimuli: stimuli, cat: cat} do
      {next_stimulus, remaining} = CAT.find_next_item(cat, stimuli, "closest")

      # With theta around -1.64, closest should be s5 (difficulty -1.8)
      assert next_stimulus.word == "mom"
      assert length(remaining) == 4
    end

    test "correctly suggests next item with fixed method", %{stimuli: stimuli} do
      cat = CAT.new(n_start_items: 0, item_select: "fixed")

      {next_stimulus, remaining} = CAT.find_next_item(cat, stimuli)

      assert next_stimulus.word == "looking"
      assert length(remaining) == 4
    end

    test "correctly suggests next item with random method", %{stimuli: stimuli} do
      cat = CAT.new(n_start_items: 0, item_select: "random")

      {next_stimulus, remaining} = CAT.find_next_item(cat, stimuli)

      assert next_stimulus != nil
      assert length(remaining) == 4
    end

    test "respects n_start_items with middle method", %{stimuli: stimuli} do
      cat = CAT.new(n_start_items: 1, start_select: "middle")

      {next_stimulus, _} = CAT.find_next_item(cat, stimuli)

      assert next_stimulus != nil
    end
  end

  describe "Prior distribution" do
    test "creates prior with correct number of points" do
      cat = CAT.new(method: "EAP", min_theta: -3, max_theta: 3)
      # Default step size 0.1, range -3 to 3 = 61 points
      assert length(cat.prior) == 61
    end

    test "creates prior with correct step intervals" do
      cat = CAT.new(method: "EAP", min_theta: -1, max_theta: 1)

      cat.prior
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [{x1, _}, {x2, _}] ->
        assert_in_delta x2 - x1, 0.1, 0.000001
      end)
    end

    test "creates uniform prior distribution" do
      cat =
        CAT.new(
          method: "EAP",
          prior_dist: "unif",
          prior_par: [-2, 2],
          min_theta: -3,
          max_theta: 3
        )

      assert cat.prior_dist == "unif"

      probs = Enum.map(cat.prior, fn {_, p} -> p end)
      xs = Enum.map(cat.prior, fn {x, _} -> x end)

      # Probabilities within bounds should be equal
      in_bounds =
        probs
        |> Enum.zip(xs)
        |> Enum.filter(fn {_, x} -> x >= -2 and x <= 2 end)
        |> Enum.map(fn {p, _} -> p end)

      first_prob = hd(in_bounds)

      Enum.each(in_bounds, fn p ->
        assert_in_delta p, first_prob, 0.000001
      end)

      # Points outside bounds should have zero probability
      outside =
        probs
        |> Enum.zip(xs)
        |> Enum.filter(fn {_, x} -> x < -2 or x > 2 end)
        |> Enum.map(fn {p, _} -> p end)

      Enum.each(outside, fn p ->
        assert p == 0.0
      end)

      # Total probability should sum to 1
      assert_in_delta Enum.sum(probs), 1.0, 0.000001
    end

    test "uses default prior parameters for uniform" do
      cat = CAT.new(method: "EAP", prior_dist: "unif")

      assert cat.prior_dist == "unif"
      assert cat.prior_par == [-4, 4]
    end

    test "throws error for invalid prior distribution" do
      assert_raise ArgumentError, ~r/priorDist must be.*unif or.*norm/, fn ->
        CAT.new(method: "EAP", prior_dist: "invalid", prior_par: [0, 1])
      end
    end
  end
end
