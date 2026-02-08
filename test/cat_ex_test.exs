defmodule CatExTest do
  use ExUnit.Case
  doctest CatEx

  alias CatEx.CAT

  describe "CAT basic functionality" do
    test "creates new CAT with default values" do
      cat = CAT.new()
      assert cat.method == "mle"
      assert cat.item_select == "mfi"
      assert cat.theta == 0.0
    end

    test "creates CAT with EAP method" do
      cat = CAT.new(method: "EAP", prior_dist: "norm", prior_par: [0, 1])
      assert cat.method == "eap"
      assert cat.prior_dist == "norm"
    end

    test "updates ability estimate with single response" do
      cat = CAT.new()
      zeta = %{a: 1, b: 0, c: 0, d: 1}
      cat = CAT.update_ability_estimate(cat, zeta, 1)

      assert CAT.n_items(cat) == 1
      assert is_float(cat.theta)
    end

    test "updates ability estimate with multiple responses" do
      cat = CAT.new()
      zetas = [%{a: 1, b: -1, c: 0, d: 1}, %{a: 1, b: 1, c: 0, d: 1}]
      answers = [1, 0]
      cat = CAT.update_ability_estimate(cat, zetas, answers)

      assert CAT.n_items(cat) == 2
    end
  end

  describe "Item selection" do
    test "selects item using MFI" do
      cat = CAT.new()

      stimuli = [
        %{difficulty: -2, discrimination: 1},
        %{difficulty: 0, discrimination: 1},
        %{difficulty: 2, discrimination: 1}
      ]

      {next_item, remaining} = CAT.find_next_item(cat, stimuli)
      assert next_item != nil
      assert length(remaining) == 2
    end

    test "selects random item" do
      cat = CAT.new(item_select: "random")

      stimuli = [
        %{difficulty: -2},
        %{difficulty: 0},
        %{difficulty: 2}
      ]

      {next_item, remaining} = CAT.find_next_item(cat, stimuli)
      assert next_item != nil
      assert length(remaining) == 2
    end

    test "selects closest item" do
      cat = CAT.new(theta: 1.5, item_select: "closest")

      stimuli = [
        %{difficulty: -2},
        %{difficulty: 0},
        %{difficulty: 2}
      ]

      {next_item, _remaining} = CAT.find_next_item(cat, stimuli)
      # Should select the item with difficulty closest to theta + 0.481 ≈ 2
      assert get_in(next_item, [:difficulty]) == 2 or get_in(next_item, [:b]) == 2
    end
  end

  describe "Utils" do
    alias CatEx.Utils

    test "item response function at theta=0" do
      zeta = %{a: 1, b: 0, c: 0, d: 1}
      prob = Utils.item_response_function(0, zeta)
      assert abs(prob - 0.5) < 0.001
    end

    test "fisher information calculation" do
      zeta = %{a: 1, b: 0, c: 0, d: 1}
      fi = Utils.fisher_information(0, zeta)
      assert fi > 0
    end

    test "fills zeta defaults" do
      zeta = %{difficulty: 0.5}
      filled = Utils.fill_zeta_defaults(zeta)
      assert filled.a == 1.0
      assert filled.b == 0.5
      assert filled.c == 0.0
      assert filled.d == 1.0
    end
  end
end
