# Get Started

CatEx is a Computer Adaptive Testing (CAT) library for Elixir, ported from
[jsCAT](https://github.com/yeatmanlab/jsCAT). It provides IRT-based adaptive
testing for educational and psychological assessments.

## Installation

Add `cat_ex` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:cat_ex, "~> 0.1.0"}
  ]
end
```

Then fetch:

```bash
mix deps.get
```

## Your First Adaptive Test

A typical CAT session follows three steps: **create** a CAT instance,
**update** ability estimates with responses, and **select** the next item.

### Step 1: Create a CAT Instance

```elixir
alias CatEx.CAT

cat = CAT.new(
  method: "MLE",        # Maximum Likelihood Estimation
  item_select: "MFI",   # Maximum Fisher Information selection
  theta: 0.0,           # Initial ability estimate
  min_theta: -6.0,
  max_theta: 6.0
)
```

### Step 2: Define Your Item Pool

Each item has 4PL IRT parameters plus any additional metadata you need:

```elixir
stimuli = [
  %{a: 1.0, b: -1.0, c: 0.2, d: 1.0, word: "easy"},
  %{a: 1.5, b:  0.0, c: 0.25, d: 0.95, word: "medium"},
  %{a: 2.0, b:  2.0, c: 0.3, d: 0.9, word: "hard"}
]
```

The four IRT parameters are:

| Parameter | Key | Meaning | Default |
|-----------|-----|---------|---------|
| Discrimination | `a` or `discrimination` | How well the item differentiates ability levels | 1.0 |
| Difficulty | `b` or `difficulty` | The ability level at which P(correct) = 0.5 (for 2PL) | 0.0 |
| Guessing | `c` or `guessing` | Lower asymptote (probability of guessing correctly) | 0.0 |
| Slipping | `d` or `slipping` | Upper asymptote (1 - probability of careless error) | 1.0 |

### Step 3: Run the Adaptive Loop

```elixir
# Present an item and record the response (1 = correct, 0 = incorrect)
cat = CAT.update_ability_estimate(cat, Enum.at(stimuli, 0), 1)

# Select the next optimal item
{next_item, remaining} = CAT.find_next_item(cat, stimuli)

# Check current state
CAT.n_items(cat)       # => 1
cat.theta              # Current ability estimate
cat.se_measurement     # Standard error of measurement
```

You can also update with multiple items at once:

```elixir
zetas = [
  %{a: 2.225, b: -1.885, c: 0.21, d: 1},
  %{a: 1.174, b: -2.411, c: 0.212, d: 1},
  %{a: 2.104, b: -2.439, c: 0.192, d: 1}
]

cat = CAT.update_ability_estimate(cat, zetas, [1, 0, 1])
```

## Choosing an Estimation Method

CatEx supports two ability estimation methods:

### MLE (Maximum Likelihood Estimation)

Best when you have enough responses (3+). Uses multi-start Powell optimization
to find the theta that maximizes the likelihood of the observed responses.

```elixir
cat = CAT.new(method: "MLE")
```

### EAP (Expected A Posteriori)

Better for early stages when few responses are available. Incorporates a prior
distribution to regularize the estimate.

```elixir
# Normal prior (mean=0, sd=1)
cat = CAT.new(method: "EAP", prior_dist: "norm", prior_par: [0, 1])

# Uniform prior
cat = CAT.new(method: "EAP", prior_dist: "unif", prior_par: [-3, 3])
```

## Item Selection Methods

| Method | Use When |
|--------|----------|
| `"MFI"` | You want the most informative item at the current ability (default) |
| `"closest"` | You want the item nearest in difficulty to current ability |
| `"random"` | You want random selection (e.g., for unvalidated items) |
| `"fixed"` | You want items in corpus order |
| `"middle"` | You want to start from the middle of the difficulty range |

## Next Steps

- **[Item Response Theory](item-response-theory.md)** - Understanding the IRT calculations
- **[Multi-CAT with Clowder](clowder-multi-cat.md)** - Managing multiple adaptive tests simultaneously
- **[Early Stopping](early-stopping.md)** - Configuring when to stop testing
