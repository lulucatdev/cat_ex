# CatEx

[![Elixir CI](https://img.shields.io/badge/Elixir-1.15+-purple.svg)](https://elixir-lang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![By Lulucat](https://img.shields.io/badge/By-Lulucat%20Innovations-orange.svg)](https://github.com/lulucatinnovations)

Computer Adaptive Testing (CAT) library for Elixir - a complete port of [jsCAT](https://github.com/yeatmanlab/jsCAT).

**Maintained by [Lulucat Innovations](https://github.com/lulucatinnovations)**

CatEx provides IRT-based Computerized Adaptive Testing functionality for educational and psychological assessments. It implements Maximum Likelihood Estimation (MLE) and Expected A Posteriori (EAP) ability estimation algorithms with Powell optimization, multiple item selection strategies, and comprehensive early stopping mechanisms.

## Features

### Core CAT Functionality
- **Ability Estimation**: MLE (Maximum Likelihood Estimation) using Powell optimization and EAP (Expected A Posteriori) with customizable prior distributions
- **Item Response Theory**: Full 4-parameter logistic (4PL) model support
  - Discrimination (a)
  - Difficulty (b)
  - Guessing (c)
  - Slipping (d)
- **Fisher Information**: Calculation for optimal item selection

### Item Selection Methods
- **MFI** (Maximum Fisher Information): Selects items with highest information at current ability estimate
- **Closest**: Selects item with difficulty closest to current theta
- **Random**: Random selection with optional seed for reproducibility
- **Fixed**: Sequential selection maintaining corpus order
- **Middle**: Selects from middle of difficulty range (useful for start items)

### Multi-CAT Management (Clowder)
- Manage multiple CAT instances simultaneously
- Multi-zeta stimuli support (different IRT parameters for different CATs)
- Unvalidated item handling
- Cross-corpus item selection

### Early Stopping Mechanisms
- **StopAfterNItems**: Stop after administering specified number of items
- **StopOnSEPlateau**: Stop when standard error stabilizes
- **StopIfSEBelowThreshold**: Stop when precision reaches threshold
- **Logical Operations**: AND, OR, ONLY for combining multiple stopping conditions

### Prior Distributions (for EAP)
- Normal distribution with custom mean and standard deviation
- Uniform distribution with custom bounds
- Automatic grid generation based on theta bounds

## Installation

Add `cat_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:cat_ex, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start

### Basic CAT Usage

```elixir
alias CatEx.CAT

# Create a CAT instance with MLE estimator
cat = CAT.new(
  method: "MLE",
  item_select: "MFI",
  theta: 0.0,
  min_theta: -6.0,
  max_theta: 6.0
)

# Define stimuli with item parameters (4PL model)
stimuli = [
  %{a: 1.0, b: -1.0, c: 0.2, d: 1.0, word: "easy"},
  %{a: 1.5, b: 0.0, c: 0.25, d: 0.95, word: "medium"},
  %{a: 2.0, b: 2.0, c: 0.3, d: 0.9, word: "hard"}
]

# Update ability estimate with response (1 = correct, 0 = incorrect)
cat = CAT.update_ability_estimate(cat, Enum.at(stimuli, 0), 1)

# Get next item using MFI selection
{next_item, remaining} = CAT.find_next_item(cat, stimuli)
# next_item will be the stimulus with highest Fisher information

# Check current state
CatEx.CAT.n_items(cat)          # Number of items administered
cat.theta                         # Current ability estimate
cat.se_measurement                # Standard error of measurement
```

### EAP Estimation with Prior

```elixir
# Create CAT with EAP and normal prior
cat = CatEx.CAT.new(
  method: "EAP",
  prior_dist: "norm",
  prior_par: [0, 1],  # mean=0, sd=1
  min_theta: -4,
  max_theta: 4
)

# Or use uniform prior
cat = CatEx.CAT.new(
  method: "EAP",
  prior_dist: "unif",
  prior_par: [-3, 3]
)
```

### Multi-CAT with Clowder

```elixir
alias CatEx.Clowder

# Define CAT configurations
cat_configs = %{
  reading: [method: "MLE", theta: 0.5],
  math: [method: "EAP", prior_dist: "norm", prior_par: [0, 1]]
}

# Create corpus with multi-zeta stimuli
corpus = [
  %{
    id: "item1",
    stimulus: "What is 2+2?",
    zetas: [
      %{cats: [:math], zeta: %{a: 1, b: 0, c: 0, d: 1}},
      %{cats: [:reading], zeta: %{a: 0.5, b: -1, c: 0.2, d: 1}}
    ]
  }
]

# Create Clowder
clowder = Clowder.new(
  cats: cat_configs,
  corpus: corpus,
  random_seed: "test-seed"
)

# Update and get next item
{clowder, next_item} = Clowder.update_and_select(
  clowder,
  cat_to_select: :math,
  items: [Enum.at(corpus, 0)],
  answers: [1]
)
```

### Early Stopping

```elixir
alias CatEx.Stopping

# Stop after 20 items
stopping = Stopping.StopAfterNItems.new(%{reading: 20, math: 20})

# Stop when SE plateaus
stopping = Stopping.StopOnSEPlateau.new(
  %{reading: 5, math: 5},     # patience (number of items to check)
  %{reading: 0.01, math: 0.02} # tolerance
)

# Stop when SE drops below threshold
stopping = Stopping.StopIfSEBelowThreshold.new(
  %{reading: 0.5, math: 0.5},   # threshold
  patience: %{reading: 3, math: 3},
  tolerance: %{reading: 0.05, math: 0.05}
)

# Use with Clowder
clowder = Clowder.new(
  cats: cat_configs,
  corpus: corpus,
  early_stopping: stopping
)
```

## API Reference

### CatEx.CAT

#### `new/1`
Create a new CAT instance.

**Options:**
- `method`: Ability estimator ("MLE" or "EAP"), default: "MLE"
- `item_select`: Selection method ("MFI", "random", "closest", "fixed"), default: "MFI"
- `n_start_items`: Number of non-adaptive start items, default: 0
- `start_select`: Selection for start items ("random", "middle", "fixed"), default: "middle"
- `theta`: Initial ability estimate, default: 0.0
- `min_theta`: Minimum theta value, default: -6.0
- `max_theta`: Maximum theta value, default: 6.0
- `prior_dist`: Prior distribution for EAP ("norm" or "unif"), default: "norm"
- `prior_par`: Prior parameters, default: [0, 1] for norm, [-4, 4] for unif
- `random_seed`: Seed for reproducible randomization

#### `update_ability_estimate/3`
Update ability estimate based on responses.

```elixir
# Single item
CAT.update_ability_estimate(cat, %{a: 1, b: 0, c: 0, d: 1}, 1)

# Multiple items
CAT.update_ability_estimate(cat, [zeta1, zeta2], [1, 0])
```

#### `find_next_item/3`
Find next item from available stimuli.

```elixir
{next_stimulus, remaining_stimuli} = CAT.find_next_item(cat, stimuli, "MFI")
```

### CatEx.Utils

#### `item_response_function/2`
Calculate 4PL item response probability.

```elixir
prob = Utils.item_response_function(0.5, %{a: 1, b: 0, c: 0.2, d: 0.9})
```

#### `fisher_information/2`
Calculate Fisher information at given theta.

```elixir
info = Utils.fisher_information(0.5, %{a: 1, b: 0, c: 0, d: 1})
```

### CatEx.Corpus

#### `prepare_clowder_corpus/4`
Convert stimulus array with prefixed parameters to MultiZetaStimulus format.

```elixir
items = [
  %{"math.a" => 1, "math.b" => 0, "reading.a" => 0.5, stimulus: "item1"}
]
corpus = Corpus.prepare_clowder_corpus(items, ["math", "reading"], ".", :symbolic)
```

## Implementation Status

### Core Features (✅ Complete)
- [x] 4PL Item Response Function
- [x] Fisher Information calculation
- [x] MLE with Powell optimization (multi-start)
- [x] EAP with normal/uniform priors
- [x] All item selection methods (MFI, Random, Closest, Fixed, Middle)
- [x] Standard error calculation
- [x] Parameter validation

### Clowder Multi-CAT (✅ Complete)
- [x] Multi-zeta stimulus support
- [x] Corpus filtering and validation
- [x] Unvalidated item handling
- [x] Cross-corpus selection
- [x] Early stopping integration

### Early Stopping (✅ Complete)
- [x] StopAfterNItems
- [x] StopOnSEPlateau
- [x] StopIfSEBelowThreshold
- [x] Logical operations (AND, OR, ONLY)

### Testing (✅ 100% Passing)
- [x] Core CAT functionality: 50+ tests
- [x] Utility functions: 40+ tests
- [x] Corpus management: 30+ tests
- [x] Stopping mechanisms: 40+ tests
- [x] Clowder integration: 27 tests

**Test Statistics:**
```
Total: 143 tests (141 tests + 2 doctests)
Passing: 143 (100%)
Failing: 0
```

### Differences from jsCAT

1. **MLE Optimization**: Uses custom Powell/Brent implementation instead of optimization-js library
   - Multi-start strategy (4 starting points) for better global optimization
   - Brent's method with parabolic interpolation for line minimization
   - Comparable accuracy to original

2. **Fisher Information Guard**: Adds a protective `p <= c or p >= d` guard returning 0.0, preventing NaN/Infinity in edge cases (jsCAT does not guard against this)

3. **Log-Likelihood Protection**: Uses `max(p, 1e-10)` to prevent `log(0)` crashes

4. **Deep Copy**: Elixir's immutable data structures eliminate the need for deep copy operations

5. **Type Safety**: Leverages Elixir's pattern matching, guards, and struct system

6. **Duck-Typed `n_items/1`**: Accepts both `%CAT{}` structs and any map with an `:n_items` key, enabling easier testing and interoperability with stopping mechanisms

## Project Structure

```
cat_ex/
├── lib/
│   └── cat_ex/
│       ├── cat.ex          # Core CAT functionality (MLE/EAP)
│       ├── clowder.ex      # Multi-CAT management
│       ├── corpus.ex       # Corpus utilities
│       ├── optimization.ex # Powell optimization (Brent's method)
│       ├── stopping.ex     # Early stopping strategies
│       └── utils.ex        # IRT calculations
├── test/
│   └── cat_ex/
│       ├── cat_test.exs
│       ├── clowder_test.exs
│       ├── corpus_test.exs
│       ├── stopping_test.exs
│       └── utils_test.exs
├── mix.exs
├── README.md
└── LICENSE
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Citation

If you use CatEx in your research or applications, please cite the original jsCAT work:

**BibTeX:**
```bibtex
@article{ma2025roar,
  title={ROAR-CAT: Rapid Online Assessment of Reading ability with Computerized Adaptive Testing},
  author={Ma, Wanjing Anya and Richie-Halford, Adam and Burkhardt, Amy K and Kanopka, Klint and Chou, Clementine and Domingue, Benjamin W and Yeatman, Jason D},
  journal={Behavior Research Methods},
  volume={57},
  number={1},
  pages={1--17},
  year={2025},
  publisher={Springer},
  doi={10.3758/s13428-024-02578-y}
}
```

**APA:**
Ma, W. A., Richie-Halford, A., Burkhardt, A. K., Kanopka, K., Chou, C., Domingue, B. W., & Yeatman, J. D. (2025). ROAR-CAT: Rapid Online Assessment of Reading ability with Computerized Adaptive Testing. *Behavior Research Methods*, *57*(1), 1-17. https://doi.org/10.3758/s13428-024-02578-y

## References

- Ma, W. A., et al. (2025). ROAR-CAT: Rapid Online Assessment of Reading ability with Computerized Adaptive Testing. *Behavior Research Methods*, 57(1), 1-17. https://doi.org/10.3758/s13428-024-02578-y
- Original jsCAT: https://github.com/yeatmanlab/jsCAT
- van der Linden, W. J., & Glas, C. A. W. (Eds.). (2010). *Elements of Adaptive Testing*. Springer.

## License

MIT License - see [LICENSE](LICENSE) file.

## Credits

**Maintained by:** [Lulucat Innovations](https://github.com/lulucatinnovations)

This is a port of the excellent jsCAT library by the Yeatman Lab. All core algorithms and methodology are based on their original work.

Copyright (c) 2024 Lulucat Innovations. Released under the MIT License.

---

# CatEx (中文文档)

[![Elixir CI](https://img.shields.io/badge/Elixir-1.15+-purple.svg)](https://elixir-lang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![By Lulucat](https://img.shields.io/badge/By-Lulucat%20Innovations-orange.svg)](https://github.com/lulucatinnovations)

Elixir 计算机自适应测试（CAT）库 - 完整移植自 [jsCAT](https://github.com/yeatmanlab/jsCAT)。

**由 [Lulucat Innovations](https://github.com/lulucatinnovations) 维护**

CatEx 为教育与心理测评提供基于项目反应理论（IRT）的计算机自适应测试功能。实现了最大似然估计（MLE）和期望后验估计（EAP）能力估计算法，配合 Powell 优化、多种选题策略及完善的早停机制。

## 功能特性

### 核心 CAT 功能
- **能力估计**：MLE（最大似然估计，使用 Powell 优化）和 EAP（期望后验估计，支持自定义先验分布）
- **项目反应理论**：完整的四参数 Logistic（4PL）模型支持
  - 区分度（a）
  - 难度（b）
  - 猜测（c）
  - 失误（d）
- **Fisher 信息量**：用于最优选题的信息量计算

### 选题方法
- **MFI**（最大 Fisher 信息量）：选择在当前能力估计处信息量最大的题目
- **Closest**：选择难度与当前 theta 最接近的题目
- **Random**：随机选题，支持可选种子以实现可复现性
- **Fixed**：按题库顺序依次选题
- **Middle**：从难度范围中间选题（适用于起始题目）

### 多 CAT 管理（Clowder）
- 同时管理多个 CAT 实例
- 多 zeta 刺激支持（不同 CAT 使用不同的 IRT 参数）
- 未验证题目处理
- 跨题库选题

### 早停机制
- **StopAfterNItems**：在施测指定数量的题目后停止
- **StopOnSEPlateau**：当测量标准误趋于稳定时停止
- **StopIfSEBelowThreshold**：当精度达到阈值时停止
- **逻辑运算**：AND、OR、ONLY 用于组合多个停止条件

### 先验分布（用于 EAP）
- 正态分布，可自定义均值和标准差
- 均匀分布，可自定义边界
- 基于 theta 范围自动生成网格

## 安装

在 `mix.exs` 中添加 `cat_ex` 依赖：

```elixir
def deps do
  [
    {:cat_ex, "~> 0.1.0"}
  ]
end
```

然后运行：

```bash
mix deps.get
```

## 快速上手

### 基本 CAT 用法

```elixir
alias CatEx.CAT

# 创建使用 MLE 估计器的 CAT 实例
cat = CAT.new(
  method: "MLE",
  item_select: "MFI",
  theta: 0.0,
  min_theta: -6.0,
  max_theta: 6.0
)

# 定义带有题目参数的刺激（4PL 模型）
stimuli = [
  %{a: 1.0, b: -1.0, c: 0.2, d: 1.0, word: "easy"},
  %{a: 1.5, b: 0.0, c: 0.25, d: 0.95, word: "medium"},
  %{a: 2.0, b: 2.0, c: 0.3, d: 0.9, word: "hard"}
]

# 根据作答更新能力估计（1 = 正确，0 = 错误）
cat = CAT.update_ability_estimate(cat, Enum.at(stimuli, 0), 1)

# 使用 MFI 策略获取下一题
{next_item, remaining} = CAT.find_next_item(cat, stimuli)

# 查看当前状态
CatEx.CAT.n_items(cat)          # 已施测题目数
cat.theta                         # 当前能力估计
cat.se_measurement                # 测量标准误
```

### EAP 估计与先验

```elixir
# 创建使用 EAP 和正态先验的 CAT
cat = CatEx.CAT.new(
  method: "EAP",
  prior_dist: "norm",
  prior_par: [0, 1],  # 均值=0, 标准差=1
  min_theta: -4,
  max_theta: 4
)

# 或使用均匀先验
cat = CatEx.CAT.new(
  method: "EAP",
  prior_dist: "unif",
  prior_par: [-3, 3]
)
```

### 使用 Clowder 进行多 CAT 管理

```elixir
alias CatEx.Clowder

# 定义 CAT 配置
cat_configs = %{
  reading: [method: "MLE", theta: 0.5],
  math: [method: "EAP", prior_dist: "norm", prior_par: [0, 1]]
}

# 创建多 zeta 刺激题库
corpus = [
  %{
    id: "item1",
    stimulus: "2+2 等于几？",
    zetas: [
      %{cats: [:math], zeta: %{a: 1, b: 0, c: 0, d: 1}},
      %{cats: [:reading], zeta: %{a: 0.5, b: -1, c: 0.2, d: 1}}
    ]
  }
]

# 创建 Clowder
clowder = Clowder.new(
  cats: cat_configs,
  corpus: corpus,
  random_seed: "test-seed"
)

# 更新并获取下一题
{clowder, next_item} = Clowder.update_and_select(
  clowder,
  cat_to_select: :math,
  items: [Enum.at(corpus, 0)],
  answers: [1]
)
```

### 早停

```elixir
alias CatEx.Stopping

# 施测 20 题后停止
stopping = Stopping.StopAfterNItems.new(%{reading: 20, math: 20})

# 当标准误趋于稳定时停止
stopping = Stopping.StopOnSEPlateau.new(
  %{reading: 5, math: 5},     # 耐心值（检查的题目数量）
  %{reading: 0.01, math: 0.02} # 容差
)

# 当标准误低于阈值时停止
stopping = Stopping.StopIfSEBelowThreshold.new(
  %{reading: 0.5, math: 0.5},   # 阈值
  patience: %{reading: 3, math: 3},
  tolerance: %{reading: 0.05, math: 0.05}
)

# 配合 Clowder 使用
clowder = Clowder.new(
  cats: cat_configs,
  corpus: corpus,
  early_stopping: stopping
)
```

## 实现状态

### 核心功能（✅ 完成）
- [x] 4PL 项目反应函数
- [x] Fisher 信息量计算
- [x] MLE 与 Powell 优化（多起点）
- [x] EAP 与正态/均匀先验
- [x] 所有选题方法（MFI、Random、Closest、Fixed、Middle）
- [x] 标准误计算
- [x] 参数验证

### Clowder 多 CAT（✅ 完成）
- [x] 多 zeta 刺激支持
- [x] 题库筛选与验证
- [x] 未验证题目处理
- [x] 跨题库选题
- [x] 早停集成

### 早停机制（✅ 完成）
- [x] StopAfterNItems
- [x] StopOnSEPlateau
- [x] StopIfSEBelowThreshold
- [x] 逻辑运算（AND、OR、ONLY）

### 测试（✅ 100% 通过）
- [x] 核心 CAT 功能：50+ 测试
- [x] 工具函数：40+ 测试
- [x] 题库管理：30+ 测试
- [x] 早停机制：40+ 测试
- [x] Clowder 集成：27 测试

**测试统计：**
```
总计：143 测试（141 测试 + 2 文档测试）
通过：143（100%）
失败：0
```

### 与 jsCAT 的差异

1. **MLE 优化**：使用自定义 Powell/Brent 实现替代 optimization-js 库
   - 多起点策略（4 个起始点）以获得更好的全局优化
   - 使用 Brent 方法配合抛物线插值进行线搜索
   - 精度与原版相当

2. **Fisher 信息量保护**：添加了 `p <= c or p >= d` 保护返回 0.0，防止边界情况下的 NaN/Infinity（jsCAT 无此保护）

3. **对数似然保护**：使用 `max(p, 1e-10)` 防止 `log(0)` 崩溃

4. **深拷贝**：Elixir 的不可变数据结构消除了深拷贝操作的需要

5. **类型安全**：利用 Elixir 的模式匹配、守卫和结构体系统

6. **鸭子类型 `n_items/1`**：同时接受 `%CAT{}` 结构体和任何带有 `:n_items` 键的 map，便于测试和与早停机制的互操作

## 引用

如果您在研究或应用中使用了 CatEx，请引用原始 jsCAT 论文：

Ma, W. A., Richie-Halford, A., Burkhardt, A. K., Kanopka, K., Chou, C., Domingue, B. W., & Yeatman, J. D. (2025). ROAR-CAT: Rapid Online Assessment of Reading ability with Computerized Adaptive Testing. *Behavior Research Methods*, *57*(1), 1-17. https://doi.org/10.3758/s13428-024-02578-y

## 许可证

MIT 许可证 - 详见 [LICENSE](LICENSE) 文件。

## 致谢

**维护者：** [Lulucat Innovations](https://github.com/lulucatinnovations)

本项目移植自 Yeatman Lab 的优秀 jsCAT 库。所有核心算法和方法论均基于其原始工作。

Copyright (c) 2024 Lulucat Innovations. 基于 MIT 许可证发布。
