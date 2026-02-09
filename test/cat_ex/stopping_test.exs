defmodule CatEx.StoppingTest do
  use ExUnit.Case
  doctest CatEx.Stopping

  alias CatEx.Stopping

  defmodule MockCat do
    defstruct [:n_items, :se_measurement]
  end

  describe "StopAfterNItems" do
    test "instantiates with input parameters" do
      stopping = Stopping.StopAfterNItems.new(%{cat1: 2, cat2: 3}, logical_operation: :or)

      assert stopping.required_items == %{cat1: 2, cat2: 3}
      assert stopping.logical_operation == :or
      assert stopping.early_stop == false
    end

    test "validates logical operation" do
      # Valid operations
      _ = Stopping.StopAfterNItems.new(%{cat1: 2}, logical_operation: :and)
      _ = Stopping.StopAfterNItems.new(%{cat1: 2}, logical_operation: :or)
      _ = Stopping.StopAfterNItems.new(%{cat1: 2}, logical_operation: :only)

      # Invalid operation
      assert_raise ArgumentError, ~r/Invalid logical operation/, fn ->
        Stopping.StopAfterNItems.new(%{cat1: 2}, logical_operation: :invalid)
      end
    end

    test "updates internal state" do
      stopping = Stopping.StopAfterNItems.new(%{cat1: 2, cat2: 3})

      cats = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.5},
        cat2: %MockCat{n_items: 1, se_measurement: 0.3}
      }

      stopping = Stopping.StopAfterNItems.update(stopping, cats)

      assert stopping.n_items.cat1 == 1
      assert stopping.n_items.cat2 == 1
    end

    test "stops when required items reached with OR operation" do
      stopping = Stopping.StopAfterNItems.new(%{cat1: 2, cat2: 3}, logical_operation: :or)

      cats1 = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.5},
        cat2: %MockCat{n_items: 1, se_measurement: 0.3}
      }

      stopping = Stopping.StopAfterNItems.update(stopping, cats1)
      assert stopping.early_stop == false

      # cat2 reaches required items
      cats2 = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.5},
        cat2: %MockCat{n_items: 3, se_measurement: 0.3}
      }

      stopping = Stopping.StopAfterNItems.update(stopping, cats2)
      assert stopping.early_stop == true
    end

    test "stops only when all required with AND operation" do
      stopping = Stopping.StopAfterNItems.new(%{cat1: 2, cat2: 3}, logical_operation: :and)

      cats1 = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.5},
        cat2: %MockCat{n_items: 1, se_measurement: 0.3}
      }

      stopping = Stopping.StopAfterNItems.update(stopping, cats1)
      assert stopping.early_stop == false

      # cat2 reaches required items, but cat1 hasn't
      cats2 = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.5},
        cat2: %MockCat{n_items: 3, se_measurement: 0.3}
      }

      stopping = Stopping.StopAfterNItems.update(stopping, cats2)
      assert stopping.early_stop == false

      # Both reach required items
      cats3 = %{
        cat1: %MockCat{n_items: 2, se_measurement: 0.5},
        cat2: %MockCat{n_items: 3, se_measurement: 0.3}
      }

      stopping = Stopping.StopAfterNItems.update(stopping, cats3)
      assert stopping.early_stop == true
    end

    test "does not stop when items don't increment" do
      stopping = Stopping.StopAfterNItems.new(%{cat1: 2, cat2: 3})

      cats = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.5},
        cat2: %MockCat{n_items: 2, se_measurement: 0.3}
      }

      stopping = Stopping.StopAfterNItems.update(stopping, cats)
      assert stopping.early_stop == false

      # Update with same n_items (shouldn't increment internal counter)
      stopping = Stopping.StopAfterNItems.update(stopping, cats)
      assert stopping.early_stop == false
    end

    test "evaluation_cats returns required items keys" do
      stopping = Stopping.StopAfterNItems.new(%{cat1: 2, cat2: 3})
      cats = Stopping.StopAfterNItems.evaluation_cats(stopping)

      assert Enum.sort(cats) == [:cat1, :cat2]
    end
  end

  describe "StopOnSEPlateau" do
    test "instantiates with input parameters" do
      stopping =
        Stopping.StopOnSEPlateau.new(
          %{cat1: 2, cat2: 3},
          %{cat1: 0.01, cat2: 0.02},
          logical_operation: :or
        )

      assert stopping.patience == %{cat1: 2, cat2: 3}
      assert stopping.tolerance == %{cat1: 0.01, cat2: 0.02}
      assert stopping.logical_operation == :or
    end

    test "updates internal state" do
      stopping = Stopping.StopOnSEPlateau.new(%{cat1: 2, cat2: 3}, %{cat1: 0.01, cat2: 0.02})

      cats = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.5},
        cat2: %MockCat{n_items: 1, se_measurement: 0.3}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats)

      assert stopping.n_items.cat1 == 1
      assert stopping.se_measurements.cat1 == [0.5]
      assert stopping.n_items.cat2 == 1
      assert stopping.se_measurements.cat2 == [0.3]

      # Second update
      cats2 = %{
        cat1: %MockCat{n_items: 2, se_measurement: 0.5},
        cat2: %MockCat{n_items: 2, se_measurement: 0.3}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats2)

      assert stopping.n_items.cat1 == 2
      assert stopping.se_measurements.cat1 == [0.5, 0.5]
    end

    test "stops when SE measurement plateaus with OR operation" do
      stopping =
        Stopping.StopOnSEPlateau.new(
          %{cat1: 2, cat2: 3},
          %{cat1: 0.01, cat2: 0.02},
          logical_operation: :or
        )

      cats1 = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.5},
        cat2: %MockCat{n_items: 1, se_measurement: 0.3}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats1)
      assert stopping.early_stop == false

      # cat1 SE plateaus (same value for 2 items)
      cats2 = %{
        cat1: %MockCat{n_items: 2, se_measurement: 0.5},
        cat2: %MockCat{n_items: 2, se_measurement: 0.3}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats2)
      assert stopping.early_stop == true
    end

    test "does not stop when SE measurement not plateaued" do
      stopping =
        Stopping.StopOnSEPlateau.new(
          %{cat1: 2, cat2: 3},
          %{cat1: 0.01, cat2: 0.02},
          logical_operation: :or
        )

      cats = %{
        cat1: %MockCat{n_items: 1, se_measurement: 100},
        cat2: %MockCat{n_items: 1, se_measurement: 100}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats)

      cats = %{
        cat1: %MockCat{n_items: 2, se_measurement: 10},
        cat2: %MockCat{n_items: 2, se_measurement: 10}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats)

      cats = %{
        cat1: %MockCat{n_items: 3, se_measurement: 1},
        cat2: %MockCat{n_items: 3, se_measurement: 1}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats)

      # SE is still decreasing, not plateaued
      assert stopping.early_stop == false
    end

    test "waits for patience items to monitor plateau" do
      stopping =
        Stopping.StopOnSEPlateau.new(
          %{cat1: 2, cat2: 3},
          %{cat1: 0.01, cat2: 0.02},
          logical_operation: :and
        )

      cats = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.5},
        cat2: %MockCat{n_items: 1, se_measurement: 0.3}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats)

      cats = %{
        cat1: %MockCat{n_items: 2, se_measurement: 0.5},
        cat2: %MockCat{n_items: 2, se_measurement: 0.3}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats)
      # cat2 hasn't reached patience of 3 yet
      assert stopping.early_stop == false

      cats = %{
        cat1: %MockCat{n_items: 3, se_measurement: 0.5},
        cat2: %MockCat{n_items: 3, se_measurement: 0.3}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats)
      # Both have plateaued for their patience periods
      assert stopping.early_stop == true
    end

    test "triggers when within tolerance" do
      stopping =
        Stopping.StopOnSEPlateau.new(
          %{cat1: 3},
          %{cat1: 0.01},
          logical_operation: :or
        )

      cats = %{
        cat1: %MockCat{n_items: 1, se_measurement: 10}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats)

      cats = %{
        cat1: %MockCat{n_items: 2, se_measurement: 1}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats)

      cats = %{
        cat1: %MockCat{n_items: 3, se_measurement: 0.99}
      }

      _stopping = Stopping.StopOnSEPlateau.update(stopping, cats)

      # 0.99 is within 0.01 of mean (10 + 1 + 0.99) / 3 = 3.996
      # mean of last 3: (10 + 1 + 0.99) / 3 = 3.996... wait that's not right
      # Recent 3: [10, 1, 0.99], mean = 3.996, not within 0.01
      # Let me recalculate: need measurements within tolerance of each other

      # Actually test with measurements that are close together
      stopping2 =
        Stopping.StopOnSEPlateau.new(
          %{cat1: 3},
          %{cat1: 0.1},
          logical_operation: :or
        )

      stopping2 =
        Stopping.StopOnSEPlateau.update(stopping2, %{
          cat1: %MockCat{n_items: 1, se_measurement: 0.5}
        })

      stopping2 =
        Stopping.StopOnSEPlateau.update(stopping2, %{
          cat1: %MockCat{n_items: 2, se_measurement: 0.5}
        })

      stopping2 =
        Stopping.StopOnSEPlateau.update(stopping2, %{
          cat1: %MockCat{n_items: 3, se_measurement: 0.5}
        })

      # All 3 measurements are 0.5 (within 0.1 of each other)
      assert stopping2.early_stop == true
    end

    test "handles AND operation" do
      stopping =
        Stopping.StopOnSEPlateau.new(
          %{cat1: 2, cat2: 3},
          %{cat1: 0.01, cat2: 0.02},
          logical_operation: :and
        )

      cats1 = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.5},
        cat2: %MockCat{n_items: 1, se_measurement: 0.3}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats1)
      assert stopping.early_stop == false

      # cat1 plateaus but cat2 hasn't
      cats2 = %{
        cat1: %MockCat{n_items: 2, se_measurement: 0.5},
        cat2: %MockCat{n_items: 2, se_measurement: 0.3}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats2)
      assert stopping.early_stop == false

      # Both plateau
      cats3 = %{
        cat1: %MockCat{n_items: 3, se_measurement: 0.5},
        cat2: %MockCat{n_items: 3, se_measurement: 0.3}
      }

      stopping = Stopping.StopOnSEPlateau.update(stopping, cats3)
      assert stopping.early_stop == true
    end
  end

  describe "StopIfSEBelowThreshold" do
    test "instantiates with input parameters" do
      stopping =
        Stopping.StopIfSEBelowThreshold.new(
          %{cat1: 0.03, cat2: 0.02},
          patience: %{cat1: 1, cat2: 3},
          tolerance: %{cat1: 0.01, cat2: 0.02},
          logical_operation: :or
        )

      assert stopping.se_threshold == %{cat1: 0.03, cat2: 0.02}
      assert stopping.patience == %{cat1: 1, cat2: 3}
      assert stopping.tolerance == %{cat1: 0.01, cat2: 0.02}
      assert stopping.logical_operation == :or
    end

    test "stops when SE falls below threshold" do
      stopping =
        Stopping.StopIfSEBelowThreshold.new(
          %{cat1: 0.03, cat2: 0.02},
          patience: %{cat1: 1, cat2: 3},
          tolerance: %{cat1: 0.01, cat2: 0.02},
          logical_operation: :or
        )

      cats = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.5},
        cat2: %MockCat{n_items: 1, se_measurement: 0.3}
      }

      stopping = Stopping.StopIfSEBelowThreshold.update(stopping, cats)
      assert stopping.early_stop == false

      # cat1 SE falls below threshold of 0.03
      cats = %{
        cat1: %MockCat{n_items: 2, se_measurement: 0.02},
        cat2: %MockCat{n_items: 2, se_measurement: 0.3}
      }

      stopping = Stopping.StopIfSEBelowThreshold.update(stopping, cats)
      assert stopping.early_stop == true
    end

    test "waits for patience period" do
      stopping =
        Stopping.StopIfSEBelowThreshold.new(
          %{cat1: 0.03},
          patience: %{cat1: 3},
          tolerance: %{cat1: 0.01},
          logical_operation: :or
        )

      cats = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.02}
      }

      stopping = Stopping.StopIfSEBelowThreshold.update(stopping, cats)
      assert stopping.early_stop == false

      cats = %{
        cat1: %MockCat{n_items: 2, se_measurement: 0.02}
      }

      stopping = Stopping.StopIfSEBelowThreshold.update(stopping, cats)
      assert stopping.early_stop == false

      cats = %{
        cat1: %MockCat{n_items: 3, se_measurement: 0.02}
      }

      stopping = Stopping.StopIfSEBelowThreshold.update(stopping, cats)
      assert stopping.early_stop == true
    end

    test "respects tolerance" do
      stopping =
        Stopping.StopIfSEBelowThreshold.new(
          %{cat1: 0.03},
          patience: %{cat1: 2},
          tolerance: %{cat1: 0.05},
          logical_operation: :or
        )

      # SE of 0.08 is above threshold 0.03, but within tolerance (0.03 + 0.05 = 0.08)
      stopping =
        Stopping.StopIfSEBelowThreshold.update(stopping, %{
          cat1: %MockCat{n_items: 1, se_measurement: 0.08}
        })

      stopping =
        Stopping.StopIfSEBelowThreshold.update(stopping, %{
          cat1: %MockCat{n_items: 2, se_measurement: 0.08}
        })

      assert stopping.early_stop == true
    end

    test "uses default values when not provided" do
      stopping =
        Stopping.StopIfSEBelowThreshold.new(
          %{cat1: 0.03},
          logical_operation: :only
        )

      # SE below threshold with default patience of 1
      cats = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.01}
      }

      stopping = Stopping.StopIfSEBelowThreshold.update(stopping, cats, :cat1)
      assert stopping.early_stop == true
    end

    test "handles empty threshold with default of 0" do
      stopping =
        Stopping.StopIfSEBelowThreshold.new(
          %{},
          patience: %{cat1: 2},
          tolerance: %{cat1: 0.01},
          logical_operation: :only
        )

      # SE below default threshold of 0 (negative SE is impossible in practice,
      # but this tests the fallback logic)
      stopping =
        Stopping.StopIfSEBelowThreshold.update(
          stopping,
          %{cat1: %MockCat{n_items: 1, se_measurement: -0.01}},
          :cat1
        )

      stopping =
        Stopping.StopIfSEBelowThreshold.update(
          stopping,
          %{cat1: %MockCat{n_items: 2, se_measurement: -0.01}},
          :cat1
        )

      assert stopping.early_stop == true
    end

    test "AND operation requires all conditions" do
      stopping =
        Stopping.StopIfSEBelowThreshold.new(
          %{cat1: 0.03, cat2: 0.02},
          patience: %{cat1: 1, cat2: 3},
          tolerance: %{cat1: 0.01, cat2: 0.02},
          logical_operation: :and
        )

      cats = %{
        cat1: %MockCat{n_items: 1, se_measurement: 0.5},
        cat2: %MockCat{n_items: 1, se_measurement: 0.03}
      }

      stopping = Stopping.StopIfSEBelowThreshold.update(stopping, cats)
      assert stopping.early_stop == false

      # cat1 drops below threshold but cat2 hasn't reached patience
      cats = %{
        cat1: %MockCat{n_items: 2, se_measurement: 0.02},
        cat2: %MockCat{n_items: 2, se_measurement: 0.03}
      }

      stopping = Stopping.StopIfSEBelowThreshold.update(stopping, cats)
      assert stopping.early_stop == false

      # Both drop below threshold after patience
      cats = %{
        cat1: %MockCat{n_items: 3, se_measurement: 0.02},
        cat2: %MockCat{n_items: 3, se_measurement: 0.01}
      }

      stopping = Stopping.StopIfSEBelowThreshold.update(stopping, cats)
      assert stopping.early_stop == true
    end
  end

  describe "logical operation only" do
    test "requires cat_to_evaluate" do
      stopping =
        Stopping.StopAfterNItems.new(
          %{cat1: 2},
          logical_operation: :only
        )

      cats = %{
        cat1: %MockCat{n_items: 2, se_measurement: 0.5}
      }

      assert_raise ArgumentError, ~r/Must provide cat_to_evaluate/, fn ->
        Stopping.StopAfterNItems.update(stopping, cats)
      end
    end

    test "evaluates only specified cat" do
      stopping =
        Stopping.StopAfterNItems.new(
          %{cat1: 2},
          logical_operation: :only
        )

      cats = %{
        cat1: %MockCat{n_items: 2, se_measurement: 0.5},
        cat2: %MockCat{n_items: 5, se_measurement: 0.3}
      }

      stopping = Stopping.StopAfterNItems.update(stopping, cats, :cat1)
      assert stopping.early_stop == true

      # Cat2 has more items but isn't evaluated
      stopping = Stopping.StopAfterNItems.update(stopping, cats, :cat2)
      assert stopping.early_stop == false
    end
  end

  describe "evaluation_cats" do
    test "returns patience and tolerance keys for StopOnSEPlateau" do
      stopping =
        Stopping.StopOnSEPlateau.new(
          %{cat1: 2, cat2: 3},
          %{cat2: 0.02, cat3: 0.03}
        )

      cats = Stopping.StopOnSEPlateau.evaluation_cats(stopping)
      assert Enum.sort(cats) == [:cat1, :cat2, :cat3]
    end

    test "returns all keys for StopIfSEBelowThreshold" do
      stopping =
        Stopping.StopIfSEBelowThreshold.new(
          %{cat1: 0.03},
          patience: %{cat2: 2},
          tolerance: %{cat3: 0.01}
        )

      cats = Stopping.StopIfSEBelowThreshold.evaluation_cats(stopping)
      assert Enum.sort(cats) == [:cat1, :cat2, :cat3]
    end
  end
end
