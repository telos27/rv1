# Test Infrastructure Reorganization Plan

**Date**: 2025-10-23
**Status**: Proposal
**Current State**: 100% RISC-V Compliance (81/81 tests), 115+ custom tests
**Assessment**: Infrastructure Grade A- (Excellent with minor improvements)

---

## Executive Summary

The RV1 test infrastructure is **production-ready** with 100% compliance and excellent coverage. This plan proposes **non-breaking reorganization** to improve:
1. **Discoverability** - Easier to find and run specific tests
2. **Maintainability** - Clear organization by test type and extension
3. **Debugging** - Better tools for individual test analysis
4. **Coverage** - Identify and fill small gaps

**Philosophy**: Incremental improvements, preserve what works, no regression risk.

---

## Current State Analysis

### Strengths ✅
- 100% official RISC-V compliance (81/81 tests)
- 115+ custom assembly tests covering all extensions
- Automated build/test infrastructure
- Excellent documentation (20+ test docs)
- Multi-configuration support (RV32/RV64)

### Issues to Address ⚠️
1. **Minor**: 2 hex files missing assembly source
2. **Minor**: Some script redundancy (phase-specific scripts)
3. **Minor**: Test categorization could be clearer
4. **Enhancement**: No easy way to run tests by category
5. **Enhancement**: No test result dashboard

---

## Part 1: Test Directory Reorganization

### Current Structure
```
tests/
├── asm/              # 115 .s files (all mixed together)
├── official-compliance/  # 82 .hex files
├── bin/              # 13 compiled binaries
└── vectors/          # Empty (intended for .hex files)
```

### Proposed Structure
```
tests/
├── custom/                      # Custom assembly tests (organized by category)
│   ├── base/                    # RV32I/RV64I tests
│   │   ├── arithmetic/          # ADD, SUB, etc.
│   │   ├── logic/               # AND, OR, XOR, shifts
│   │   ├── branch/              # Branch instructions
│   │   ├── jump/                # JAL, JALR
│   │   ├── load_store/          # Memory operations
│   │   └── misc/                # FENCE, ECALL, etc.
│   ├── m_extension/             # Multiply/Divide
│   │   ├── multiply/
│   │   ├── divide/
│   │   └── hazards/
│   ├── a_extension/             # Atomic operations
│   │   ├── lr_sc/
│   │   └── amo/
│   ├── f_extension/             # Single-precision FP
│   │   ├── arithmetic/
│   │   ├── conversion/
│   │   ├── compare/
│   │   └── fma/
│   ├── d_extension/             # Double-precision FP
│   │   ├── arithmetic/
│   │   ├── conversion/
│   │   └── fma/
│   ├── c_extension/             # Compressed instructions
│   ├── zicsr/                   # CSR operations
│   ├── privilege/               # M/S/U mode tests
│   │   ├── mode_transitions/
│   │   ├── delegation/
│   │   └── exceptions/
│   ├── mmu/                     # Virtual memory
│   ├── hazards/                 # Pipeline hazards
│   ├── integration/             # Multi-extension tests
│   └── benchmarks/              # Performance tests
│       ├── fibonacci/
│       ├── bubblesort/
│       └── dhrystone/
│
├── official/                    # Official RISC-V compliance tests
│   ├── rv32ui/                  # Base integer (42 tests)
│   ├── rv32um/                  # Multiply/divide (8 tests)
│   ├── rv32ua/                  # Atomics (10 tests)
│   ├── rv32uf/                  # Single-precision FP (11 tests)
│   ├── rv32ud/                  # Double-precision FP (9 tests)
│   ├── rv32uc/                  # Compressed (1 test)
│   └── README.md                # Official test documentation
│
├── regression/                  # Regression tests (bug fixes)
│   ├── bug_001_fence_i/
│   ├── bug_023_c_config/
│   ├── bug_054_fma_grs/
│   └── README.md                # Bug test documentation
│
└── generated/                   # Auto-generated files (in .gitignore)
    ├── hex/                     # Generated .hex files
    ├── elf/                     # Generated .elf files
    ├── bin/                     # Generated .bin files
    └── results/                 # Test results
```

### Migration Strategy

**Phase 1: Non-Breaking Addition** (1 hour)
1. Create new directory structure
2. **Copy** (not move) tests to new locations
3. Keep old `tests/asm/` intact
4. Add symlinks from old → new for compatibility

**Phase 2: Script Updates** (2 hours)
5. Update test scripts to search both old and new locations
6. Add category-based test running
7. Test thoroughly

**Phase 3: Deprecation** (when confident)
8. Add deprecation notice to `tests/asm/README.md`
9. Eventually remove old structure (after validation period)

---

## Part 2: Test Categorization

### Test Categories by Extension

#### Base Integer (RV32I/RV64I) - 15+ tests

**Arithmetic** (well-covered):
- simple_add.s ✅
- test_rv64i_arithmetic.s ✅
- Need: test_sub.s, test_overflow.s

**Logic** (well-covered):
- logic_ops.s ✅
- shift_ops.s ✅
- test_shifts_debug.s ✅

**Branch** (well-covered):
- branch_test.s ✅
- test_branch_forward.s ✅
- Need: test_branch_backward.s, test_all_branch_types.s

**Load/Store** (well-covered):
- load_store.s ✅
- test_lb_detailed.s ✅
- test_misaligned*.s (3 files) ✅
- test_load_*.s (5 files) ✅

**Jump** (well-covered):
- jump_test.s ✅

**Gaps**:
- No explicit test for AUIPC
- No comprehensive immediate generation test
- No LUI corner cases (partially covered)

---

#### M Extension - 10 tests (excellent coverage)

**Multiply** (good):
- test_m_basic.s ✅
- test_m_simple.s ✅
- Need: test_mul_edges.s (INT_MIN, INT_MAX)

**Divide** (excellent):
- test_div_simple.s ✅
- test_div_comprehensive.s ✅
- test_div_by_zero.s ✅

**Hazards** (good):
- test_m_hazard.s ✅

**Gaps**:
- No explicit MULH/MULHU/MULHSU edge case test
- No RV64M W-variant tests (MULW, DIVW, etc.)

---

#### A Extension - 2 custom tests (rely on official tests)

**LR/SC** (basic coverage):
- test_atomic_simple.s ✅
- test_lr_sc_minimal.s ✅
- test_lr_only.s ✅
- test_sc_only.s ✅
- test_lr_sc_direct.s ✅

**AMO Operations**:
- **MAJOR GAP**: No custom AMO tests (AMOSWAP, AMOADD, etc.)
- Rely entirely on official tests

**Recommendation**: Add comprehensive AMO test suite

---

#### F Extension - 13 tests (excellent coverage)

**Arithmetic** (good):
- test_fp_basic.s ✅
- test_fp_add_simple.s ✅

**Conversion** (excellent):
- test_fp_convert.s ✅
- test_fcvt_*.s (multiple) ✅

**Compare** (good):
- test_fp_compare.s ✅

**FMA** (good):
- test_fp_fma.s ✅

**Misc** (good):
- test_fp_csr.s ✅
- test_fmv_xw.s ✅
- test_fp_misc.s ✅

**Gaps**:
- No explicit FDIV edge cases
- No FSQRT edge cases
- No denormal number tests
- No NaN propagation tests

---

#### D Extension - Same 13 tests (shared with F)

**Coverage**: Same as F extension (tests use both .S and .D instructions)

**Gaps**: Same as F extension

---

#### C Extension - 7 tests (good coverage)

**Basic** (good):
- test_rvc_basic.s ✅
- test_rvc_simple.s ✅
- test_rvc_minimal.s ✅

**Control Flow** (good):
- test_rvc_control.s ✅

**Mixed** (good):
- test_rvc_mixed.s ✅

**Stack** (good):
- test_rvc_stack.s ✅

**Gaps**:
- No test for all 40 compressed instructions individually
- No C.FLDSP/C.FSDSP tests (FP compressed)

---

#### Privilege/Supervisor - 12 tests (excellent coverage)

**CSR** (good):
- test_csr_basic.s ✅
- test_csr_debug.s ✅
- test_simple_csr.s ✅
- test_smode_csr.s ✅

**Mode Transitions** (excellent):
- test_priv_*.s (4 files) ✅
- test_enter_smode.s ✅
- test_ecall_*.s (2 files) ✅
- test_mret_simple.s ✅
- test_sret.s ✅

**Delegation** (good):
- test_medeleg.s ✅

**Supervisor** (good):
- test_supervisor_*.s (2 files) ✅

**Gaps**: None significant

---

#### MMU/Virtual Memory - 4 tests (basic coverage)

**Tests**:
- test_mmu_enabled.s ✅
- test_vm_identity.s ✅
- test_page_fault_*.s (2 files) ✅

**Gaps**:
- No TLB stress test
- No multi-level page table test
- No ASID testing
- No Sv39 (RV64) specific tests

---

### Missing Test Categories

#### 1. **Edge Cases** (HIGH PRIORITY)
Create `tests/custom/edge_cases/`:
- test_edge_arithmetic.s - INT_MIN, INT_MAX operations
- test_edge_multiply.s - MULH* corner cases
- test_edge_fp.s - NaN, Inf, denormals
- test_edge_branch.s - Maximum branch offsets

#### 2. **Performance/Benchmarks** (MEDIUM PRIORITY)
Currently only fibonacci.s, need:
- Bubblesort
- Matrix multiply
- Dhrystone
- Coremark

#### 3. **AMO Operations** (HIGH PRIORITY)
Create `tests/custom/a_extension/amo/`:
- test_amoswap.s
- test_amoadd.s
- test_amoand_or_xor.s
- test_amomin_max.s
- test_amo_ordering.s (memory ordering)

#### 4. **RV64 Specific** (MEDIUM PRIORITY)
Only 2 RV64 tests exist:
- test_rv64i_basic.s ✅
- test_rv64i_arithmetic.s ✅

Need:
- test_rv64m_wvariants.s (MULW, DIVW, etc.)
- test_rv64a_ld.s (LR.D, SC.D, AMO*.D)
- test_rv64i_lwu_ld.s (64-bit loads)

#### 5. **Exception Handling** (LOW PRIORITY)
- test_illegal_instruction.s
- test_load_misaligned_exception.s (currently hangs?)
- test_store_misaligned_exception.s
- test_instruction_page_fault.s

#### 6. **Stress Tests** (LOW PRIORITY)
- test_pipeline_stress.s (maximum hazards)
- test_cache_stress.s (when cache implemented)
- test_interrupt_stress.s (nested interrupts)

---

## Part 3: Infrastructure Improvements

### 3.1 Individual Test Runner

**Current**: Must edit scripts to run single test
**Proposed**: Easy CLI interface

Create `tools/run_test_by_name.sh`:
```bash
#!/bin/bash
# Usage: ./tools/run_test_by_name.sh <test_name> [options]
# Example: ./tools/run_test_by_name.sh fibonacci
# Example: ./tools/run_test_by_name.sh rv32ui-p-add --official
# Example: ./tools/run_test_by_name.sh test_fp_basic --debug --waves

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_NAME="$1"
OFFICIAL=false
DEBUG=false
WAVES=false
TIMEOUT=10

# Parse options
shift
while [[ $# -gt 0 ]]; do
  case $1 in
    --official) OFFICIAL=true ;;
    --debug) DEBUG=true ;;
    --waves) WAVES=true ;;
    --timeout) TIMEOUT="$2"; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# Find test file
if [ "$OFFICIAL" = true ]; then
  # Search official tests
  HEX_FILE=$(find "$PROJECT_ROOT/tests/official" -name "${TEST_NAME}*.hex" | head -1)
else
  # Search custom tests
  ASM_FILE=$(find "$PROJECT_ROOT/tests/custom" -name "${TEST_NAME}.s" 2>/dev/null | head -1)
  if [ -z "$ASM_FILE" ]; then
    # Fallback to old location
    ASM_FILE="$PROJECT_ROOT/tests/asm/${TEST_NAME}.s"
  fi

  if [ ! -f "$ASM_FILE" ]; then
    echo "Error: Test not found: $TEST_NAME"
    exit 1
  fi

  # Build test
  echo "Building $TEST_NAME..."
  "$SCRIPT_DIR/asm_to_hex.sh" "$ASM_FILE"

  HEX_FILE="${ASM_FILE%.s}.hex"
fi

if [ ! -f "$HEX_FILE" ]; then
  echo "Error: Hex file not found: $HEX_FILE"
  exit 1
fi

# Determine configuration
CONFIG="CONFIG_RV32I"
if [[ "$TEST_NAME" == *"rvc"* ]] || [[ "$TEST_NAME" == *"rv32uc"* ]]; then
  CONFIG="CONFIG_RV32IMC"
fi

# Build simulation
echo "Compiling simulation..."
IVERILOG_FLAGS="-g2012 -I$PROJECT_ROOT/rtl/ -D${CONFIG} -DMEM_FILE=\"$HEX_FILE\""

if [ "$OFFICIAL" = true ]; then
  IVERILOG_FLAGS="$IVERILOG_FLAGS -DCOMPLIANCE_TEST"
fi

if [ "$DEBUG" = true ]; then
  IVERILOG_FLAGS="$IVERILOG_FLAGS -DDEBUG_CORE"
fi

SIM_FILE="$PROJECT_ROOT/sim/${TEST_NAME}.vvp"

iverilog $IVERILOG_FLAGS \
  -o "$SIM_FILE" \
  "$PROJECT_ROOT/tb/integration/tb_core_pipelined.v" \
  $(find "$PROJECT_ROOT/rtl" -name "*.v")

if [ $? -ne 0 ]; then
  echo "Error: Compilation failed"
  exit 1
fi

# Run simulation
echo "Running $TEST_NAME..."
if [ "$WAVES" = true ]; then
  timeout ${TIMEOUT}s vvp "$SIM_FILE"
  echo "Waveforms saved to sim/waves/"
else
  timeout ${TIMEOUT}s vvp "$SIM_FILE" | grep -v "VCD"
fi

EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
  echo "Error: Test timed out after ${TIMEOUT}s"
  exit 1
elif [ $EXIT_CODE -ne 0 ]; then
  echo "Error: Test failed with exit code $EXIT_CODE"
  exit 1
fi

echo "✅ Test passed: $TEST_NAME"
```

### 3.2 Category-Based Test Runner

Create `tools/run_tests_by_category.sh`:
```bash
#!/bin/bash
# Usage: ./tools/run_tests_by_category.sh <category>
# Example: ./tools/run_tests_by_category.sh m_extension
# Example: ./tools/run_tests_by_category.sh hazards
# Example: ./tools/run_tests_by_category.sh all

CATEGORY="$1"

if [ -z "$CATEGORY" ]; then
  echo "Usage: $0 <category>"
  echo "Categories: base, m_extension, a_extension, f_extension, d_extension, c_extension, privilege, mmu, hazards, benchmarks, all"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Find all tests in category
if [ "$CATEGORY" = "all" ]; then
  TEST_DIR="$PROJECT_ROOT/tests/custom"
else
  TEST_DIR="$PROJECT_ROOT/tests/custom/$CATEGORY"
fi

if [ ! -d "$TEST_DIR" ]; then
  echo "Error: Category not found: $CATEGORY"
  exit 1
fi

# Run all tests in category
PASSED=0
FAILED=0
FAILED_TESTS=()

for TEST_FILE in $(find "$TEST_DIR" -name "*.s" | sort); do
  TEST_NAME=$(basename "$TEST_FILE" .s)
  echo "========================================="
  echo "Running: $TEST_NAME"
  echo "========================================="

  if "$SCRIPT_DIR/run_test_by_name.sh" "$TEST_NAME" --timeout 15; then
    ((PASSED++))
  else
    ((FAILED++))
    FAILED_TESTS+=("$TEST_NAME")
  fi
  echo ""
done

# Summary
echo "========================================="
echo "Summary: $CATEGORY"
echo "========================================="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
  echo ""
  echo "Failed tests:"
  for TEST in "${FAILED_TESTS[@]}"; do
    echo "  - $TEST"
  done
  exit 1
fi

echo "✅ All tests passed in category: $CATEGORY"
```

### 3.3 Test Result Dashboard

Create `tools/generate_test_report.sh`:
```bash
#!/bin/bash
# Generate comprehensive test report

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REPORT_FILE="$PROJECT_ROOT/TEST_RESULTS.md"

cat > "$REPORT_FILE" << 'EOF'
# Test Results Report

**Generated**: $(date)
**Commit**: $(git rev-parse --short HEAD)

---

## Official Compliance Tests

Running official RISC-V compliance tests...

EOF

# Run official tests
"$SCRIPT_DIR/run_official_tests.sh" all > /tmp/official_results.txt 2>&1
OFFICIAL_EXIT=$?

# Parse results
RV32I_PASSED=$(grep -c "PASSED" /tmp/official_results.txt | grep "rv32ui" || echo "0")
echo "- RV32I: $RV32I_PASSED/42" >> "$REPORT_FILE"

# ... similar for other extensions

cat >> "$REPORT_FILE" << 'EOF'

---

## Custom Tests by Category

EOF

# Run custom tests by category
for CATEGORY in base m_extension a_extension f_extension d_extension c_extension privilege mmu; do
  echo "### $CATEGORY" >> "$REPORT_FILE"
  "$SCRIPT_DIR/run_tests_by_category.sh" "$CATEGORY" > /tmp/custom_${CATEGORY}.txt 2>&1
  PASSED=$(grep "Passed:" /tmp/custom_${CATEGORY}.txt | awk '{print $2}')
  FAILED=$(grep "Failed:" /tmp/custom_${CATEGORY}.txt | awk '{print $2}')
  echo "- Passed: $PASSED" >> "$REPORT_FILE"
  echo "- Failed: $FAILED" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
done

echo "Report generated: $REPORT_FILE"
cat "$REPORT_FILE"
```

### 3.4 Makefile Enhancements

Add to `Makefile`:
```makefile
# Test categories
.PHONY: test-base test-m test-a test-f test-d test-c test-privilege test-mmu

test-base:
	@./tools/run_tests_by_category.sh base

test-m:
	@./tools/run_tests_by_category.sh m_extension

test-a:
	@./tools/run_tests_by_category.sh a_extension

test-f:
	@./tools/run_tests_by_category.sh f_extension

test-d:
	@./tools/run_tests_by_category.sh d_extension

test-c:
	@./tools/run_tests_by_category.sh c_extension

test-privilege:
	@./tools/run_tests_by_category.sh privilege

test-mmu:
	@./tools/run_tests_by_category.sh mmu

# Individual test
.PHONY: test-one
test-one:
	@if [ -z "$(TEST)" ]; then \
		echo "Usage: make test-one TEST=<test_name>"; \
		exit 1; \
	fi
	@./tools/run_test_by_name.sh $(TEST)

# Test report
.PHONY: test-report
test-report:
	@./tools/generate_test_report.sh

# Rebuild all hex files
.PHONY: rebuild-hex
rebuild-hex:
	@echo "Rebuilding all hex files..."
	@for s in tests/custom/*/*.s; do \
		./tools/asm_to_hex.sh "$$s"; \
	done
```

---

## Part 4: Coverage Gaps & New Tests

### Priority 1: High-Value Tests (Implement First)

#### 1.1 AMO Test Suite (HIGH PRIORITY)
**Why**: Currently zero custom AMO tests, rely 100% on official tests

Create `tests/custom/a_extension/amo/`:
- `test_amoswap.s` - Basic AMOSWAP.W/D
- `test_amoadd.s` - AMOADD with overflow
- `test_amoand_or_xor.s` - Logical AMOs
- `test_amomin_max.s` - Min/max with signed/unsigned
- `test_amo_address_alignment.s` - Misalignment testing
- `test_amo_aq_rl.s` - Acquire/Release semantics

#### 1.2 Edge Case Test Suite (HIGH PRIORITY)
**Why**: No systematic edge case testing

Create `tests/custom/edge_cases/`:
- `test_edge_integer.s` - INT_MIN, INT_MAX, overflow
- `test_edge_multiply.s` - MULH corner cases
- `test_edge_divide.s` - Division overflow (INT_MIN / -1)
- `test_edge_fp_special.s` - NaN, Inf, denormals
- `test_edge_branch_offset.s` - Maximum branch distances
- `test_edge_immediates.s` - Maximum immediate values

#### 1.3 RV64 Extended Tests (MEDIUM PRIORITY)
**Why**: Only 2 RV64 tests exist

Create `tests/custom/rv64/`:
- `test_rv64i_wordops.s` - ADDIW, SLLIW, SRLIW, etc.
- `test_rv64i_loads.s` - LWU, LD
- `test_rv64m_wvariants.s` - MULW, DIVW, REMW
- `test_rv64a_double.s` - LR.D, SC.D, AMO*.D
- `test_rv64_upper_bits.s` - Upper 32-bit behavior

### Priority 2: Nice-to-Have Tests

#### 2.1 FP Special Cases (MEDIUM PRIORITY)
- `test_fp_denormals.s` - Denormal number handling
- `test_fp_nan_propagation.s` - NaN in operations
- `test_fp_rounding_modes.s` - All 5 rounding modes
- `test_fp_exceptions.s` - FP exception flags

#### 2.2 Benchmark Suite (LOW PRIORITY)
- `bubblesort.s` - Sorting benchmark
- `matrix_multiply.s` - Matrix ops
- `dhrystone.s` - Classic benchmark
- `coremark.s` - Modern benchmark (if feasible)

#### 2.3 Stress Tests (LOW PRIORITY)
- `test_pipeline_stress.s` - Maximum hazard generation
- `test_tlb_stress.s` - TLB thrashing
- `test_branch_stress.s` - Branch prediction stress

---

## Part 5: Implementation Roadmap

### Phase 1: Quick Wins (1-2 hours)
1. ✅ Create reorganization plan (this document)
2. Create directory structure for new organization
3. Create symlinks for backward compatibility
4. Update scripts to support both old/new locations
5. Add `tools/run_test_by_name.sh`

### Phase 2: High-Priority Tests (4-6 hours)
6. Create AMO test suite (6 tests)
7. Create edge case test suite (6 tests)
8. Verify all new tests pass
9. Document test coverage improvements

### Phase 3: Infrastructure (2-3 hours)
10. Create `tools/run_tests_by_category.sh`
11. Create `tools/generate_test_report.sh`
12. Add Makefile targets
13. Update documentation

### Phase 4: Migration (when ready)
14. Migrate existing tests to new structure
15. Update all documentation
16. Deprecate old structure
17. Clean up redundant scripts

### Phase 5: Extended Coverage (optional, 8-12 hours)
18. RV64 extended tests
19. FP special cases
20. Benchmark suite
21. Stress tests

---

## Part 6: Immediate Action Items

### Today (30 minutes)
- [ ] Review this plan with user
- [ ] Get approval for reorganization approach
- [ ] Identify which tests to create first

### This Week (4-6 hours)
- [ ] Implement Phase 1 (directory structure + scripts)
- [ ] Create AMO test suite (6 tests)
- [ ] Create edge case tests (6 tests)
- [ ] Verify 100% compliance maintained

### This Month (optional)
- [ ] Complete infrastructure improvements
- [ ] Migrate all tests to new structure
- [ ] Create test dashboard

---

## Success Criteria

### Must Have
- ✅ All existing tests still pass (100% compliance maintained)
- ✅ New tests provide value (find bugs or document behavior)
- ✅ Scripts are backward compatible
- ✅ Documentation is updated

### Should Have
- Category-based test running
- Individual test debugging made easier
- Test coverage >95% of implemented instructions

### Nice to Have
- Automated test dashboard
- Performance regression tracking
- Comprehensive benchmark suite

---

## Appendix: Test Naming Convention

### Proposed Standard

**Pattern**: `test_<extension>_<category>_<specifics>.s`

**Examples**:
- `test_i_arithmetic_overflow.s` - RV32I arithmetic overflow
- `test_m_multiply_signed_edges.s` - M extension multiply edge cases
- `test_a_amo_swap_basic.s` - A extension AMOSWAP basic test
- `test_f_convert_int32_to_float.s` - F extension conversion
- `test_d_fma_rounding_rne.s` - D extension FMA with RNE rounding
- `test_c_quadrant0_loads.s` - C extension quadrant 0 loads
- `test_priv_mmode_to_smode.s` - Privilege mode transition
- `test_mmu_tlb_miss.s` - MMU TLB miss handling

**Benefits**:
- Clear extension identification
- Easy sorting and categorization
- Descriptive names aid debugging

---

## Questions for User

1. **Reorganization Scope**: Implement full reorganization or just add new category scripts?
2. **Test Priority**: Which tests to create first (AMO vs edge cases vs RV64)?
3. **Migration Timeline**: Migrate existing tests now or gradually?
4. **Script Redundancy**: Archive old phase-specific scripts now?
5. **Documentation**: Update existing docs or create new test guide?

---

**Status**: Awaiting user feedback
**Next Steps**: Implement approved portions of plan
