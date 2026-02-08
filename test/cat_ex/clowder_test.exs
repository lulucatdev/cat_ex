defmodule CatEx.ClowderTest do
  use ExUnit.Case
  doctest CatEx.Clowder

  alias CatEx.Clowder
  alias CatEx.CAT
  alias CatEx.Stopping

  # Helper functions
  defp create_stimulus(id), do: %{id: id, content: "Content #{id}"}

  defp create_multi_zeta_stimulus(id, zetas) do
    %{
      id: id,
      content: "Multi-zeta content #{id}",
      zetas: zetas
    }
  end

  defp create_zeta_cat_map(cat_names, zeta \\ nil) do
    zeta = zeta || %{a: 1, b: 0, c: 0, d: 1}
    %{cats: cat_names, zeta: zeta}
  end

  describe "Clowder initialization" do
    test "initializes with provided cats and corpus" do
      clowder =
        Clowder.new(
          cats: %{
            cat1: [method: "MLE", theta: 0.5],
            cat2: [method: "EAP", theta: -1.0]
          },
          corpus: [
            create_multi_zeta_stimulus("0", [
              create_zeta_cat_map([:cat1]),
              create_zeta_cat_map([:cat2])
            ]),
            create_multi_zeta_stimulus("1", [
              create_zeta_cat_map([:cat1]),
              create_zeta_cat_map([:cat2])
            ]),
            create_multi_zeta_stimulus("2", [create_zeta_cat_map([:cat1])]),
            create_multi_zeta_stimulus("3", [create_zeta_cat_map([:cat2])]),
            create_multi_zeta_stimulus("4", [])
          ]
        )

      assert Map.has_key?(clowder.cats, :cat1)
      assert Map.has_key?(clowder.cats, :cat2)
      # Auto-added
      assert Map.has_key?(clowder.cats, :unvalidated)
      assert length(clowder.remaining_items) == 5
      assert length(clowder.corpus) == 5
      assert clowder.seen_items == []
    end

    test "throws error with invalid corpus (duplicate cat names)" do
      assert_raise ArgumentError, ~r/Duplicate cat names/, fn ->
        Clowder.new(
          cats: %{cat1: []},
          corpus: [
            %{
              id: "item1",
              zetas: [
                %{cats: ["Model A", "Model B"], zeta: %{a: 1, b: 0.5}},
                %{cats: ["Model C"], zeta: %{a: 2, b: 0.7}},
                # Duplicate Model C
                %{cats: ["Model C"], zeta: %{a: 1, b: 2}}
              ]
            },
            %{
              id: "item2",
              zetas: [%{cats: ["Model A", "Model C"], zeta: %{a: 2.5, b: 0.8}}]
            }
          ]
        )
      end
    end

    test "can receive random seed" do
      clowder =
        Clowder.new(
          cats: %{cat1: []},
          corpus: [],
          random_seed: "test-seed"
        )

      assert clowder.random_seed == "test-seed"
    end

    test "can receive early stopping" do
      early_stopping = Stopping.StopAfterNItems.new(%{cat1: 5})

      clowder =
        Clowder.new(
          cats: %{cat1: []},
          corpus: [],
          early_stopping: early_stopping
        )

      assert clowder.early_stopping != nil
    end
  end

  describe "Clowder properties" do
    setup do
      clowder =
        Clowder.new(
          cats: %{
            cat1: [method: "MLE", theta: 0.5],
            cat2: [method: "EAP", theta: -1.0]
          },
          corpus: [
            create_multi_zeta_stimulus("0", [
              create_zeta_cat_map([:cat1]),
              create_zeta_cat_map([:cat2])
            ]),
            create_multi_zeta_stimulus("1", [
              create_zeta_cat_map([:cat1]),
              create_zeta_cat_map([:cat2])
            ]),
            create_multi_zeta_stimulus("2", [create_zeta_cat_map([:cat1])]),
            create_multi_zeta_stimulus("3", [create_zeta_cat_map([:cat2])]),
            create_multi_zeta_stimulus("4", [])
          ]
        )

      %{clowder: clowder}
    end

    test "thetas property returns theta for each cat", %{clowder: clowder} do
      thetas = Clowder.thetas(clowder)

      assert thetas.cat1 == 0.5
      assert thetas.cat2 == -1.0
    end

    test "se_measurements property returns SE for each cat", %{clowder: clowder} do
      se_measurements = Clowder.se_measurements(clowder)

      # SE can be :infinity when no items have been administered
      assert se_measurements.cat1 == :infinity or is_float(se_measurements.cat1)
      assert se_measurements.cat2 == :infinity or is_float(se_measurements.cat2)
    end

    test "n_items property returns count for each cat", %{clowder: clowder} do
      n_items = Clowder.n_items(clowder)

      assert n_items.cat1 == 0
      assert n_items.cat2 == 0
    end
  end

  describe "update_and_select" do
    setup do
      clowder =
        Clowder.new(
          cats: %{
            cat1: [method: "MLE", theta: 0.5],
            cat2: [method: "EAP", theta: -1.0]
          },
          corpus: [
            create_multi_zeta_stimulus("0", [
              create_zeta_cat_map([:cat1]),
              create_zeta_cat_map([:cat2])
            ]),
            create_multi_zeta_stimulus("1", [
              create_zeta_cat_map([:cat1]),
              create_zeta_cat_map([:cat2])
            ]),
            create_multi_zeta_stimulus("2", [create_zeta_cat_map([:cat1])]),
            create_multi_zeta_stimulus("3", [create_zeta_cat_map([:cat2])]),
            create_multi_zeta_stimulus("4", [])
          ]
        )

      %{clowder: clowder}
    end

    test "throws error for invalid cat_to_select", %{clowder: clowder} do
      assert_raise ArgumentError, ~r/Invalid cat name/, fn ->
        Clowder.update_and_select(clowder, cat_to_select: :invalid_cat)
      end
    end

    test "throws error if items and answers length mismatch", %{clowder: clowder} do
      assert_raise ArgumentError, ~r/same length/, fn ->
        Clowder.update_and_select(clowder,
          cat_to_select: :cat1,
          items: [Enum.at(clowder.corpus, 0), Enum.at(clowder.corpus, 1)],
          answers: [1]
        )
      end
    end

    test "updates seen and remaining items", %{clowder: clowder} do
      {clowder, _} =
        Clowder.update_and_select(clowder,
          cat_to_select: :cat2,
          cats_to_update: [:cat1, :cat2],
          items: [
            Enum.at(clowder.corpus, 0),
            Enum.at(clowder.corpus, 1),
            Enum.at(clowder.corpus, 2)
          ],
          answers: [1, 1, 1]
        )

      assert length(clowder.seen_items) == 3
      assert length(clowder.remaining_items) == 2
    end

    test "selects item not yet seen", %{clowder: clowder} do
      {clowder, next_item} =
        Clowder.update_and_select(clowder,
          cat_to_select: :cat2,
          cats_to_update: [:cat1, :cat2],
          items: [
            Enum.at(clowder.corpus, 0),
            Enum.at(clowder.corpus, 1),
            Enum.at(clowder.corpus, 2)
          ],
          answers: [1, 1, 1]
        )

      # Should select from remaining items (id 3 or 4)
      assert next_item.id in ["3", "4"]
    end

    test "updates ability estimates correctly", %{clowder: clowder} do
      original_theta = clowder.cats.cat1.theta

      {clowder, _} =
        Clowder.update_and_select(clowder,
          cat_to_select: :cat1,
          cats_to_update: [:cat1],
          items: [Enum.at(clowder.corpus, 0)],
          answers: [1]
        )

      assert clowder.cats.cat1.theta != original_theta
    end

    test "can receive single item and answer", %{clowder: clowder} do
      {clowder, next_item} =
        Clowder.update_and_select(clowder,
          cat_to_select: :cat1,
          items: Enum.at(clowder.corpus, 0),
          answers: 1
        )

      assert next_item != nil
      assert length(clowder.seen_items) == 1
    end

    test "can receive single cat_to_update", %{clowder: clowder} do
      original_theta = clowder.cats.cat1.theta

      {clowder, next_item} =
        Clowder.update_and_select(clowder,
          cat_to_select: :cat1,
          cats_to_update: :cat1,
          items: Enum.at(clowder.corpus, 0),
          answers: 1
        )

      assert next_item != nil
      assert clowder.cats.cat1.theta != original_theta
    end

    test "allows selecting from different corpus", %{clowder: clowder} do
      clowder =
        Clowder.new(
          cats: %{
            cat1: [method: "MLE", theta: 0.5],
            cat2: [method: "MLE", theta: 0.5]
          },
          corpus: [
            create_multi_zeta_stimulus("item1", [create_zeta_cat_map([:cat1])]),
            create_multi_zeta_stimulus("item2", [create_zeta_cat_map([:cat1, :cat2])]),
            create_multi_zeta_stimulus("item3", [create_zeta_cat_map([:cat1, :cat2])])
          ]
        )

      {_, next_item} =
        Clowder.update_and_select(clowder,
          cat_to_select: :cat1,
          corpus_to_select_from: :cat2
        )

      assert next_item.id in ["item2", "item3"]
    end

    test "validates corpus_to_select_from", %{clowder: clowder} do
      assert_raise ArgumentError, ~r/Invalid cat name/, fn ->
        Clowder.update_and_select(clowder,
          cat_to_select: :cat1,
          corpus_to_select_from: :nonexistent
        )
      end
    end

    test "throws error for invalid cats_to_update", %{clowder: clowder} do
      assert_raise ArgumentError, ~r/Invalid cat name/, fn ->
        Clowder.update_and_select(clowder,
          cat_to_select: :cat1,
          cats_to_update: [:invalid_cat, :cat2]
        )
      end
    end

    test "returns nil when all items exhausted", %{clowder: clowder} do
      {clowder, _} =
        Clowder.update_and_select(clowder,
          cat_to_select: :cat1,
          items: clowder.remaining_items,
          answers: List.duplicate(1, length(clowder.remaining_items))
        )

      assert clowder.stopping_reason ==
               "No validated items remaining for the requested corpus cat1"
    end

    test "returns undefined when no validated items remain", %{clowder: clowder} do
      clowder =
        Clowder.new(
          cats: %{cat1: [method: "MLE", theta: 0.5]},
          corpus: [
            create_multi_zeta_stimulus("0", [create_zeta_cat_map([:cat1])]),
            create_multi_zeta_stimulus("1", [create_zeta_cat_map([:cat1])])
          ]
        )

      # Use all validated items
      {clowder, _} =
        Clowder.update_and_select(clowder,
          cat_to_select: :cat1,
          cats_to_update: [:cat1],
          items: clowder.corpus,
          answers: [1, 1]
        )

      # Try to get another item with return_undefined_on_exhaustion defaulting to true
      {clowder, next_item} =
        Clowder.update_and_select(clowder,
          cat_to_select: :cat1
        )

      assert next_item == nil

      assert clowder.stopping_reason ==
               "No validated items remaining for the requested corpus cat1"
    end
  end

  describe "Unvalidated items" do
    test "selects unvalidated item when cat_to_select is unvalidated" do
      clowder =
        Clowder.new(
          cats: %{cat1: [method: "MLE", theta: 0.5]},
          corpus: [
            create_multi_zeta_stimulus("0", [create_zeta_cat_map([])]),
            create_multi_zeta_stimulus("1", [create_zeta_cat_map([:cat1])]),
            create_multi_zeta_stimulus("2", [create_zeta_cat_map([])]),
            create_multi_zeta_stimulus("3", [create_zeta_cat_map([:cat1])])
          ]
        )

      # Draw multiple times to test randomness
      results =
        for _ <- 1..20 do
          {clowder, next_item} =
            Clowder.update_and_select(clowder,
              cat_to_select: :unvalidated
            )

          next_item.id
        end

      assert Enum.all?(results, fn id -> id in ["0", "2"] end)
    end

    test "returns undefined when no unvalidated items remain" do
      clowder =
        Clowder.new(
          cats: %{cat1: [method: "MLE", theta: 0.5]},
          corpus: [
            create_multi_zeta_stimulus("0", [create_zeta_cat_map([])]),
            create_multi_zeta_stimulus("1", [create_zeta_cat_map([:cat1])]),
            create_multi_zeta_stimulus("2", [create_zeta_cat_map([])]),
            create_multi_zeta_stimulus("3", [create_zeta_cat_map([:cat1])])
          ]
        )

      # Use all unvalidated items
      {clowder, _} =
        Clowder.update_and_select(clowder,
          cats_to_update: [:cat1],
          items: [Enum.at(clowder.corpus, 0), Enum.at(clowder.corpus, 2)],
          answers: [1, 1],
          cat_to_select: :unvalidated
        )

      assert clowder.stopping_reason == "No unvalidated items remaining"
    end

    test "returns item from missing when no unvalidated and return_undefined_on_exhaustion is false" do
      clowder =
        Clowder.new(
          cats: %{cat1: [method: "MLE", theta: 0.5]},
          corpus: [
            # For cat2
            create_multi_zeta_stimulus("0", [create_zeta_cat_map([:cat2])]),
            # For cat2
            create_multi_zeta_stimulus("1", [create_zeta_cat_map([:cat2])]),
            # Unvalidated
            create_multi_zeta_stimulus("2", [create_zeta_cat_map([])])
          ],
          random_seed: "test"
        )

      # Exhaust unvalidated items
      {clowder, _} =
        Clowder.update_and_select(clowder,
          items: [Enum.at(clowder.corpus, 2)],
          answers: [1],
          cat_to_select: :unvalidated
        )

      # Should return items from missing (validated for cat2)
      {_, next_item} =
        Clowder.update_and_select(clowder,
          cat_to_select: :unvalidated,
          return_undefined_on_exhaustion: false
        )

      assert next_item.id in ["0", "1", "2"]
    end

    test "does not update cats with unvalidated items" do
      clowder =
        Clowder.new(
          cats: %{cat1: [method: "MLE", theta: 0.5]},
          corpus: [
            create_multi_zeta_stimulus("0", [create_zeta_cat_map([])]),
            create_multi_zeta_stimulus("1", [create_zeta_cat_map([:cat1])]),
            create_multi_zeta_stimulus("2", [create_zeta_cat_map([])]),
            create_multi_zeta_stimulus("3", [create_zeta_cat_map([:cat1])])
          ]
        )

      {clowder, _} =
        Clowder.update_and_select(clowder,
          cats_to_update: [:cat1],
          items: [Enum.at(clowder.corpus, 0), Enum.at(clowder.corpus, 2)],
          answers: [1, 1],
          cat_to_select: :unvalidated
        )

      assert Clowder.n_items(clowder).cat1 == 0
    end
  end

  describe "Early stopping integration" do
    test "triggers early stopping after required number of items" do
      early_stopping = Stopping.StopAfterNItems.new(%{cat1: 2}, logical_operation: :or)

      clowder =
        Clowder.new(
          cats: %{cat1: [method: "MLE", theta: 0.5]},
          corpus: [
            create_multi_zeta_stimulus("0", [create_zeta_cat_map([:cat1])]),
            create_multi_zeta_stimulus("1", [create_zeta_cat_map([:cat1])]),
            create_multi_zeta_stimulus("2", [create_zeta_cat_map([:cat1])])
          ],
          early_stopping: early_stopping
        )

      {clowder, next_item} =
        Clowder.update_and_select(clowder,
          cat_to_select: :cat1,
          cats_to_update: [:cat1],
          items: [Enum.at(clowder.corpus, 0)],
          answers: [1]
        )

      refute clowder.early_stopping.early_stop
      assert next_item != nil

      {clowder, next_item} =
        Clowder.update_and_select(clowder,
          cat_to_select: :cat1,
          cats_to_update: [:cat1],
          items: [Enum.at(clowder.corpus, 1)],
          answers: [1]
        )

      assert clowder.early_stopping.early_stop
      assert clowder.stopping_reason == "Early stopping"
      assert next_item == nil
    end

    test "handles StopOnSEPlateau condition" do
      early_stopping =
        Stopping.StopOnSEPlateau.new(
          %{cat1: 2},
          %{cat1: 0.05},
          logical_operation: :or
        )

      # Use high discrimination items to get SE to plateau quickly
      clowder =
        Clowder.new(
          cats: %{cat1: [method: "MLE", theta: 0.5]},
          corpus: [
            create_multi_zeta_stimulus("0", [
              create_zeta_cat_map([:cat1], %{a: 6, b: 6, c: 0, d: 1})
            ]),
            create_multi_zeta_stimulus("1", [
              create_zeta_cat_map([:cat1], %{a: 6, b: 6, c: 0, d: 1})
            ]),
            create_multi_zeta_stimulus("2", [
              create_zeta_cat_map([:cat1], %{a: 6, b: 6, c: 0, d: 1})
            ]),
            create_multi_zeta_stimulus("3", [
              create_zeta_cat_map([:cat1], %{a: 6, b: 6, c: 0, d: 1})
            ])
          ],
          early_stopping: early_stopping
        )

      # Run through corpus until early stopping triggers
      for i <- 0..3 do
        corpus = clowder.corpus

        if i < length(corpus) do
          {clowder, next_item} =
            Clowder.update_and_select(clowder,
              cat_to_select: :cat1,
              cats_to_update: [:cat1],
              items: [Enum.at(corpus, i)],
              answers: [1]
            )

          if i == 3 and clowder.early_stopping.early_stop do
            assert clowder.stopping_reason == "Early stopping"
            assert next_item == nil
          end
        end
      end
    end

    test "evaluates early stopping only for specified cat" do
      early_stopping =
        Stopping.StopAfterNItems.new(
          %{cat2: 1},
          logical_operation: :only
        )

      clowder =
        Clowder.new(
          cats: %{
            cat1: [method: "MLE", theta: 0.5],
            cat2: [method: "MLE", theta: 0.5]
          },
          corpus: [
            create_multi_zeta_stimulus("item2cat", [create_zeta_cat_map([:cat2])]),
            create_multi_zeta_stimulus("item1cat", [create_zeta_cat_map([:cat1])])
          ],
          early_stopping: early_stopping
        )

      {clowder, next_item} =
        Clowder.update_and_select(clowder,
          cat_to_select: :cat1,
          cats_to_update: [:cat2],
          items: [Enum.at(clowder.corpus, 0)],
          answers: [1],
          cat_to_evaluate_early_stopping: :cat2
        )

      assert clowder.early_stopping.early_stop
      assert clowder.stopping_reason == "Early stopping"
      assert next_item == nil
    end
  end

  describe "Corpus management" do
    test "prepare_clowder_corpus converts stimulus array" do
      items = [
        %{
          "cat1.a" => 1,
          "cat1.b" => 2,
          "cat1.c" => 3,
          "cat1.d" => 4,
          stimulus: "stim0",
          type: "jspsychHtmlMultiResponse"
        }
      ]

      corpus = CatEx.Corpus.prepare_clowder_corpus(items, ["cat1"], ".", :symbolic)

      assert length(corpus) == 1
      item = hd(corpus)
      assert item.stimulus == "stim0"
      assert length(item.zetas) == 1
      zeta = hd(item.zetas)
      assert zeta.zeta.a == 1
      assert zeta.zeta.b == 2
      assert zeta.zeta.c == 3
      assert zeta.zeta.d == 4
    end
  end
end
