defmodule CatEx.Optimization do
  @moduledoc """
  Numerical optimization for Maximum Likelihood Estimation.

  Implements Brent's method with parabolic interpolation for single-variable
  minimization, used internally by `CatEx.CAT` for MLE ability estimation.

  The optimizer:
  1. Brackets a minimum using golden section expansion
  2. Refines the bracket using Brent's method (parabolic interpolation with
     golden section fallback)

  This replaces the `optimization-js` Powell minimizer used by the original jsCAT.
  CatEx additionally uses a multi-start strategy (4 starting points) to improve
  the chance of finding the global minimum.

  ## Usage

  Typically you do not call this module directly. It is used internally by
  `CatEx.CAT.update_ability_estimate/3` when `method: "MLE"`.

      # Direct usage (minimize x^2 - 4x + 4)
      {x_min, f_min} = CatEx.Optimization.powell_minimize(fn x -> (x - 2) * (x - 2) end, 0.0)
      # x_min ≈ 2.0, f_min ≈ 0.0
  """

  @default_tolerance 1.0e-8
  @max_iterations 200
  @initial_step_size 1.0

  @doc """
  Performs Powell's optimization method to find the minimum of a function.

  ## Parameters
  - `func` - Function to minimize, takes a single float argument
  - `x0` - Initial guess (starting point)
  - `tolerance` - Convergence tolerance (default: 1.0e-8)
  - `max_iterations` - Maximum iterations (default: 200)

  ## Returns
  - The value of x that minimizes the function

  ## Example
      func = fn x -> :math.pow(x - 2, 2) end
      minimum = CatEx.Optimization.powell_minimize(func, 0.0)
      # minimum ≈ 2.0
  """
  def powell_minimize(
        func,
        x0,
        tolerance \\ @default_tolerance,
        max_iterations \\ @max_iterations
      ) do
    # Powell's method using Brent's method for line minimization
    # This is a simplified implementation optimized for single-variable functions

    a = x0
    fa = func.(a)

    b = a + @initial_step_size
    fb = func.(b)

    # Ensure we have a bracket
    {a, b, c, fa, fb, fc} = find_bracket(func, a, b, fa, fb)

    # Now minimize using Brent's method within the bracket
    brent_minimize(func, a, b, c, fa, fb, fc, tolerance, max_iterations, 0)
  end

  # Find a bracket containing a minimum
  defp find_bracket(func, a, b, fa, fb) when fb > fa do
    # Try the other direction
    c = a - @initial_step_size
    fc = func.(c)

    if fc > fa do
      # Local minimum is at a
      {c, a, b, fc, fa, fb}
    else
      extend_bracket(func, c, a, b, fc, fa, fb)
    end
  end

  defp find_bracket(func, a, b, fa, fb) do
    extend_bracket(func, a, b, b + @initial_step_size, fa, fb, func.(b + @initial_step_size))
  end

  defp extend_bracket(_func, a, b, c, fa, fb, fc) when fb < fc do
    # We have a good bracket [a, b, c] where fb is the minimum
    {a, b, c, fa, fb, fc}
  end

  defp extend_bracket(func, a, b, c, fa, fb, fc) do
    # Keep extending
    new_c = b + 2 * (c - b)
    new_fc = func.(new_c)

    if new_fc < fc do
      extend_bracket(func, b, c, new_c, fb, fc, new_fc)
    else
      # Last three points form a bracket
      {a, b, c, fa, fb, fc}
    end
  end

  # Brent's method for finding a minimum
  defp brent_minimize(func, a, b, c, fa, fb, fc, tolerance, max_iter, iter)
       when iter < max_iter do
    # a < b < c and fb <= fa and fb <= fc

    # Try parabolic interpolation
    if fa != fc do
      # Calculate the minimum of the parabola through (a, fa), (b, fb), (c, fc)
      p = (b - a) * (fb - fc)
      q = (b - c) * (fb - fa)

      if p != q do
        # Compute parabolic interpolation point
        xmin = b - ((b - a) * p - (b - c) * q) / (2 * (p - q))

        # Check if xmin is within the bracket and closer to b than half the interval
        _tol = tolerance * abs(b) + tolerance

        if abs(xmin - b) < 0.5 * abs(c - a) and abs(xmin - b) < abs(c - b) do
          # Evaluate at parabolic minimum
          fmin = func.(xmin)

          if fmin < fb do
            # New minimum found
            if xmin > b do
              brent_minimize(func, b, xmin, c, fb, fmin, fc, tolerance, max_iter, iter + 1)
            else
              brent_minimize(func, a, xmin, b, fa, fmin, fb, tolerance, max_iter, iter + 1)
            end
          else
            # Parabolic step didn't improve, use golden section
            golden_section_step(func, a, b, c, fa, fb, fc, tolerance, max_iter, iter)
          end
        else
          golden_section_step(func, a, b, c, fa, fb, fc, tolerance, max_iter, iter)
        end
      else
        golden_section_step(func, a, b, c, fa, fb, fc, tolerance, max_iter, iter)
      end
    else
      golden_section_step(func, a, b, c, fa, fb, fc, tolerance, max_iter, iter)
    end
  end

  defp brent_minimize(_func, _a, b, _c, _fa, fb, _fc, _tolerance, _max_iter, _iter) do
    # Return the best point found
    {b, fb}
  end

  # Golden section step when parabolic interpolation fails
  defp golden_section_step(func, a, b, c, fa, fb, fc, tolerance, max_iter, iter) do
    # Golden ratio
    # (3 - sqrt(5)) / 2
    golden = 0.3819660113

    # Choose the larger subinterval
    if abs(b - a) > abs(c - b) do
      x = b - golden * (b - a)
      fx = func.(x)

      if fx < fb do
        brent_minimize(func, a, x, b, fa, fx, fb, tolerance, max_iter, iter + 1)
      else
        brent_minimize(func, x, b, c, fx, fb, fc, tolerance, max_iter, iter + 1)
      end
    else
      x = b + golden * (c - b)
      fx = func.(x)

      if fx < fb do
        brent_minimize(func, b, x, c, fb, fx, fc, tolerance, max_iter, iter + 1)
      else
        brent_minimize(func, a, b, x, fa, fb, fx, tolerance, max_iter, iter + 1)
      end
    end
  end

  @doc """
  Maximizes a function using Powell's method.
  Simply negates the function and minimizes.
  """
  def powell_maximize(
        func,
        x0,
        tolerance \\ @default_tolerance,
        max_iterations \\ @max_iterations
      ) do
    neg_func = fn x -> -func.(x) end
    powell_minimize(neg_func, x0, tolerance, max_iterations)
  end
end
