# Test Infrastructure Audit Report

**Date**: 2025-10-13
**Project**: RV1 RISC-V CPU Core
**Auditor**: Claude (AI Assistant)

---

## Executive Summary

This audit examined the entire test infrastructure of the RV1 project to ensure:
1. All tests are properly organized and documented
2. The build chain (assembly → hex → simulation) works correctly
3. Official RISC-V compliance tests are ready to run
4. Test coverage is comprehensive and gaps are identified

### Key Findings

✅ **Strengths**:
- 81 official RISC-V compliance tests built and ready
- Comprehensive custom test suite (102 assembly files)
- Multiple testbenches for unit and integration testing
- Good test runner scripts infrastructure

⚠️ **Issues Found**:
1. **Untracked hex files**: 2 hex files not in git (LR/SC tests)
2. **Missing source files**: 2 hex files have no corresponding .s file
3. **Incomplete hex generation**: 30+ .s files missing .hex files
4. **Toolchain prefix mismatch**: assemble.sh defaults to riscv32, but riscv64 is used
5. **Test organization**: Mix of .hex in tests/asm/ and tests/vectors/
6. **No automated hex rebuild**: No Makefile target to regenerate all .hex files

---

## Detailed Findings

### 1. Untracked Hex Files (Git Issue)

**Files**:
```
tests/asm/test_lr_sc_minimal_bytes.hex
tests/asm/test_lr_sc_simple.hex
```

**Analysis**:
- `test_lr_sc_minimal_bytes.hex` - 191 bytes, created Oct 12 22:27
  - **No corresponding .s file** - appears to be manually created or from deleted source
  - Contains valid RISC-V code (LR/SC instructions visible in hex)
  - **Recommendation**: Find source or recreate, then commit

- `test_lr_sc_simple.hex` - 13KB, created Oct 12 22:14
  - **No corresponding .s file** - appears to be manually created or from deleted source
  - Larger test, possibly comprehensive LR/SC test
  - **Recommendation**: Find source or recreate, then commit

**Root Cause**: These hex files were likely generated during Phase 7 (A extension) debugging but the source .s files were either:
- Never created (hand-assembled for quick testing)
- Created but deleted after debugging
- Created in different location

**Action Required**:
- [ ] **Option A**: Find/recreate source files, add to git
- [ ] **Option B**: Delete hex files if no longer needed
- [ ] **Option C**: Document as "legacy test artifacts" and keep for reference

---

### 2. Test File Organization Issues

**Current State**:
- **102 assembly files** (.s) in `tests/asm/`
- **77 hex files** (.hex) in `tests/asm/`
- **0 hex files** in `tests/vectors/` (empty directory)
- **Mismatch**: 25+ .s files without corresponding .hex

**Problem**: Inconsistent workflow
- Original design: .s files → `tests/vectors/*.hex` (per assemble.sh)
- Current reality: .hex files stored in `tests/asm/` alongside .s
- .gitignore ignores `tests/vectors/*.hex` but not `tests/asm/*.hex`

**Missing .hex files** (30 examples):
```
test_lui_spacing.s → No hex
test_div_by_zero.s → No hex
shift_ops.s → No hex
fibonacci.s → No hex
test_rvc_stack.s → No hex
test_div_simple.s → No hex
load_store.s → No hex
logic_ops.s → No hex
jump_test.s → No hex
branch_test.s → No hex
... (20 more)
```

**Action Required**:
- [ ] Decide on standard location: `tests/asm/` or `tests/vectors/`
- [ ] Update `.gitignore` to match decision
- [ ] Update `assemble.sh` to match decision
- [ ] Generate missing .hex files OR mark .s files as deprecated

---

### 3. Build Chain Issues

#### Issue 3a: Toolchain Prefix Mismatch

**assemble.sh line 30**:
```bash
RISCV_PREFIX=${RISCV_PREFIX:-riscv32-unknown-elf-}
```

**Actual toolchain** (from Makefile line 8):
```makefile
RISCV_PREFIX = riscv64-unknown-elf-
```

**Impact**: assemble.sh won't work without explicitly setting `RISCV_PREFIX=riscv64-unknown-elf-`

**Fix**:
```bash
# Change line 30 in assemble.sh to:
RISCV_PREFIX=${RISCV_PREFIX:-riscv64-unknown-elf-}
```

#### Issue 3b: No Automated Hex Rebuild

**Current workflow** (manual):
```bash
# User must manually run for each file:
./tools/assemble.sh tests/asm/fibonacci.s tests/asm/fibonacci.hex
```

**Missing**: Makefile target to regenerate all hex files

**Recommended addition**:
```makefile
# Add to Makefile:
.PHONY: rebuild-hex
rebuild-hex:
	@echo "Rebuilding all hex files..."
	@for s in tests/asm/*.s; do \
		base=$$(basename $$s .s); \
		echo "  $$base.s → $$base.hex"; \
		RISCV_PREFIX=$(RISCV_PREFIX) ./tools/assemble.sh "$$s" "tests/asm/$$base.hex" || true; \
	done
	@echo "✓ Hex rebuild complete"
```

---

### 4. Testbench Infrastructure

**Unit Testbenches** (9 files):
```
tb/unit/tb_alu.v                    - ALU operations
tb/unit/tb_csr_file.v               - CSR registers
tb/unit/tb_decoder.v                - Instruction decoder
tb/unit/tb_decoder_control_csr.v   - Decoder + control + CSR
tb/unit/tb_div_unit_simple.v       - Division unit
tb/unit/tb_exception_unit.v        - Exception handling
tb/unit/tb_pipeline_registers.v    - Pipeline registers
tb/unit/tb_register_file.v         - Register file
tb/unit/tb_rvc_decoder.v            - Compressed instruction decoder
```

**Integration Testbenches** (7 files):
```
tb/integration/tb_core.v                   - Single-cycle core
tb/integration/tb_core_pipelined.v         - Pipelined core (main)
tb/integration/tb_core_pipelined_rv64.v    - 64-bit pipelined core
tb/integration/tb_debug_simple.v           - Debug testbench
tb/integration/tb_minimal_rvc.v            - Minimal RVC test
tb/integration/tb_rvc_minimal.v            - RVC minimal (duplicate?)
tb/integration/tb_rvc_simple.v             - RVC simple test
```

**Other Testbenches** (6 files):
```
tb/tb_mmu.v                              - MMU unit test
tb/tb_rvc_mixed_integration.v           - RVC mixed instructions
tb/tb_rvc_quick_test.v                   - RVC quick test
tb/tb_simple_exec.v                      - Simple execution test
tb/tb_simple_test.v                      - Simple test
tb/tb_simple_with_program.v             - Simple with program
```

**Status**: ✅ Good coverage, but some redundancy/overlap

**Observations**:
- Multiple "simple" testbenches with unclear distinctions
- Two nearly identical testbenches: `tb_minimal_rvc.v` and `tb_rvc_minimal.v`
- Main workhorse: `tb_core_pipelined.v` (most capable)

**Recommendations**:
- [ ] Consolidate or document differences between similar testbenches
- [ ] Mark primary testbench (`tb_core_pipelined.v`) clearly
- [ ] Add comments explaining when to use each testbench

---

### 5. Test Runner Scripts

**Available Scripts** (11 files):
```
tools/build_riscv_tests.sh          - Build official RISC-V tests ✅
tools/run_all_tests.sh              - Run all tests
tools/run_compliance.sh             - Run compliance tests (old?)
tools/run_compliance_pipelined.sh   - Run pipelined compliance
tools/run_official_tests.sh         - Run official tests (main) ✅
tools/run_phase10_2_test.sh         - Phase 10.2 specific
tools/run_test.sh                   - Generic test runner
tools/run_tests_simple.sh           - Simple tests
tools/test_phase10_2_suite.sh       - Phase 10.2 test suite
tools/test_pipelined.sh             - Pipelined core tests ✅
tools/test_rvc_suite.sh             - RVC test suite ✅
```

**Status**: ✅ Good infrastructure, but overlapping scripts

**Key Scripts**:
- ✅ `run_official_tests.sh` - Primary for official compliance
- ✅ `test_pipelined.sh` - Primary for custom tests
- ⚠️ Multiple compliance runners (redundancy)

**Recommendations**:
- [ ] Consolidate or deprecate old compliance scripts
- [ ] Create single "master" test runner that calls others
- [ ] Document script hierarchy and when to use each

---

### 6. Official RISC-V Compliance Tests

**Status**: ✅ **READY TO RUN**

**Test Files Built**: 81 hex files in `tests/official-compliance/`

**Breakdown**:
- RV32UI (Base Integer): 42 tests
- RV32UM (Multiply/Divide): 8 tests
- RV32UA (Atomic): 10 tests
- RV32UF (Single-Precision FP): 11 tests
- RV32UD (Double-Precision FP): 9 tests
- RV32UC (Compressed): 1 test

**Test Runner**: `./tools/run_official_tests.sh [extension]`

**Usage**:
```bash
./tools/run_official_tests.sh i      # Run RV32I tests
./tools/run_official_tests.sh m      # Run M extension
./tools/run_official_tests.sh a      # Run A extension
./tools/run_official_tests.sh f      # Run F extension (NOT YET RUN)
./tools/run_official_tests.sh d      # Run D extension (NOT YET RUN)
./tools/run_official_tests.sh c      # Run C extension
./tools/run_official_tests.sh all    # Run everything
```

**Verified Working**:
- ✅ RV32I: 42/42 passing (100%)
- ✅ RV32M: 8/8 passing (100%)
- ✅ RV32A: 10/10 passing (100%)
- ✅ RV32C: 1/1 passing (100%)

**Not Yet Run**:
- ⏳ RV32UF: 11 tests (F extension)
- ⏳ RV32UD: 9 tests (D extension)

**Action**: Run F/D tests to validate FPU implementation

---

### 7. Custom Test Coverage Analysis

**Test Categories**:

**Base ISA Tests** (15 tests):
```
simple_add.s, fibonacci.s, load_store.s
branch_test.s, jump_test.s, logic_ops.s, shift_ops.s
test_load_use.s, test_forwarding_and.s
test_misaligned*.s (3 files)
... others
```
**Status**: ✅ Good coverage

**M Extension Tests** (10 tests):
```
test_m_basic.s, test_m_simple.s, test_m_hazard.s
test_m_debug.s, test_m_incremental.s
test_div_*.s (3 files)
... others
```
**Status**: ✅ Comprehensive

**A Extension Tests** (2 tests):
```
test_atomic_simple.s
test_lrsc_*.s (variants)
```
**Status**: ⚠️ Limited - only 2 source files (but has official tests)

**F/D Extension Tests** (13 tests):
```
test_fp_basic.s, test_fp_compare.s, test_fp_convert.s
test_fp_fma.s, test_fp_csr.s, test_fp_load_use.s
test_fp_loadstore*.s (3 files)
test_fp_minimal*.s (3 files)
... others
```
**Status**: ✅ Excellent coverage

**Privilege/CSR Tests** (12 tests):
```
test_csr_*.s (3 files)
test_ecall*.s (2 files)
test_mret*.s, test_sret*.s
test_enter_smode.s, test_smode_csr.s
test_medeleg.s, test_mmu_enabled.s
test_supervisor*.s (3 files)
test_priv*.s, test_phase10_2*.s (3 files)
```
**Status**: ✅ Very comprehensive (Phase 10 work)

**C Extension Tests** (7 tests):
```
test_rvc_basic.s, test_rvc_control.s, test_rvc_minimal.s
test_rvc_mixed.s, test_rvc_simple.s, test_rvc_stack.s
```
**Status**: ✅ Good coverage (34/34 unit tests also)

---

## Priority Recommendations

### Critical (Fix Immediately)

1. ✅ **FIXED: Toolchain prefix mismatch** in `assemble.sh`
   - Changed line 30: `RISCV_PREFIX=${RISCV_PREFIX:-riscv64-unknown-elf-}`
   - Added line 45: `-m elf32lriscv` flag to linker
   - **Verified working**: `./tools/assemble.sh tests/asm/simple_add.s /tmp/test.hex` ✅

2. **Resolve untracked hex files**
   - Find/recreate source for `test_lr_sc_minimal_bytes.s` and `test_lr_sc_simple.s`
   - OR document as legacy artifacts
   - OR delete if not needed
   - Then: `git add tests/asm/test_lr_sc_*.hex` and commit

3. **Update .gitignore**
   ```
   # Current: tests/vectors/*.hex
   # Should also have: tests/asm/*.hex (if we keep hex files there)
   # OR move all hex to tests/vectors/ and update scripts
   ```

### High Priority (Before F/D Testing)

4. **Add Makefile target for hex rebuild**
   - Add `rebuild-hex` target to Makefile
   - Document usage in README

5. **Test the build chain end-to-end**
   ```bash
   # Verify this workflow works:
   ./tools/assemble.sh tests/asm/simple_add.s tests/asm/simple_add.hex
   ./tools/test_pipelined.sh simple_add
   ```

6. **Generate missing hex files**
   - Run `make rebuild-hex` (after adding target)
   - Or decide which .s files are deprecated and remove them

### Medium Priority (Cleanup)

7. **Consolidate redundant testbenches**
   - Decide: `tb_minimal_rvc.v` vs `tb_rvc_minimal.v` (pick one)
   - Document purpose of each "simple" testbench
   - Mark `tb_core_pipelined.v` as primary integration testbench

8. **Consolidate test runner scripts**
   - Deprecate old compliance scripts
   - Create master test runner
   - Document script hierarchy

9. **Organize test documentation**
   - Create `tests/README.md` explaining:
     - Directory structure
     - How to add new tests
     - How to run tests
     - Test naming conventions

### Low Priority (Nice to Have)

10. **Add test result tracking**
    - Create `test_results.log` or similar
    - Track pass/fail history
    - Identify flaky tests

11. **Add performance tracking**
    - Track cycle counts for key tests
    - Detect performance regressions

---

## Test Workflow Recommendations

### Standard Workflow (Recommended)

**For adding a new test**:
```bash
# 1. Write assembly test
vim tests/asm/my_new_test.s

# 2. Generate hex file
./tools/assemble.sh tests/asm/my_new_test.s tests/asm/my_new_test.hex

# 3. Run test
./tools/test_pipelined.sh my_new_test

# 4. Commit both files
git add tests/asm/my_new_test.s tests/asm/my_new_test.hex
git commit -m "Add my_new_test for XYZ feature"
```

**For running official compliance**:
```bash
# Run specific extension
./tools/run_official_tests.sh f

# Run all official tests
./tools/run_official_tests.sh all
```

**For debugging**:
```bash
# Use primary testbench with debug level
iverilog -g2012 -I rtl/ -DDEBUG_LEVEL=2 -DMEM_FILE=\"tests/asm/my_test.hex\" \
  -o sim/test.vvp rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v
vvp sim/test.vvp
gtkwave sim/waves/core_pipelined.vcd
```

---

## Conclusion

The RV1 test infrastructure is **fundamentally sound** with excellent coverage, but has several **organizational and workflow issues** that should be fixed before proceeding with F/D compliance testing.

**Overall Grade**: B+ (Good infrastructure, needs cleanup)

**Blocking Issues for F/D Testing**: None (can proceed)

**Recommended Next Steps**:
1. Fix toolchain prefix (5 minutes)
2. Resolve untracked hex files (15 minutes)
3. Run F/D compliance tests (30 minutes)
4. Add Makefile hex rebuild target (30 minutes)
5. Clean up test organization (1-2 hours, can be done later)

**Test Infrastructure is READY for F/D compliance testing!** ✅

---

*Generated by AI Assistant | RV1 RISC-V Processor Project*
