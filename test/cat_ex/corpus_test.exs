defmodule CatEx.CorpusTest do
  use ExUnit.Case
  doctest CatEx.Corpus

  alias CatEx.Corpus

  describe "default_zeta" do
    test "returns default zeta in symbolic format" do
      zeta = Corpus.default_zeta(:symbolic)
      assert zeta.a == 1
      assert zeta.b == 0
      assert zeta.c == 0
      assert zeta.d == 1
    end

    test "returns default zeta in semantic format" do
      zeta = Corpus.default_zeta(:semantic)
      assert zeta.discrimination == 1
      assert zeta.difficulty == 0
      assert zeta.guessing == 0
      assert zeta.slipping == 1
    end
  end

  describe "ensure_zeta_numeric_values" do
    test "converts string numbers to numeric values" do
      zeta = %{a: "1.5", b: "2.0", c: "0.25", d: "0.95"}
      result = Corpus.ensure_zeta_numeric_values(zeta)

      assert result.a == 1.5
      assert result.b == 2.0
      assert result.c == 0.25
      assert result.d == 0.95
    end

    test "preserves numeric values" do
      zeta = %{a: 1.5, b: 2.0, c: 0.25, d: 0.95}
      result = Corpus.ensure_zeta_numeric_values(zeta)

      assert result.a == 1.5
      assert result.b == 2.0
      assert result.c == 0.25
      assert result.d == 0.95
    end

    test "filters out nil values" do
      zeta = %{a: 1.5, b: nil, c: 0.25}
      result = Corpus.ensure_zeta_numeric_values(zeta)

      assert Map.has_key?(result, :a)
      assert not Map.has_key?(result, :b)
      assert Map.has_key?(result, :c)
    end

    test "filters out NA values (case insensitive)" do
      zeta = %{a: 1.5, b: "NA", c: "na", d: "Na", discrimination: 2.0}
      result = Corpus.ensure_zeta_numeric_values(zeta)

      assert Map.has_key?(result, :a)
      assert not Map.has_key?(result, :b)
      assert not Map.has_key?(result, :c)
      assert not Map.has_key?(result, :d)
      assert Map.has_key?(result, :discrimination)
    end

    test "handles zero values correctly" do
      zeta = %{a: 0, b: "0", c: 0.0, d: "0.0"}
      result = Corpus.ensure_zeta_numeric_values(zeta)

      assert result.a == 0
      assert result.b == 0
      assert result.c == 0
      assert result.d == 0
    end

    test "handles negative values correctly" do
      zeta = %{a: -1.5, b: "-2.0", c: 0.25}
      result = Corpus.ensure_zeta_numeric_values(zeta)

      assert result.a == -1.5
      assert result.b == -2.0
      assert result.c == 0.25
    end

    test "returns empty map when all values are invalid" do
      zeta = %{a: nil, b: nil, c: "NA", d: nil}
      result = Corpus.ensure_zeta_numeric_values(zeta)
      assert map_size(result) == 0
    end
  end

  describe "validate_zeta_params" do
    test "throws error when providing both a and discrimination" do
      assert_raise ArgumentError, ~r/has both.*a.*and.*discrimination/, fn ->
        Corpus.validate_zeta_params(%{a: 1, discrimination: 1})
      end
    end

    test "throws error when providing both b and difficulty" do
      assert_raise ArgumentError, ~r/has both.*b.*and.*difficulty/, fn ->
        Corpus.validate_zeta_params(%{b: 1, difficulty: 1})
      end
    end

    test "throws error when providing both c and guessing" do
      assert_raise ArgumentError, ~r/has both.*c.*and.*guessing/, fn ->
        Corpus.validate_zeta_params(%{c: 1, guessing: 1})
      end
    end

    test "throws error when providing both d and slipping" do
      assert_raise ArgumentError, ~r/has both.*d.*and.*slipping/, fn ->
        Corpus.validate_zeta_params(%{d: 1, slipping: 1})
      end
    end

    test "throws error when requiring all keys and missing one" do
      for key <- [:a, :b, :c, :d] do
        zeta = Map.delete(Corpus.default_zeta(:symbolic), key)

        assert_raise ArgumentError, ~r/missing/, fn ->
          Corpus.validate_zeta_params(zeta, true)
        end
      end
    end

    test "passes validation with valid params" do
      zeta = %{a: 1, b: 0, c: 0, d: 1}
      assert Corpus.validate_zeta_params(zeta) == :ok
    end
  end

  describe "fill_zeta_defaults" do
    test "fills in default values for missing keys" do
      zeta = %{difficulty: 1, guessing: 0.5}
      filled = Corpus.fill_zeta_defaults(zeta, :semantic)

      assert filled.discrimination == 1
      assert filled.difficulty == 1
      assert filled.guessing == 0.5
      assert filled.slipping == 1
    end

    test "does not modify existing values" do
      zeta = %{a: 5, b: 5, c: 5, d: 5}
      filled = Corpus.fill_zeta_defaults(zeta, :symbolic)

      assert filled.a == 5
      assert filled.b == 5
      assert filled.c == 5
      assert filled.d == 5
    end

    test "converts to semantic format" do
      zeta = %{a: 5, b: 5}
      filled = Corpus.fill_zeta_defaults(zeta, :semantic)

      assert filled.discrimination == 5
      assert filled.difficulty == 5
      assert filled.guessing == 0
      assert filled.slipping == 1
    end

    test "converts to symbolic format" do
      zeta = %{difficulty: 5, discrimination: 5}
      filled = Corpus.fill_zeta_defaults(zeta, :symbolic)

      assert filled.a == 5
      assert filled.b == 5
      assert filled.c == 0
      assert filled.d == 1
    end
  end

  describe "convert_zeta" do
    test "converts from symbolic to semantic format" do
      zeta = %{a: 1, b: 2, c: 3, d: 4}
      converted = Corpus.convert_zeta(zeta, :semantic)

      assert converted.discrimination == 1
      assert converted.difficulty == 2
      assert converted.guessing == 3
      assert converted.slipping == 4
    end

    test "converts from semantic to symbolic format" do
      zeta = %{discrimination: 1, difficulty: 2, guessing: 3, slipping: 4}
      converted = Corpus.convert_zeta(zeta, :symbolic)

      assert converted.a == 1
      assert converted.b == 2
      assert converted.c == 3
      assert converted.d == 4
    end

    test "does not modify other keys when converting" do
      zeta = %{a: 1, b: 2, c: 3, d: 4, key1: 5, key2: 6}
      converted = Corpus.convert_zeta(zeta, :semantic)

      assert converted.key1 == 5
      assert converted.key2 == 6
    end

    test "converts only existing keys" do
      zeta = %{a: 1, b: 2}
      converted = Corpus.convert_zeta(zeta, :semantic)

      assert converted.discrimination == 1
      assert converted.difficulty == 2
      assert not Map.has_key?(converted, :guessing)
      assert not Map.has_key?(converted, :slipping)
    end

    test "throws error for invalid format" do
      assert_raise ArgumentError, ~r/Invalid format/, fn ->
        Corpus.convert_zeta(%{a: 1}, :invalid)
      end
    end
  end

  describe "check_no_duplicate_cat_names" do
    test "throws error when cat name is present in multiple zetas" do
      corpus = [
        %{
          stimulus: "Item 1",
          zetas: [
            %{cats: ["Model A", "Model B"], zeta: %{a: 1, b: 0.5, c: 0.2, d: 0.8}},
            %{cats: ["Model C"], zeta: %{a: 2, b: 0.7, c: 0.3, d: 0.9}},
            %{cats: ["Model C"], zeta: %{a: 1, b: 2, c: 0.3, d: 0.9}}
          ]
        },
        %{
          stimulus: "Item 2",
          zetas: [%{cats: ["Model A", "Model C"], zeta: %{a: 2.5, b: 0.8, c: 0.35, d: 0.95}}]
        }
      ]

      assert_raise ArgumentError, ~r/Duplicate cat names.*Model C/, fn ->
        Corpus.check_no_duplicate_cat_names(corpus)
      end
    end

    test "passes when no duplicate cat names" do
      items = [
        %{
          stimulus: "Item 1",
          zetas: [
            %{cats: ["Model A", "Model B"], zeta: %{a: 1, b: 0.5, c: 0.2, d: 0.8}},
            %{cats: ["Model C"], zeta: %{a: 2, b: 0.7, c: 0.3, d: 0.9}}
          ]
        },
        %{
          stimulus: "Item 2",
          zetas: [%{cats: ["Model B", "Model C"], zeta: %{a: 2.5, b: 0.8, c: 0.35, d: 0.95}}]
        }
      ]

      assert Corpus.check_no_duplicate_cat_names(items) == :ok
    end

    test "handles empty corpus without error" do
      assert Corpus.check_no_duplicate_cat_names([]) == :ok
    end
  end

  describe "filter_items_by_cat_parameter_availability" do
    test "returns empty available array when no items match" do
      items = [
        %{
          stimulus: "Item 1",
          zetas: [
            %{cats: ["Model A", "Model B"], zeta: %{a: 1, b: 0.5, c: 0.2, d: 0.8}},
            %{cats: ["Model C"], zeta: %{a: 2, b: 0.7, c: 0.3, d: 0.9}}
          ]
        },
        %{
          stimulus: "Item 2",
          zetas: [%{cats: ["Model B", "Model C"], zeta: %{a: 2.5, b: 0.8, c: 0.35, d: 0.95}}]
        }
      ]

      result = Corpus.filter_items_by_cat_parameter_availability(items, "Model D")

      assert result.available == []
      assert length(result.missing) == 2
    end

    test "returns empty missing array when all items match" do
      items = [
        %{
          stimulus: "Item 1",
          zetas: [
            %{cats: ["Model A", "Model B"], zeta: %{a: 1, b: 0.5, c: 0.2, d: 0.8}},
            %{cats: ["Model A"], zeta: %{a: 2, b: 0.7, c: 0.3, d: 0.9}}
          ]
        },
        %{
          stimulus: "Item 2",
          zetas: [
            %{cats: ["Model A", "Model C"], zeta: %{a: 2.5, b: 0.8, c: 0.35, d: 0.95}},
            %{cats: ["Model A"], zeta: %{a: 3, b: 0.9, c: 0.4, d: 0.99}}
          ]
        }
      ]

      result = Corpus.filter_items_by_cat_parameter_availability(items, "Model A")

      assert result.missing == []
      assert length(result.available) == 2
    end

    test "separates items based on matching cat names" do
      items = [
        %{
          stimulus: "Item 1",
          zetas: [
            %{cats: ["Model A", "Model B"], zeta: %{a: 1, b: 0.5, c: 0.2, d: 0.8}},
            %{cats: ["Model C"], zeta: %{a: 2, b: 0.7, c: 0.3, d: 0.9}}
          ]
        },
        %{
          stimulus: "Item 2",
          zetas: [%{cats: ["Model B", "Model C"], zeta: %{a: 2.5, b: 0.8, c: 0.35, d: 0.95}}]
        },
        %{
          stimulus: "Item 3",
          zetas: [%{cats: ["Model A"], zeta: %{a: 3, b: 0.9, c: 0.4, d: 0.99}}]
        }
      ]

      result = Corpus.filter_items_by_cat_parameter_availability(items, "Model A")

      assert length(result.available) == 2
      assert hd(result.available).stimulus == "Item 1"
      assert (result.available |> Enum.at(1)).stimulus == "Item 3"
      assert length(result.missing) == 1
      assert hd(result.missing).stimulus == "Item 2"
    end
  end

  describe "prepare_clowder_corpus" do
    test "converts Stimulus array to MultiZetaStimulus array with symbolic format" do
      items = [
        %{
          "cat1.a" => 1,
          "cat1.b" => 2,
          "cat1.c" => 3,
          "cat1.d" => 4,
          "foo.a" => 5,
          "foo.b" => 6,
          "foo.c" => 7,
          "foo.d" => 8,
          stimulus: "stim0",
          type: "jspsychHtmlMultiResponse"
        }
      ]

      result = Corpus.prepare_clowder_corpus(items, ["cat1", "foo"], ".", :symbolic)

      assert length(result) == 1
      item = hd(result)
      assert item.stimulus == "stim0"
      assert item.type == "jspsychHtmlMultiResponse"
      assert length(item.zetas) == 2

      cat1_zeta = Enum.find(item.zetas, fn z -> "cat1" in z.cats end)
      assert cat1_zeta.zeta.a == 1
      assert cat1_zeta.zeta.b == 2
      assert cat1_zeta.zeta.c == 3
      assert cat1_zeta.zeta.d == 4

      foo_zeta = Enum.find(item.zetas, fn z -> "foo" in z.cats end)
      assert foo_zeta.zeta.a == 5
      assert foo_zeta.zeta.b == 6
      assert foo_zeta.zeta.c == 7
      assert foo_zeta.zeta.d == 8
    end

    test "converts with semantic format" do
      items = [
        %{
          "cat1.a" => 1,
          "cat1.b" => 2,
          stimulus: "stim0"
        }
      ]

      result = Corpus.prepare_clowder_corpus(items, ["cat1"], ".", :semantic)
      item = hd(result)
      zeta = hd(item.zetas).zeta

      assert zeta.discrimination == 1
      assert zeta.difficulty == 2
    end

    test "handles different delimiters" do
      items = [
        %{
          "cat1_a" => 1,
          "cat1_b" => 2,
          stimulus: "stim1"
        }
      ]

      result = Corpus.prepare_clowder_corpus(items, ["cat1"], "_", :symbolic)
      item = hd(result)
      zeta = hd(item.zetas).zeta

      assert zeta.a == 1
      assert zeta.b == 2
    end
  end
end
