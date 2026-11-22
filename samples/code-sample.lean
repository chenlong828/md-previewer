/-
  Lean 4 语法高亮样例（代码视图只读展示）：块注释、属性、声明、策略与命令。
  结构取自 `samples/` 之外的真实入门演示；这里不要求可编译（无 Mathlib 依赖）。
-/

set_option linter.unusedSimpArgs false

/-! ## 前 n 个奇数之和 = n² -/

def oddSum : Nat → Nat
  | 0 => 0
  | n + 1 => oddSum n + (2*n + 1)

/-- 对 n 归纳：n = 0 用 rfl，n → n+1 用平方展开后交给 omega。 -/
theorem oddSum_eq_sq (n : Nat) : oddSum n = n^2 := by
  induction n with
  | zero => rfl
  | succ n ih =>
    simp only [oddSum, ih]
    simp [Nat.pow_succ, Nat.mul_add, Nat.mul_comm]
    omega

-- 公理审计：只应出现标准公理，不该有 sorryAx。
#print axioms oddSum_eq_sq
