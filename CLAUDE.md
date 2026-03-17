# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

nanoBench is a Linux-based tool for running microbenchmarks on Intel and AMD x86 CPUs using hardware performance counters. It measures instruction latency, throughput, and port usage with minimal overhead. The tool powers the data on uops.info.

## Architecture

### Two Implementations

The codebase has **two separate implementations** that share common code:

1. **User-space variant** (`user/`) - Safer, but limited to unprivileged instructions
2. **Kernel module** (`kernel/`) - Can benchmark privileged instructions and use uncore counters, but risky on production systems

**Shared code**: `common/nanoBench.c` and `common/nanoBench.h` contain the core benchmarking logic used by both variants.

### Key Architecture Concepts

- **Runtime code generation**: The tool generates x86 machine code at runtime by copying measurement templates and inserting user-provided code
- **Magic bytes**: Special 64-bit constants (e.g., `MAGIC_BYTES_CODE`, `MAGIC_BYTES_RUNTIME_R14`) are used as placeholders in templates, replaced with actual values/addresses during code generation
- **Measurement templates**: Assembly functions in `common/nanoBench.c` that read performance counters, execute benchmarked code, and read counters again. Different templates for Intel/AMD, with/without memory access (`noMem` variants)
- **Register initialization**: R14, RDI, RSI, RSP, RBP point to dedicated 1MB writable memory regions during benchmarks
- **Unrolling**: User code is copied multiple times (controlled by `-unroll_count`) to amortize measurement overhead

### Directory Structure

- `common/` - Core implementation shared by both variants
- `user/` - User-space implementation and Makefile
- `kernel/` - Kernel module implementation and Makefile
- `configs/` - Performance counter event definitions for different CPU microarchitectures
- `tools/CacheAnalyzer/` - Python tools for cache analysis experiments
- `tools/cpuBench/` - Tools for comprehensive instruction benchmarking
- `tools/CPUID/` - CPUID utilities

## Building

### User-space version
```bash
make user
# or
cd user && make
```
Output: `user/nanoBench` binary

### Kernel module
```bash
make kernel
# or
cd kernel && make
```
Output: `kernel/nb.ko` kernel module

Requires: Linux kernel headers at `/lib/modules/$(uname -r)/build`

### Build both
```bash
make
```

### Clean
```bash
make clean
```

## Running Benchmarks

### Prerequisites
- Root privileges required
- Install msr-tools: `sudo apt install msr-tools`
- Secure Boot may need to be disabled
- For kernel module: `sudo insmod kernel/nb.ko` (required after every reboot)

### User-space Benchmarks

**Always use the wrapper script `nanoBench.sh`**, not the binary directly. The script handles assembly → machine code conversion.

```bash
sudo ./nanoBench.sh -asm "ADD RAX, RBX" -config configs/cfg_Skylake_common.txt
```

The script uses `utils.sh:assemble()` function to convert Intel syntax assembly to machine code using `as` and `objcopy`.

### Kernel Module Benchmarks

Use `kernel-nanoBench.sh` (bash wrapper) or `kernelNanoBench.py` (Python wrapper):

```bash
sudo ./kernel-nanoBench.sh -asm "ADD RAX, RBX" -config configs/cfg_Skylake_common.txt
```

### Cycle-by-Cycle Measurements

Intel CPUs only. Uses Freeze_Perfmon_On_PMI feature:

```bash
sudo ./cycleByCycle.py -asm "MOVQ XMM0, RAX; MOVQ RAX, XMM0" -config configs/cfg_Skylake_common.txt
```

## Important Code Patterns

### Assembly Syntax Extensions

Beyond standard Intel syntax, the tool supports:
- `|n` - n-byte NOP (1 ≤ n ≤ 15)
- `n*|code|` - Unroll code n times (no nesting)

Example: `5*|ADD RAX, 1|` expands to 5 ADD instructions

### Performance Counter Config Files

Format: `EvtSel.UMASK(.CMSK=...)(.CTR=...) EventName`

Files in `configs/` are organized by CPU microarchitecture:
- `cfg_<uarch>_common.txt` - Common events
- `cfg_<uarch>_all_core.txt` - All core events
- `cfg_<uarch>_all_offcore.txt` - All offcore events

### MSR Config Files (Kernel Module Only)

For uncore/RAPL counters that require RDMSR:

Format: `msr_<addr>=<val>(.msr_<addr>=<val>)* msr_<read_addr> EventName`

### Code Conventions

- The tool uses **Intel syntax** for assembly (not AT&T)
- Assembly templates use `.intel_syntax noprefix` directive
- The codebase supports both `__KERNEL__` (kernel module) and user-space compilation via conditional compilation
- Measurement templates must not use global variables or RIP-relative addressing (they're copied to runtime-allocated executable memory)

## Testing

No automated test suite is present. Testing is done by running benchmarks on actual hardware and comparing results to expected values for known instructions.

## Debugging

User-space only: Add `-debug` flag to run under gdb with a breakpoint before final counter read.

## Helper Scripts

- `disable-HT.sh` / `enable-HT.sh` - Control hyperthreading
- `single-core-mode.sh` - Disable all cores except one
- `set-R14-size.sh` - Configure R14 memory region size (kernel module)
- `utils.sh` - Shell functions used by wrapper scripts (includes `assemble()`)

## Cache Analyzer Tools

Located in `tools/CacheAnalyzer/`. Requires:
1. Kernel module loaded
2. Large physically-contiguous memory: `sudo ./set-R14-size.sh 1G`
3. Plotly for graphing: `pip install plotly`

Key tools:
- `cacheSeq.py` - Measure hits/misses for access sequences
- `replPolicy.py` - Determine cache replacement policy
- `strideGraph.py` - Generate stride-based access graphs
- `cacheInfo.py` - Combine CPUID + measured slice count

## Platform Support

- Intel CPUs: Architectural performance monitoring version ≥ 2
- AMD CPUs: Family 17h
- Cycle-by-cycle: Intel CPUs with ≥ 4 programmable counters
- Tested on Ubuntu 18.04 and 20.04
