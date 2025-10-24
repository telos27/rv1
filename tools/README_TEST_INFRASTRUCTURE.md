# Test Infrastructure Tools

**Created**: 2025-10-23
**Status**: ✅ Production Ready

This document describes the new test infrastructure tools for easier test execution and organization.

---

## Quick Start

### Run a single test
```bash
# Custom test
./tools/run_test_by_name.sh fibonacci

# Official compliance test
./tools/run_test_by_name.sh rv32ui-p-add --official

# With debug output and waveforms
./tools/run_test_by_name.sh test_fp_basic --debug --waves
```

### Run tests by category
```bash
# Run all M extension tests
./tools/run_tests_by_category.sh m

# Run official RV32UM tests
./tools/run_tests_by_category.sh official --extension rv32um

# Run with verbose output
./tools/run_tests_by_category.sh f --verbose
```

### Using Makefile shortcuts
```bash
# Run individual test
make test-one TEST=fibonacci
make test-one TEST=rv32ui-p-add OFFICIAL=1

# Run by extension
make test-m              # M extension tests
make test-a              # A extension tests
make test-f              # F extension tests
make test-d              # D extension tests
make test-fp             # All FP tests (F+D)

# Run official tests
make test-official EXT=rv32um
make test-all-official   # All 81 tests (takes ~5 minutes)
```

---

## Tool 1: run_test_by_name.sh

**Purpose**: Run individual RISC-V tests by name with flexible options

**Location**: `tools/run_test_by_name.sh`

### Usage
```bash
./tools/run_test_by_name.sh <test_name> [options]
```

### Options
- `--official` - Run official compliance test (searches in tests/official-compliance/)
- `--debug` - Enable debug output (DEBUG_CORE, DEBUG_FPU, DEBUG_M)
- `--waves` - Generate waveform files (VCD)
- `--timeout <sec>` - Set timeout in seconds (default: 10)
- `--rv64` - Use RV64 configuration (default: RV32)
- `--help` - Show help message

### Examples
```bash
# Basic usage
./tools/run_test_by_name.sh fibonacci

# Official test with 5s timeout
./tools/run_test_by_name.sh rv32ui-p-add --official --timeout 5

# Debug with waveforms
./tools/run_test_by_name.sh test_m_basic --debug --waves

# RV64 test
./tools/run_test_by_name.sh test_rv64i_basic --rv64
```

### Features
- ✅ Automatic test discovery (searches custom and official test directories)
- ✅ Automatic assembly and compilation for custom tests
- ✅ Color-coded output (green=pass, red=fail, yellow=timeout)
- ✅ Detailed error messages with hints
- ✅ Waveform generation for debugging
- ✅ Architecture detection (RV32/RV64, with/without extensions)

---

## Tool 2: run_tests_by_category.sh

**Purpose**: Run multiple tests organized by category or extension

**Location**: `tools/run_tests_by_category.sh`

### Usage
```bash
./tools/run_tests_by_category.sh <category> [options]
```

### Categories
- `base` - RV32I/RV64I base instructions
- `m` - M extension (multiply/divide)
- `a` - A extension (atomics: LR/SC, AMO)
- `f` - F extension (single-precision FP)
- `d` - D extension (double-precision FP)
- `c` - C extension (compressed)
- `csr` - CSR and Zicsr tests
- `privilege` - Privilege modes (M/S/U)
- `mmu` - Virtual memory/MMU tests
- `hazards` - Pipeline hazard tests
- `fp` - All floating-point (F+D)
- `official` - Official compliance tests
- `all` - All custom tests

### Options
- `--extension <ext>` - For 'official' category, specify extension (rv32ui, rv32um, etc.)
- `--verbose` - Show detailed output for each test
- `--timeout <sec>` - Set timeout per test (default: 10)
- `--continue` - Continue on failure (don't stop at first failure)
- `--help` - Show help message

### Examples
```bash
# Run M extension tests
./tools/run_tests_by_category.sh m

# Run official RV32UM tests
./tools/run_tests_by_category.sh official --extension rv32um

# Run all FP tests with verbose output
./tools/run_tests_by_category.sh fp --verbose

# Run all tests, continue on failure
./tools/run_tests_by_category.sh all --continue --timeout 5
```

### Features
- ✅ Smart test categorization by extension and type
- ✅ Pass/fail statistics with percentages
- ✅ Failed test reporting
- ✅ Parallel-safe (runs tests sequentially for clear output)
- ✅ Color-coded results
- ✅ Optional verbose mode for debugging

---

## Makefile Integration

New targets have been added to the Makefile for easy access.

### Individual Test Execution
```bash
make test-one TEST=<name>              # Custom test
make test-one TEST=<name> OFFICIAL=1   # Official test
```

### Category-Based Testing
```bash
make test-m        # M extension
make test-a        # A extension
make test-f        # F extension
make test-d        # D extension
make test-c        # C extension
make test-fp       # All FP (F+D)
make test-priv     # Privilege modes
```

### Official Compliance Testing
```bash
make test-official EXT=rv32ui   # RV32I base (42 tests)
make test-official EXT=rv32um   # RV32M (8 tests)
make test-official EXT=rv32ua   # RV32A (10 tests)
make test-official EXT=rv32uf   # RV32F (11 tests)
make test-official EXT=rv32ud   # RV32D (9 tests)
make test-official EXT=rv32uc   # RV32C (1 test)

make test-all-official          # All 81 tests (~5 minutes)
```

---

## Test Discovery

### Custom Tests
The scripts search for custom tests in:
1. `tests/custom/**/*.s` (future organized structure)
2. `tests/asm/*.s` (current structure)

### Official Tests
Official compliance tests are located in:
- `tests/official-compliance/*.hex`

Pattern matching:
- `rv32ui-*` - Base integer
- `rv32um-*` - Multiply/divide
- `rv32ua-*` - Atomics
- `rv32uf-*` - Single-precision FP
- `rv32ud-*` - Double-precision FP
- `rv32uc-*` - Compressed

---

## Output Examples

### Successful Test
```
========================================
RISC-V Test Runner
========================================
Test: fibonacci
XLEN: 32
Timeout: 10s

[1/3] Searching custom tests...
Found: /home/lei/rv1/tests/asm/fibonacci.s

Building test...
✓ Success!

[2/3] Compiling simulation...
✓ Compilation successful

[3/3] Running simulation...
----------------------------------------
[Test output...]
----------------------------------------

✓ Test PASSED: fibonacci
```

### Category Summary
```
========================================
Test Summary
========================================
Category: official
Total tests: 8
Passed: 8
Failed: 0
Timeout: 0

Pass rate: 100% (8/8)
✓ All tests passed!
```

---

## Tips & Tricks

### Quick Verification After Changes
```bash
# Quick test of M extension after modifying multiplier
make test-official EXT=rv32um

# Test FP after FPU changes
make test-fp
```

### Debugging Failing Tests
```bash
# Run with debug output
./tools/run_test_by_name.sh test_m_basic --debug

# Generate waveforms
./tools/run_test_by_name.sh test_m_basic --waves
gtkwave sim/waves/test_m_basic.vcd
```

### Running Comprehensive Validation
```bash
# Run all official tests (100% compliance check)
make test-all-official

# Should show: 81/81 PASSING
```

### Handling Slow Tests
```bash
# Increase timeout for complex tests
./tools/run_test_by_name.sh dhrystone --timeout 30

# Category with longer timeout
./tools/run_tests_by_category.sh benchmarks --timeout 30
```

---

## Troubleshooting

### Test Times Out
- Increase timeout: `--timeout 30`
- Check if test has proper termination (ECALL or similar)
- Generate waveforms to see where it hangs: `--waves`

### Test Not Found
- Check test name (case-sensitive)
- Custom tests should be in `tests/asm/*.s`
- Official tests should be in `tests/official-compliance/*.hex`
- List available tests: `ls tests/asm/*.s | xargs -n1 basename`

### Compilation Fails
- Verify RTL files are present
- Check for syntax errors in test assembly
- Use `--debug` to see full compilation output

### Permission Denied
- Make scripts executable: `chmod +x tools/run_test_by_name.sh tools/run_tests_by_category.sh`

---

## Future Enhancements

Potential improvements:
- [ ] Parallel test execution for faster category runs
- [ ] Test result caching
- [ ] HTML test dashboard generation
- [ ] Code coverage reporting
- [ ] Automatic regression detection
- [ ] Performance benchmarking mode

---

## See Also

- `TEST_REORGANIZATION_PLAN.md` - Full reorganization plan
- `NEXT_SESSION.md` - Session 25 goals and AMO test plan
- `CLAUDE.md` - Project overview and conventions
- `Makefile` - Build system documentation

---

**Happy Testing!** 🧪

These tools make it easy to run individual tests, verify compliance, and debug issues. Use them frequently during development to catch regressions early.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
