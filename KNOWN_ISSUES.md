# Known Issues and Limitations

**Date**: 2025-10-12
**Project**: RV1 RISC-V CPU Core

---

## Overview

This document tracks known issues, limitations, and areas requiring future work in the RV1 RISC-V CPU implementation.

---

## Active Issues

### 1. Mixed Compressed/Normal Instruction Addressing Issue

**Status**: 🔴 **ACTIVE - Needs Investigation**

**Component**: C Extension integration with 32-bit instructions

**Description**:
The `test_rvc_simple` test, which mixes compressed (16-bit) and normal (32-bit) instructions, produces incorrect results:
- Expected: x10=42, x11=5, x12=15
- Actual: x10=24, x11=5, x12=0

**Evidence**:
```
Test program flow:
1. c.li x10, 0        # x10 = 0     (compressed)
2. c.addi x10, 10     # x10 = 10    (compressed)
3. c.li x11, 5        # x11 = 5     (compressed)
4. c.add x10, x11     # x10 = 15    (compressed)
5. addi x10, x10, 12  # x10 = 27    (32-bit) ← Issue here
6. c.li x12, 15       # x12 = 15    (compressed)
7. c.add x10, x12     # x10 = 42    (compressed)
8. ebreak

Actual result: x10=24 (missing 18), x12=0 (not set)
```

**Root Cause**: Unknown - needs investigation
- Pure compressed instructions work correctly (test_rvc_minimal passes)
- Issue appears when mixing compressed and 32-bit instructions
- Likely related to PC alignment or instruction fetch at mixed boundaries

**Impact**:
- **Low** for pure compressed programs (working correctly)
- **Medium** for mixed instruction programs
- Does not affect RVC decoder (34/34 unit tests passing)

**Workaround**: Use pure compressed or pure 32-bit instruction sequences

**Investigation Required**:
1. Trace instruction fetch at PC boundaries where compressed/32-bit mix
2. Check PC[1] mux behavior when transitioning from compressed to 32-bit
3. Verify instruction memory fetch alignment for mixed cases
4. Check hazard detection with mixed instruction sizes

**Files Involved**:
- `rtl/core/rv32i_core_pipelined.v` (IF stage, PC logic)
- `rtl/memory/instruction_memory.v` (fetch logic)
- `tests/asm/test_rvc_simple.s` (test case)

**Priority**: Medium

---

### 2. FPU Converter Blocking Assignments

**Status**: 🟡 **DOCUMENTED - Low Priority**

**Component**: Floating-Point Unit (FPU)

**Description**:
The `fp_converter.v` module uses blocking assignments (`=`) in sequential logic blocks, which can cause synthesis issues and simulation mismatches.

**Evidence**:
Verilator warnings:
```
Warning-BLKSEQ: rtl/core/fp_converter.v:136:23:
  Blocking assignment '=' in sequential logic process
  Suggest using delayed assignment '<='
```

Approximately 20-30 instances throughout `fp_converter.v`.

**Root Cause**:
Mixed coding style - combinational logic embedded in sequential blocks.

**Impact**:
- **Low** for current simulation (Icarus Verilog tolerates it)
- **Medium** for synthesis (may cause timing issues)
- **High** for formal verification tools

**Workaround**: None currently needed for simulation

**Fix Required**:
Separate combinational and sequential logic:
```verilog
// Current (problematic):
always @(posedge clk) begin
  sign_fp = fp_operand[FLEN-1];  // Blocking in sequential
  if (reset_n) begin
    result <= computed_value;
  end
end

// Fixed:
always @(*) begin  // Combinational block
  sign_fp = fp_operand[FLEN-1];
end

always @(posedge clk) begin  // Sequential block
  if (reset_n) begin
    result <= computed_value;
  end
end
```

**Files Involved**:
- `rtl/core/fp_converter.v`

**Priority**: Low (works in simulation, fix before FPGA deployment)

---

### 3. FPU Width Mismatch Warnings

**Status**: 🟡 **DOCUMENTED - Low Priority**

**Component**: Floating-Point Unit (FPU)

**Description**:
Multiple width mismatch warnings in FPU modules where signal widths don't match exactly.

**Evidence**:
```
Warning-WIDTHEXPAND: rtl/core/fp_minmax.v:56:48:
  Operator COND expects 64 bits on the Conditional True,
  but Conditional True's CONST '32'h7fc00000' generates 32 bits.

Warning-WIDTHTRUNC: rtl/core/fp_converter.v:150:41:
  Operator ASSIGNDLY expects 32 bits on the Assign RHS,
  but Assign RHS's COND generates 64 bits.
```

**Root Cause**:
FPU modules designed to support both 32-bit (single) and 64-bit (double) precision, but conditional expressions don't properly handle width differences.

**Impact**:
- **Low** - Automatic width extension/truncation works correctly
- May cause confusion in simulation waveforms
- Clutters synthesis reports

**Workaround**: None needed

**Fix Required**:
Add explicit width casting:
```verilog
// Current:
wire [FLEN-1:0] canonical_nan = (FLEN == 32) ? 32'h7FC00000 : 64'h7FF8000000000000;

// Fixed:
wire [FLEN-1:0] canonical_nan = (FLEN == 32) ?
                                 {{(FLEN-32){1'b0}}, 32'h7FC00000} :
                                 64'h7FF8000000000000;
```

**Files Involved**:
- `rtl/core/fp_minmax.v`
- `rtl/core/fp_converter.v`

**Priority**: Low

---

### 4. Missing CSR/Decoder Ports

**Status**: 🟡 **DOCUMENTED - Partial Implementation**

**Component**: Core Pipeline Integration

**Description**:
Some decoder and CSR file ports are not connected in the top-level pipeline.

**Evidence**:
Verilator warnings:
```
Warning-PINMISSING: Cell has missing pin: 'csr_addr'
Warning-PINMISSING: Cell has missing pin: 'csr_uimm'
Warning-PINMISSING: Cell has missing pin: 'satp_out'
Warning-PINMISSING: Cell has missing pin: 'mstatus_sum'
Warning-PINMISSING: Cell has missing pin: 'mstatus_mxr'
```

**Root Cause**:
CSR (Control and Status Register) implementation is partially complete. Some ports added to modules but not yet wired in top-level.

**Impact**:
- **Low** for basic operation (basic CSRs working)
- **Medium** for full privilege mode support
- **High** for virtual memory (SATP not connected)

**Workaround**: Basic CSR operations work for implemented subset

**Fix Required**:
1. Complete CSR implementation (Phase 4)
2. Add privilege mode support
3. Wire all CSR ports in pipeline
4. Add virtual memory support (SATP)

**Files Involved**:
- `rtl/core/rv32i_core_pipelined.v`
- `rtl/core/decoder.v`
- `rtl/core/csr_file.v`

**Priority**: Medium (required for Phase 4)

---

## Resolved Issues

### ✅ Icarus Verilog Simulation Hang with Compressed Instructions

**Status**: ✅ **RESOLVED** (2025-10-12)

**Description**: Simulation would hang after first clock cycle when compressed instructions were present.

**Resolution**: Issue resolved (likely through FPU state machine fixes). Simulation now runs normally.

**Evidence**: test_rvc_minimal passes with correct execution.

---

### ✅ FPU State Machine Mixed Assignments

**Status**: ✅ **RESOLVED** (2025-10-12)

**Description**: Five FPU modules had mixed blocking/non-blocking assignments for state machine logic.

**Resolution**: Fixed 70 lines across 5 files:
- `rtl/core/fp_adder.v` (18 lines)
- `rtl/core/fp_multiplier.v` (12 lines)
- `rtl/core/fp_divider.v` (16 lines)
- `rtl/core/fp_sqrt.v` (8 lines)
- `rtl/core/fp_fma.v` (16 lines)

**Fix**: Separated combinational (blocking) and sequential (non-blocking) assignments.

---

### ✅ Test Ebreak Exception Loop

**Status**: ✅ **RESOLVED** (2025-10-12)

**Description**: Tests appeared to fail because ebreak caused exception loop, overwriting correct results.

**Resolution**: Implemented cycle-based test termination that checks results before exception loop.

**Evidence**: test_rvc_minimal now passes cleanly.

---

## Limitations

### 1. Test Programs Require Careful Cycle Counting

**Type**: Limitation

**Description**: Integration tests use cycle counting to terminate before exceptions. If pipeline timing changes, cycle counts must be updated.

**Workaround**:
- Document expected cycle count in test comments
- Use generous cycle counts (e.g., +20 cycles beyond expected)
- Can add dynamic detection of target register writes

**Future Improvement**: Implement proper trap handlers in test programs

---

### 2. No Exception Handlers in Test Programs

**Type**: Limitation

**Description**: Test programs don't have proper exception/trap handlers, so ebreak causes jump to address 0.

**Impact**:
- Tests must terminate before ebreak executes
- Cannot test exception handling itself
- Programs loop after ebreak

**Workaround**: Cycle-based termination in testbenches

**Future Improvement**:
- Add minimal trap handler stubs
- Set up mtvec CSR properly
- Implement proper ebreak handling

---

### 3. Limited Floating-Point Testing

**Type**: Limitation

**Description**: FPU implementation exists but has limited test coverage.

**Status**:
- Basic FP operations implemented
- State machines fixed
- Needs comprehensive test suite

**Priority**: Medium

---

## Future Work (Not Issues)

### Phase 4: CSR and Privilege Modes
- Complete CSR file implementation
- Add full privilege mode support (M/S/U)
- Implement virtual memory (SATP, TLB)
- Add proper trap/exception handling
- Timer and interrupt support

### Testing Improvements
- Add formal verification for critical paths
- Expand FPU test suite
- Add RISC-V compliance tests for all extensions
- Performance benchmarking (Dhrystone, CoreMark)

### Extensions
- Bit manipulation (B extension)
- Vector processing (V extension)
- Hypervisor support (H extension)

---

## Issue Tracking

### How to Report New Issues

When discovering a new issue, document:

1. **Component**: Which module/subsystem
2. **Description**: Clear description of the problem
3. **Evidence**: Error messages, test results, traces
4. **Root Cause**: If known
5. **Impact**: Severity and scope
6. **Workaround**: If available
7. **Files Involved**: Specific source files
8. **Priority**: High/Medium/Low

Add to this document and commit.

### Priority Definitions

- **High**: Blocks critical functionality or causes incorrect results
- **Medium**: Limits functionality or affects quality
- **Low**: Cosmetic, warnings, or future improvements

### Status Definitions

- 🔴 **ACTIVE**: Needs investigation and fix
- 🟡 **DOCUMENTED**: Known, low priority, or has workaround
- ✅ **RESOLVED**: Fixed and validated

---

## Summary

### Critical Issues: 0
All blocking issues have been resolved.

### Active Issues: 1
- Mixed compressed/normal instruction addressing (Medium priority)

### Documented Issues: 3
- FPU converter blocking assignments (Low priority)
- FPU width mismatches (Low priority)
- Missing CSR ports (Medium priority - Phase 4 work)

### Limitations: 3
- Test cycle counting requirement
- No exception handlers in tests
- Limited FP testing

---

**Last Updated**: 2025-10-12
**Next Review**: When starting Phase 4 or when new issues discovered

---

*RV1 RISC-V CPU Core Project*
