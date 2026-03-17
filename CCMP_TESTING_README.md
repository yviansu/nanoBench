# APX ccmp Performance Testing Guide

This guide explains how to test and compare the performance of Intel APX's `ccmp` (Conditional Compare) instruction against traditional `cmp + conditional jump` patterns.

## What is ccmp?

**ccmp** (Conditional Compare) is a new instruction in Intel's APX (Advanced Performance Extensions) that performs conditional comparisons **without branching**.

### ccmp Pseudocode

```
IF (current_flags satisfy condition):
    flags = compare(operand1, operand2)
ELSE:
    flags = default_flags_value  // specified in instruction encoding
```

### Key Benefits

1. **Eliminates branch instructions** → No `BR_INST_RETIRED`
2. **Eliminates branch mispredictions** → No `BR_MISP_RETIRED`
3. **Reduces pipeline stalls** → Lower `CORE_CYCLES` in unpredictable scenarios
4. **Enables instruction chaining** → Multiple conditions without branches

## Test Scripts

### 1. Quick Test (`test_ccmp_quick.sh`)

**Purpose**: Fast comparison of the most important scenarios.

**Usage**:
```bash
sudo ./test_ccmp_quick.sh
```

**Tests**:
- Unpredictable branch pattern (alternating 0/1)
- Condition chains (A && B && C)
- Random branches (rdtsc-based)

**Output**: Displays key metrics side-by-side for easy comparison.

### 2. Comprehensive Test (`test_ccmp_vs_branch.sh`)

**Purpose**: Detailed testing across multiple scenarios with full results.

**Usage**:
```bash
sudo ./test_ccmp_vs_branch.sh [CPU_CONFIG]

# Examples:
sudo ./test_ccmp_vs_branch.sh Skylake
sudo ./test_ccmp_vs_branch.sh AlderLakeP
```

**Tests**:
1. Predictable branches (best case for branch predictor)
2. Unpredictable alternating pattern
3. Complex condition chains
4. Random patterns (worst case)
5. Nested conditions with early exit
6. Branches with side effects

**Output**: Creates `ccmp_benchmark_results.txt` with detailed results.

## Understanding the Results

### Key Performance Counters

| Counter | Meaning | ccmp Expected |
|---------|---------|---------------|
| `BR_INST_RETIRED.ALL_BRANCHES` | Total branch instructions executed | **Much lower or 0** |
| `BR_MISP_RETIRED.ALL_BRANCHES` | Branch mispredictions | **0** |
| `CORE_CYCLES` | CPU cycles consumed | **Lower in unpredictable cases** |
| `INST_RETIRED.ANY` | Total instructions retired | Similar or lower |
| `UOPS_ISSUED.ANY` | Micro-ops issued | Compare for efficiency |

### Example Results Interpretation

**Scenario: Unpredictable alternating pattern**

Traditional (cmp + jmp):
```
BR_INST_RETIRED: 10.00
BR_MISP_RETIRED: 5.00     ← 50% misprediction!
CORE_CYCLES: 45.00
```

APX ccmp:
```
BR_INST_RETIRED: 0.00     ← No branches!
BR_MISP_RETIRED: 0.00     ← No mispredictions!
CORE_CYCLES: 25.00        ← ~44% faster
```

## Test Scenarios Explained

### Test 1: Predictable Branches
```asm
Traditional: cmp rax, rbx; je target
ccmp:        cmp rax, rbx; ccmpe rcx, rdx, 0
```
**Expected**: Similar performance (branch predictor works well on predictable patterns).

### Test 2: Unpredictable Pattern (0xAAAA...)
```asm
# 0xAAAAAAAAAAAAAAAA = binary 1010101010...
# Creates perfect alternating pattern (unpredictable)
Traditional: bt r15, 0; jnc skip; cmp rax, rbx; skip: ror r15, 1
ccmp:        bt r15, 0; ccmpc rax, rbx, 0; ror r15, 1
```
**Expected**: ccmp significantly faster (~30-50% cycle reduction).

### Test 3: Condition Chains (A && B && C)
```asm
Traditional: cmp A, B; jne end; cmp C, D; jne end; cmp E, F; end:
ccmp:        cmp A, B; ccmpe C, D, 0; ccmpe E, F, 0
```
**Expected**: ccmp eliminates multiple branch points.

## ccmp Instruction Variants

Based on `ccmp-spec.md`:

### Syntax
```asm
ccmp<condition> operand1, operand2, dfv

where:
  <condition> = condition code (e, ne, l, g, le, ge, a, b, ae, be, etc.)
  operand1    = register or memory
  operand2    = register or immediate
  dfv         = default flags value (0-15, sets NZCV bits if condition false)
```

### Common Patterns

#### 1. Simple Conditional Compare
```asm
cmp rax, rbx      ; Set flags
ccmpe rcx, rdx, 0 ; If ZF=1 (equal), compare rcx with rdx
```

#### 2. Chained Conditions (A && B && C)
```asm
cmp rax, rbx       ; Compare A and B
ccmpe rcx, rdx, 0  ; If equal, compare C and D
ccmpe r8, r9, 0    ; If still equal, compare E and F
jne not_all_equal  ; Single branch at the end (optional)
```

## When to Use ccmp

### ✅ Good Use Cases
- **Unpredictable branches** (data-dependent)
- **Condition chains** (if A && B && C)
- **Hot paths** with branch misprediction issues
- **Predicated execution** patterns

### ❌ Less Beneficial
- **Highly predictable branches** (counters, loops)
- **Single conditions** in cold code
- **Complex control flow** with side effects

## Requirements

- **CPU**: Intel CPU with APX support (or assembler that supports APX instructions)
- **OS**: Linux with nanoBench installed
- **Privileges**: Root (for accessing performance counters)
- **Tools**: msr-tools (`sudo apt install msr-tools`)

## References

- [ccmp-spec.md](ccmp-spec.md) - ccmp instruction specification
- [nanoBench Paper](https://arxiv.org/abs/1911.03282) - nanoBench methodology
- [Intel APX Documentation](https://www.intel.com/content/www/us/en/developer/articles/technical/advanced-performance-extensions-apx.html)
