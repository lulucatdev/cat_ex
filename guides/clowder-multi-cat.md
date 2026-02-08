# Multi-CAT with Clowder

`CatEx.Clowder` manages multiple CAT instances simultaneously. This is useful
when a single assessment measures multiple constructs (e.g., reading and math)
and each item may have different IRT parameters for each construct.

## Overview

A **Clowder** wraps:
- Multiple named **CAT** instances (e.g., `:reading`, `:math`)
- A shared **corpus** of items with multi-zeta parameters
- An automatic **unvalidated** CAT for items without IRT parameters
- Optional **early stopping** configuration

## Creating a Clowder

```elixir
alias CatEx.Clowder

clowder = Clowder.new(
  cats: %{
    reading: [method: "MLE", theta: 0.5],
    math: [method: "EAP", prior_dist: "norm", prior_par: [0, 1]]
  },
  corpus: corpus,
  random_seed: "my-seed"
)
```

An `:unvalidated` CAT is automatically added for items that don't have IRT
parameters for any named CAT.

## Corpus Format

Each item in the corpus is a **multi-zeta stimulus** -- a map with a `:zetas`
key listing which CATs have parameters for this item:

```elixir
corpus = [
  %{
    id: "item1",
    stimulus: "What is 2+2?",
    zetas: [
      %{cats: [:math], zeta: %{a: 1.5, b: 0, c: 0.25, d: 1}},
      %{cats: [:reading], zeta: %{a: 0.8, b: -1, c: 0.2, d: 1}}
    ]
  },
  %{
    id: "item2",
    stimulus: "Spell 'cat'",
    zetas: [
      %{cats: [:reading], zeta: %{a: 1.2, b: -0.5, c: 0.1, d: 1}}
    ]
  }
]
```

### Preparing a Corpus from Flat Data

If your data has prefixed column names (e.g., from a CSV), use
`CatEx.Corpus.prepare_clowder_corpus/4`:

```elixir
items = [
  %{
    "math.a" => 1.5, "math.b" => 0, "math.c" => 0.25, "math.d" => 1,
    "reading.a" => 0.8, "reading.b" => -1,
    stimulus: "What is 2+2?"
  }
]

corpus = CatEx.Corpus.prepare_clowder_corpus(items, ["math", "reading"], ".", :symbolic)
```

## The Update-and-Select Loop

`Clowder.update_and_select/2` handles everything in one call: updating CATs
with responses, checking early stopping, and selecting the next item.

```elixir
{clowder, next_item} = Clowder.update_and_select(clowder,
  cat_to_select: :math,           # Which CAT drives item selection
  cats_to_update: [:math, :reading],  # Which CATs to update with responses
  items: [previous_item],         # Items just presented
  answers: [1]                    # Responses (1=correct, 0=incorrect)
)
```

### Key Options

| Option | Description |
|--------|-------------|
| `cat_to_select` | **(required)** Which CAT to use for selecting the next item |
| `cats_to_update` | List of CATs to update with the new responses |
| `items` | Previously presented items (single or list) |
| `answers` | Corresponding answers (single or list) |
| `corpus_to_select_from` | Select from a different CAT's item pool |
| `item_select` | Override item selection method |
| `cat_to_evaluate_early_stopping` | Which CAT to check for early stopping with `:only` |
| `return_undefined_on_exhaustion` | Return `nil` when items run out (default: `true`) |

### Stopping Reasons

After `update_and_select`, check `clowder.stopping_reason`:

```elixir
case clowder.stopping_reason do
  nil -> # Continue testing
  "Early stopping" -> # Early stopping triggered
  "No validated items remaining for the requested corpus " <> cat -> # Items exhausted
  "No unvalidated items remaining" -> # Unvalidated items exhausted
end
```

## Unvalidated Items

Items with empty `cats` lists in their zetas are considered **unvalidated**.
Select them with `cat_to_select: :unvalidated`:

```elixir
{clowder, item} = Clowder.update_and_select(clowder,
  cat_to_select: :unvalidated
)
```

## Querying State

```elixir
Clowder.thetas(clowder)          # %{reading: 0.5, math: -0.3, unvalidated: 0.0}
Clowder.se_measurements(clowder) # %{reading: 0.8, math: :infinity, ...}
Clowder.n_items(clowder)         # %{reading: 3, math: 1, unvalidated: 0}
```
