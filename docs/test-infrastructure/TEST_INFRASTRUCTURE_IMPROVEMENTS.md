# Test Infrastructure Improvements

**Date**: 2025-10-13
**Status**: Recommendations for Future Work
**Priority**: Non-blocking organizational improvements

---

## Overview

The RV1 test infrastructure is **functionally complete and working**. These recommendations address organizational debt and workflow improvements that would make testing easier in the future.

**Current Status**: ✅ All critical issues fixed, infrastructure ready for use

---

## High Priority Improvements

### 1. Add Makefile Target for Hex Rebuild

**Problem**: No automated way to regenerate all hex files from assembly sources

**Current Workflow** (manual):
```bash
# Must run for each file individually:
./tools/assemble.sh tests/asm/fibonacci.s tests/asm/fibonacci.hex
./tools/assemble.sh tests/asm/test_m_basic.s tests/asm/test_m_basic.hex
# ... repeat for 100+ files
```

**Proposed Solution**:

Add to `Makefile`:

```makefile
#==============================================================================
# Assembly Test Targets
#==============================================================================

.PHONY: rebuild-hex
rebuild-hex:
	@echo "Rebuilding all hex files from assembly sources..."
	@mkdir -p tests/asm
	@count=0; \
	for s in tests/asm/*.s; do \
		base=$$(basename $$s .s); \
		hex="tests/asm/$$base.hex"; \
		echo "  $$base.s → $$base.hex"; \
		./tools/assemble.sh "$$s" "$$hex" 2>/dev/null || \
			echo "    ⚠️  Warning: Failed to assemble $$base.s"; \
		if [ -f "$$hex" ]; then count=$$((count + 1)); fi; \
	done; \
	echo "✓ Hex rebuild complete: $$count files generated"

.PHONY: check-hex
check-hex:
	@echo "Checking for missing hex files..."
	@missing=0; \
	for s in tests/asm/*.s; do \
		base=$$(basename $$s .s); \
		hex="tests/asm/$$base.hex"; \
		if [ ! -f "$$hex" ]; then \
			echo "  ⚠️  Missing: $$base.hex"; \
			missing=$$((missing + 1)); \
		fi; \
	done; \
	if [ $$missing -eq 0 ]; then \
		echo "✓ All assembly files have corresponding hex files"; \
	else \
		echo "⚠️  $$missing assembly files are missing hex files"; \
	fi

.PHONY: clean-hex
clean-hex:
	@echo "Cleaning generated hex files..."
	@rm -f tests/asm/*.hex
	@rm -f tests/vectors/*.hex tests/vectors/*.o tests/vectors/*.elf tests/vectors/*.dump
	@echo "✓ Hex files cleaned"
```

**Usage**:
```bash
make rebuild-hex    # Regenerate all hex files
make check-hex      # Check for missing hex files
make clean-hex      # Clean all generated hex files
```

**Effort**: 30 minutes
**Benefit**: Saves hours when updating assembly tests

---

### 2. Standardize Hex File Location

**Problem**: Inconsistent hex file locations
- Design intent: `tests/vectors/*.hex` (per `assemble.sh` default)
- Current reality: `tests/asm/*.hex` (where tests actually are)
- `.gitignore`: Ignores `tests/vectors/*.hex` but not `tests/asm/*.hex`

**Proposed Solution**: Choose one standard location

**Option A: Keep hex in `tests/asm/`** (Recommended)

Pros:
- Matches current practice
- Source and hex co-located (easier to manage)
- Most hex files already there

Changes needed:
```bash
# 1. Update .gitignore
echo "tests/asm/*.hex" >> .gitignore

# 2. Update assemble.sh default output location (line 21):
# From:
HEX_FILE="tests/vectors/${BASE_NAME}.hex"
# To:
HEX_FILE="tests/asm/${BASE_NAME}.hex"
```

**Option B: Move hex to `tests/vectors/`** (Cleaner separation)

Pros:
- Separates source from generated files
- Matches original design intent
- `.gitignore` already configured

Changes needed:
```bash
# 1. Move all hex files
mv tests/asm/*.hex tests/vectors/

# 2. Update test runner scripts to look in tests/vectors/
# (Multiple scripts: test_pipelined.sh, run_test.sh, etc.)
```

**Recommendation**: **Option A** - Keep hex in `tests/asm/` (simpler, matches practice)

**Effort**: 15 minutes
**Benefit**: Consistent organization, cleaner git status

---

### 3. Update .gitignore for Consistency

**Current `.gitignore`**:
```
tests/vectors/*.o
tests/vectors/*.elf
tests/vectors/*.dump
# Missing: tests/vectors/*.hex
# Missing: tests/asm/*.hex (if we keep them there)
```

**Proposed Changes**:

If keeping hex in `tests/asm/`:
```bash
# Add to .gitignore:
tests/asm/*.hex
```

If moving hex to `tests/vectors/`:
```bash
# Add to .gitignore:
tests/vectors/*.hex
```

**Also add**:
```bash
# Simulation artifacts
sim/*.vvp
sim/waves/*.vcd
sim/waves/*.fst

# Test artifacts
tests/official-compliance/*.log
tests/official-compliance/*.out
```

**Effort**: 5 minutes
**Benefit**: Cleaner `git status`, no accidental commits of generated files

---

### 4. Generate Missing Hex Files

**Problem**: 30+ `.s` files without corresponding `.hex` files

**Analysis**: Many are likely deprecated/experimental tests

**Proposed Solution**:

```bash
# 1. Attempt to generate all missing hex files
make rebuild-hex

# 2. Review failures and decide for each:
#    - Fix assembly errors → regenerate
#    - Deprecated test → delete .s file
#    - Intentionally no hex → document in tests/README.md

# 3. Document which tests are active vs deprecated
```

**Missing hex files** (30 examples from audit):
```
test_lui_spacing.s
test_div_by_zero.s
shift_ops.s
fibonacci.s
test_rvc_stack.s
... (25 more)
```

**Effort**: 1-2 hours (reviewing and deciding)
**Benefit**: Clarity on which tests are active, easier maintenance

---

## Medium Priority Improvements

### 5. Consolidate Redundant Testbenches

**Problem**: Multiple similar testbenches with unclear distinctions

**Redundant pairs**:
- `tb/integration/tb_minimal_rvc.v` vs `tb/integration/tb_rvc_minimal.v`
- `tb/tb_simple_test.v` vs `tb/tb_simple_exec.v` vs `tb/tb_simple_with_program.v`

**Proposed Solution**:

```bash
# 1. Compare redundant files to find differences
diff tb/integration/tb_minimal_rvc.v tb/integration/tb_rvc_minimal.v

# 2. If identical or nearly identical:
#    - Keep one (preferably newer/better named)
#    - Delete the other
#    - Update any scripts that reference deleted file

# 3. If different:
#    - Document purpose of each in header comment
#    - Rename for clarity (e.g., tb_rvc_unit.v vs tb_rvc_integration.v)
```

**Effort**: 1 hour
**Benefit**: Less confusion, easier to know which testbench to use

---

### 6. Document Testbench Hierarchy

**Problem**: Unclear which testbench to use when

**Proposed Solution**:

Add to `tb/README.md`:

```markdown
# Testbench Guide

## Primary Testbenches (Use These)

### Unit Testing
- `tb/unit/tb_alu.v` - Test ALU operations
- `tb/unit/tb_register_file.v` - Test register file
- `tb/unit/tb_decoder.v` - Test instruction decoder
- `tb/unit/tb_rvc_decoder.v` - Test compressed instruction decoder
- `tb/unit/tb_csr_file.v` - Test CSR registers

### Integration Testing
- **`tb/integration/tb_core_pipelined.v`** ← **PRIMARY TESTBENCH**
  - Use this for testing complete programs
  - Supports debug levels (0-3)
  - Supports compliance testing mode
  - Performance metrics tracking
  - **Recommended for all custom test programs**

- `tb/integration/tb_core_pipelined_rv64.v` - RV64 variant

### Specialized Testing
- `tb/tb_mmu.v` - Dedicated MMU/TLB testing
- `tb/integration/tb_rvc_*.v` - RVC-specific integration tests

## When to Use Which

**Testing a new instruction**: Use `tb/integration/tb_core_pipelined.v`
**Testing a specific module**: Use corresponding `tb/unit/tb_*.v`
**Debugging waveforms**: Use `tb/integration/tb_core_pipelined.v` with `-DDEBUG_LEVEL=2`
**Running official tests**: Use `tools/run_official_tests.sh` (calls tb_core_pipelined.v)
```

**Effort**: 30 minutes
**Benefit**: New contributors know which testbench to use

---

### 7. Consolidate Test Runner Scripts

**Problem**: 11 test runner scripts with overlapping functionality

**Current scripts**:
```
tools/run_official_tests.sh         ← Primary for official tests
tools/test_pipelined.sh             ← Primary for custom tests
tools/run_compliance_pipelined.sh   ← Overlaps with run_official_tests.sh
tools/run_compliance.sh             ← Old version?
tools/run_test.sh                   ← Generic, unclear usage
tools/run_all_tests.sh              ← Runs what?
... (5 more phase-specific scripts)
```

**Proposed Solution**:

Create a master test runner:

```bash
#!/bin/bash
# tools/test.sh - Master test runner

usage() {
  cat << EOF
Usage: $0 [category] [test_name]

Categories:
  unit          - Run all unit tests
  custom        - Run all custom integration tests
  official      - Run official RISC-V compliance tests
  [extension]   - Run specific extension (i, m, a, f, d, c)

Examples:
  $0 unit                    # Run all unit tests
  $0 custom fibonacci        # Run custom fibonacci test
  $0 official i              # Run official RV32I tests
  $0 f                       # Run F extension tests
  $0 all                     # Run everything

See also:
  tools/test_pipelined.sh <test>     # Run single custom test
  tools/run_official_tests.sh <ext>  # Run official tests
EOF
}

# Dispatch to appropriate script
case "$1" in
  unit)       make test-unit ;;
  custom)     ./tools/test_pipelined.sh "$2" ;;
  official)   ./tools/run_official_tests.sh "$2" ;;
  i|m|a|f|d|c|all) ./tools/run_official_tests.sh "$1" ;;
  *)          usage ;;
esac
```

**Deprecate/archive**:
- Move old scripts to `tools/archive/`
- Update documentation to reference master script

**Effort**: 1 hour
**Benefit**: Single entry point for all testing, clearer hierarchy

---

### 8. Create tests/README.md

**Problem**: No documentation explaining test organization

**Proposed Content**:

```markdown
# RV1 Test Directory

## Directory Structure

```
tests/
├── asm/                    # Assembly test sources (.s) and hex files (.hex)
├── vectors/                # Build artifacts (.o, .elf, .dump)
├── official-compliance/    # Official RISC-V test hex files (81 tests)
└── riscv-compliance/       # (deprecated, use official-compliance/)
```

## Adding a New Test

1. Write assembly test in `tests/asm/`
2. Generate hex file: `./tools/assemble.sh tests/asm/my_test.s tests/asm/my_test.hex`
3. Run test: `./tools/test_pipelined.sh my_test`
4. Commit both files: `git add tests/asm/my_test.{s,hex}`

## Test Naming Conventions

- `test_<feature>.s` - Feature-specific test
- `test_<extension>_<operation>.s` - Extension-specific test
- `test_<bug>.s` - Regression test for bug fix

## Running Tests

### Custom Tests
```bash
./tools/test_pipelined.sh <test_name>    # Single test
make test-unit                            # All unit tests
```

### Official Compliance Tests
```bash
./tools/run_official_tests.sh i          # RV32I (42 tests)
./tools/run_official_tests.sh m          # M extension (8 tests)
./tools/run_official_tests.sh a          # A extension (10 tests)
./tools/run_official_tests.sh f          # F extension (11 tests)
./tools/run_official_tests.sh d          # D extension (9 tests)
./tools/run_official_tests.sh c          # C extension (1 test)
./tools/run_official_tests.sh all        # All tests
```

## Test Coverage

- **RV32I**: 15 custom + 42 official = 57 tests
- **M Extension**: 10 custom + 8 official = 18 tests
- **A Extension**: 2 custom + 10 official = 12 tests
- **F Extension**: 13 custom + 11 official = 24 tests
- **D Extension**: (included in F) + 9 official
- **C Extension**: 7 custom + 1 official = 8 tests
- **Privilege/CSR**: 12 custom tests

Total: 100+ custom tests, 81 official tests
```

**Effort**: 30 minutes
**Benefit**: Self-documenting test infrastructure

---

## Low Priority Improvements

### 9. Add Test Result Tracking

**Concept**: Track test results over time to detect regressions

```bash
# tools/track_tests.sh
#!/bin/bash
# Run tests and log results

DATE=$(date +%Y-%m-%d_%H-%M-%S)
LOG="test_results_$DATE.log"

echo "Test Run: $DATE" > "$LOG"
echo "==================" >> "$LOG"

# Run all tests and capture results
./tools/run_official_tests.sh all 2>&1 | tee -a "$LOG"

# Extract summary
echo "" >> "$LOG"
echo "Summary:" >> "$LOG"
grep -E "PASS|FAIL" "$LOG" | sort | uniq -c >> "$LOG"
```

**Benefit**: Historical test data, regression detection

---

### 10. Add Performance Tracking

**Concept**: Track cycle counts for key tests

```bash
# Track performance regressions
echo "Performance Tracking" > perf.log
for test in fibonacci test_m_basic test_atomic_simple; do
  cycles=$(./tools/test_pipelined.sh $test 2>&1 | grep "cycles" | awk '{print $NF}')
  echo "$test: $cycles cycles" >> perf.log
done
```

**Benefit**: Detect performance regressions early

---

## Implementation Priority

**Before Next Session**:
1. ✅ (Done) Fix `assemble.sh` toolchain prefix
2. ✅ (Done) Add untracked hex files to git
3. Add `rebuild-hex` target to Makefile (30 min)

**Before Adding New Features**:
4. Standardize hex file location (15 min)
5. Update `.gitignore` (5 min)
6. Create `tests/README.md` (30 min)

**Future Cleanup** (when time permits):
7. Consolidate redundant testbenches (1 hour)
8. Document testbench hierarchy (30 min)
9. Consolidate test runner scripts (1 hour)
10. Generate missing hex files (1-2 hours)

**Nice to Have**:
11. Test result tracking
12. Performance tracking

---

## Maintenance Tasks

### Regular Maintenance

**Monthly**:
- Run `make check-hex` to verify all .s files have .hex
- Run `make rebuild-hex` if toolchain changes
- Run official compliance: `./tools/run_official_tests.sh all`

**After Major Changes**:
- Rebuild all hex files: `make rebuild-hex`
- Run full test suite
- Update test documentation if workflow changes

**Before Releases**:
- Full compliance run: `./tools/run_official_tests.sh all`
- Check for deprecated tests and remove
- Verify all test documentation is current

---

## Notes

- These improvements are **non-blocking** - infrastructure works as-is
- Prioritize based on pain points encountered
- Most improvements are quick wins (< 1 hour each)
- Focus on items that will save time in the long run

---

**Last Updated**: 2025-10-13
**Status**: Recommendations ready for implementation

*See also: TEST_INFRASTRUCTURE_AUDIT.md for detailed analysis*
