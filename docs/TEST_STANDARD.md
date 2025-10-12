# Test Standard for RV1 Project

## Overview
This document describes the standard methodology for writing and running tests in the RV1 RISC-V CPU project.

## Test Success/Failure Indication

### Standard Method
All tests should use the EBREAK instruction to signal test completion, combined with a marker value in register x28 (t3) to indicate success or failure.

### Success Markers (x28 register values)
Tests should set x28 to one of these values to indicate success:
- `0xDEADBEEF` - General success marker (most common)
- `0xFEEDFACE` - Alternate success marker
- `0xC0FFEE00` - Success marker for specific tests
- `0x0000BEEF` - Compact success marker
- `0x00000001` - Minimal success marker

### Failure Markers (x28 register values)
Tests should set x28 to one of these values to indicate failure:
- `0xDEADDEAD` - General failure marker
- `0x0BADC0DE` - Alternate failure marker

### Test Template

```assembly
.section .text
.globl _start

_start:
    # Test code here
    # Perform operations and checks

    # If test passes:
    li x28, 0xDEADBEEF
    nop                    # Allow register write to complete
    nop
    nop
    ebreak                 # Signal test completion

    # If test fails (optional):
fail:
    li x28, 0xDEADDEAD
    ebreak
```

### Why NOPs Before EBREAK?
The `li` pseudo-instruction expands to LUI + ADDI. In a pipelined processor, when EBREAK is detected in the IF stage, preceding instructions may not have completed their write-back stage. Adding 3 NOPs ensures the ADDI instruction completes writing to x28 before the testbench reads the register values.

## Testbench Behavior

### EBREAK Detection
When the testbench detects EBREAK (0x00100073):
1. Waits 10 cycles for pipeline to flush and complete
2. Reads the value of x28 register
3. Compares against known success/failure markers
4. Reports test result:
   - **TEST PASSED** - if x28 matches a success marker
   - **TEST FAILED** - if x28 matches a failure marker
   - **TEST PASSED (EBREAK with no marker)** - if x28 doesn't match any marker

### Example Output

**Successful Test:**
```
EBREAK encountered at cycle 116
Final PC: 0x00000084

========================================
TEST PASSED
========================================
  Success marker (x28): 0xdeadbeef
  Cycles: 116
```

**Failed Test:**
```
EBREAK encountered at cycle 45
Final PC: 0x00000060

========================================
TEST FAILED
========================================
  Failure marker (x28): 0xdeaddead
  Cycles: 45
```

## Test Types

### 1. Simple Tests
Tests that verify basic functionality without complex validation.
- Use EBREAK with success marker
- Example: `test_simple.s`

### 2. Self-Checking Tests
Tests that validate results and branch to success/failure paths.
- Check computed values against expected results
- Branch to `fail:` label if mismatch detected
- Set appropriate marker before EBREAK
- Example: `test_fp_compare.s`

### 3. Compliance Tests
RISC-V official compliance tests use a different convention:
- Use ECALL instead of EBREAK
- Store result in x3 (gp) register: 1 = pass, other = fail
- Require `-DCOMPLIANCE_TEST` flag during compilation

## Writing New Tests

### Checklist
- [ ] Test has clear purpose and scope
- [ ] Test uses EBREAK for completion signaling
- [ ] Test sets x28 to appropriate success/failure marker
- [ ] Three NOPs added before EBREAK
- [ ] Test includes expected results as comments
- [ ] Test assembles and links correctly
- [ ] Test passes when run through testbench

### File Organization
```
tests/asm/
  test_name.s         # Assembly source
  test_name.elf       # Linked executable
  test_name.hex       # Hex file for simulation
```

### Assembly and Simulation
```bash
# Assemble test
riscv64-unknown-elf-as -march=rv32imaf -mabi=ilp32f -o test_name.o test_name.s

# Link test
riscv64-unknown-elf-ld -melf32lriscv -T tests/linker.ld -o test_name.elf test_name.o

# Generate hex file
riscv64-unknown-elf-objcopy -O verilog test_name.elf test_name.hex

# Run test
./tools/test_pipelined.sh test_name
```

## Performance Metrics

### Expected Cycle Counts
Different test types have different expected completion times:
- **Simple integer tests**: 10-50 cycles
- **FP arithmetic tests**: 50-150 cycles
- **FP division/sqrt tests**: 100-500 cycles
- **Complex validation tests**: 500-5,000 cycles

Tests exceeding 10,000 cycles may indicate:
- Infinite loop (programming error)
- Excessive stalling (hazard handling issue)
- Very complex test (may need timeout adjustment)

### Timeout
Default timeout: 50,000 cycles
- Adjustable in `tb/integration/tb_core_pipelined.v`
- Tests timing out warrant investigation

## Anti-Patterns to Avoid

### ❌ DON'T: Use infinite loop for test end
```assembly
# Bad - causes timeout
end:
    j end
```

### ✅ DO: Use EBREAK with marker
```assembly
# Good - clear completion
    li x28, 0xDEADBEEF
    nop
    nop
    nop
    ebreak
```

### ❌ DON'T: Set marker immediately before EBREAK
```assembly
# Bad - x28 may not be written yet
    li x28, 0xDEADBEEF
    ebreak
```

### ✅ DO: Add NOPs between marker and EBREAK
```assembly
# Good - ensures write completion
    li x28, 0xDEADBEEF
    nop
    nop
    nop
    ebreak
```

## Migration Guide

### Converting Old Tests
To update tests from infinite loop to EBREAK:

1. Find the end pattern:
   ```assembly
   end:
       j end
   ```

2. Replace with EBREAK pattern:
   ```assembly
       li x28, 0xDEADBEEF
       nop
       nop
       nop
       ebreak
   ```

3. If test has success marker but infinite loop:
   ```assembly
   # Old
   li x28, 0xFEEDFACE
   j end

   # New
   li x28, 0xFEEDFACE
   nop
   nop
   nop
   ebreak
   ```

4. Reassemble and regenerate hex file

5. Test to verify PASS/FAIL detection works

## Benefits of This Standard

1. **Fast execution**: Tests complete in cycles instead of timing out
2. **Clear results**: Explicit PASS/FAIL indication
3. **Cycle counting**: Performance measurement included
4. **Debugging**: Easier to identify which test failed and why
5. **CI/CD ready**: Automated testing with clear exit codes
6. **Consistency**: All tests follow same pattern

## Future Enhancements

Potential improvements to the test framework:
- Exit code propagation (0 = pass, non-zero = fail)
- JSON output format for automated parsing
- Performance regression tracking
- Coverage metrics integration
- Waveform auto-capture on failure
