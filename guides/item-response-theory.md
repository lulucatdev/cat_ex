# Item Response Theory

CatEx implements the **4-Parameter Logistic (4PL)** Item Response Theory model
via `CatEx.Utils`.

## The 4PL Model

The probability that a person with ability `theta` answers an item correctly:

```
P(theta) = c + (d - c) / (1 + exp(-a * (theta - b)))
```

Where:
- **a** (discrimination): Steepness of the response curve
- **b** (difficulty): Location on the ability scale
- **c** (guessing): Lower asymptote (chance of guessing correctly)
- **d** (slipping): Upper asymptote (1 minus chance of careless error)

### Calculating Probabilities

```elixir
alias CatEx.Utils

# Standard 2PL item (c=0, d=1)
Utils.item_response_function(0, %{a: 1, b: 0, c: 0, d: 1})
# => 0.5

# With guessing parameter
Utils.item_response_function(0, %{a: 1, b: -0.3, c: 0.35, d: 1})
# => ~0.7234
```

### Semantic Parameter Names

You can use either symbolic (`a`, `b`, `c`, `d`) or semantic names:

```elixir
# These are equivalent:
Utils.item_response_function(0, %{a: 1, b: 0, c: 0, d: 1})
Utils.item_response_function(0, %{discrimination: 1, difficulty: 0, guessing: 0, slipping: 1})
```

Missing parameters are filled with defaults automatically.

## Fisher Information

Fisher information quantifies how much information an item provides about
ability at a given theta. It is used by the MFI item selection method.

```elixir
# High information = item is very useful at this ability level
Utils.fisher_information(0, %{a: 1.53, b: -0.5, c: 0.5, d: 1})
# => ~0.206

Utils.fisher_information(2.35, %{a: 1, b: 2, c: 0.3, d: 1})
# => ~0.1401
```

Items with higher discrimination (`a`) and difficulty near the current theta
produce more Fisher information.

## Log-Likelihood

The log-likelihood function is central to MLE estimation. It measures how
well a given theta explains the observed response pattern.

```elixir
zetas = [%{a: 1, b: 0, c: 0, d: 1}]
resps = [1]

Utils.log_likelihood(0, zetas, resps)
# => ~-0.693 (= log(0.5))
```

## Standard Error

Standard error of measurement is calculated as `SE = 1 / sqrt(sum(FI))`,
where FI is the Fisher information summed across all administered items.
Lower SE indicates a more precise ability estimate.

## Prior Distributions

For EAP estimation, CatEx provides two prior distributions:

### Normal Distribution

```elixir
# Returns list of {theta, probability} tuples
prior = Utils.normal_distribution(0, 1, -4, 4, 0.1)
# 81 points from -4 to 4 with step 0.1, weighted by N(0,1)
```

### Uniform Distribution

```elixir
prior = Utils.uniform_distribution(-2, 2, -4, 4, 0.1)
# Points from -4 to 4; uniform probability within [-2, 2], zero outside
```
