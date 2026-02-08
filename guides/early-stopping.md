# Early Stopping

CatEx provides three early stopping strategies that can be used standalone or
combined with logical operations. All stopping modules live under
`CatEx.Stopping`.

## StopAfterNItems

The simplest strategy: stop after a fixed number of items have been administered.

```elixir
alias CatEx.Stopping

stopping = Stopping.StopAfterNItems.new(
  %{reading: 20, math: 15},   # Required item counts per CAT
  logical_operation: :or       # Stop when ANY cat reaches its limit
)
```

## StopOnSEPlateau

Stop when the standard error of measurement stabilizes (stops changing).
Useful when further items aren't improving precision.

```elixir
stopping = Stopping.StopOnSEPlateau.new(
  %{reading: 5, math: 5},       # Patience: number of recent SE values to check
  %{reading: 0.01, math: 0.02}, # Tolerance: max allowed deviation from mean
  logical_operation: :and        # Stop only when ALL cats plateau
)
```

The plateau is detected when the last `patience` SE measurements all fall
within `tolerance` of their mean.

## StopIfSEBelowThreshold

Stop when measurement precision reaches a target threshold.

```elixir
stopping = Stopping.StopIfSEBelowThreshold.new(
  %{reading: 0.3, math: 0.4},             # SE thresholds
  patience: %{reading: 3, math: 3},       # Must stay below for this many items
  tolerance: %{reading: 0.05, math: 0.05} # Allowed overshoot above threshold
)
```

The condition triggers when the last `patience` SE values each satisfy
`se - threshold <= tolerance`.

## Logical Operations

Each stopping strategy supports three logical operations for combining
conditions across multiple CATs:

| Operation | Behavior |
|-----------|----------|
| `:or` | Stop when **any** CAT meets its condition (default) |
| `:and` | Stop when **all** CATs meet their conditions |
| `:only` | Evaluate **only** the specified `cat_to_evaluate` |

### Using `:only`

The `:only` operation requires passing a `cat_to_evaluate` when calling
`update/3`:

```elixir
stopping = Stopping.StopAfterNItems.new(
  %{reading: 10},
  logical_operation: :only
)

# Must specify which cat to evaluate
stopping = Stopping.StopAfterNItems.update(stopping, cats, :reading)
```

## Using with Clowder

Pass the stopping configuration when creating a Clowder:

```elixir
early_stopping = Stopping.StopAfterNItems.new(%{reading: 20, math: 15})

clowder = CatEx.Clowder.new(
  cats: %{reading: [method: "MLE"], math: [method: "EAP"]},
  corpus: corpus,
  early_stopping: early_stopping
)
```

The Clowder automatically calls `update/3` on the stopping strategy during
`update_and_select/2`. When early stopping triggers, the Clowder sets
`stopping_reason` to `"Early stopping"` and returns `nil` as the next item.

```elixir
{clowder, next_item} = Clowder.update_and_select(clowder,
  cat_to_select: :reading,
  cats_to_update: [:reading],
  items: [item],
  answers: [1],
  cat_to_evaluate_early_stopping: :reading  # For :only operations
)

if clowder.stopping_reason == "Early stopping" do
  IO.puts("Test complete!")
end
```

## Updating Manually

If using stopping strategies without a Clowder, call `update/3` yourself:

```elixir
cats = %{
  reading: my_reading_cat,
  math: my_math_cat
}

stopping = Stopping.StopAfterNItems.update(stopping, cats)

if stopping.early_stop do
  IO.puts("Time to stop!")
end
```

The `cats` map values must be either `CatEx.CAT` structs or any struct/map
with `:n_items` and `:se_measurement` fields.
