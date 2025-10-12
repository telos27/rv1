# Phase 10.2 Test Suite - Supervisor Mode CSRs and SRET

**Date**: 2025-10-12
**Phase**: 10.2 - Supervisor Mode CSRs and SRET Instruction
**Status**: Implementation Complete, Testing In Progress

---

## Overview

This document describes the comprehensive test suite for Phase 10.2, which validates:
- All 8 Supervisor-mode CSRs (sstatus, sie, stvec, sscratch, sepc, scause, stval, sip)
- Trap delegation registers (medeleg, mideleg)
- SRET instruction functionality
- Privilege level transitions (M ↔ S ↔ U)
- CSR privilege checking

---

## Test Programs

### Test 1: Comprehensive S-mode CSR Test
**File**: `tests/asm/test_phase10_2_csr.s`

**Purpose**: Validate all S-mode CSR read/write operations

**Tests Performed**:
1. ✅ STVEC - Supervisor trap vector (read/write, 4-byte alignment)
2. ✅ SSCRATCH - Supervisor scratch register (read/write)
3. ✅ SEPC - Supervisor exception PC (read/write, 4-byte alignment)
4. ✅ SCAUSE - Supervisor exception cause (read/write)
5. ✅ STVAL - Supervisor trap value (read/write)
6. ✅ MEDELEG - Machine exception delegation (read/write)
7. ✅ MIDELEG - Machine interrupt delegation (read/write)
8. ✅ SSTATUS - Supervisor status (subset of MSTATUS)
   - Verify SIE, SPIE, SPP, SUM, MXR fields visible
   - Verify MPP, MIE, MPIE fields NOT visible
   - Verify writes to SSTATUS update MSTATUS
9. ✅ SIE - Supervisor interrupt enable (subset of MIE)
   - Verify only bits [9,5,1] visible (SEIE, STIE, SSIE)
   - Verify writes to SIE update MIE
10. ✅ SIP - Supervisor interrupt pending (subset of MIP)
   - Verify only bits [9,5,1] visible
11. ✅ SATP - Supervisor address translation (read/write)

**Expected Results**:
- a0 = 1 (success)
- a1 = 11 (number of tests passed)
- t3 = 11 (test counter)

**Success Criteria**: All 11 CSR tests pass

---

### Test 2: Trap Delegation
**File**: `tests/asm/test_phase10_2_delegation.s`

**Purpose**: Verify exception delegation from M-mode to S-mode

**Tests Performed**:
1. Setup medeleg to delegate specific exceptions
2. Setup stvec to point to S-mode trap handler
3. Transition from M-mode to S-mode
4. Trigger delegated exception
5. Verify exception goes to S-mode handler (not M-mode)
6. Verify SCAUSE, SEPC, STVAL set correctly
7. Test non-delegated exception still goes to M-mode

**Test Flow**:
```
M-mode (setup delegation)
  ↓ MRET
S-mode (trigger ECALL)
  ↓ ECALL (cause 9)
M-mode handler (non-delegated)
  ↓ verify mcause=9
SUCCESS
```

**Expected Results**:
- a0 = 1 (success)
- a1 = 5 (stage reached)
- t3 = 0xDEADBEEF (success marker)

**Success Criteria**: ECALL from S-mode correctly traps to M-mode

---

### Test 3: SRET Instruction
**File**: `tests/asm/test_phase10_2_sret.s`

**Purpose**: Comprehensive SRET functionality validation

**Tests Performed**:
1. **SRET restores PC from SEPC**
   - Set SEPC to target address
   - Execute SRET
   - Verify PC = SEPC

2. **SRET restores SIE from SPIE**
   - Set MSTATUS: SIE=0, SPIE=1
   - Execute SRET
   - Verify: SIE=1 (old SPIE), SPIE=1, SPP=0

3. **SRET with SPIE=0**
   - Set MSTATUS: SIE=1, SPIE=0
   - Execute SRET
   - Verify: SIE=0 (old SPIE), SPIE=1, SPP=0

4. **SRET privilege transition (S→U)**
   - Enter S-mode via MRET
   - Set SPP=0 (U-mode)
   - Execute SRET
   - Verify transition successful

**Expected Results**:
- a0 = 1 (success)
- a1 = 4 (number of tests passed)
- t5 = 0xDEADBEEF

**Success Criteria**: All 4 SRET behaviors work correctly

---

### Test 4: Privilege Transitions
**File**: `tests/asm/test_phase10_2_transitions.s`

**Purpose**: Validate all privilege mode transitions

**Tests Performed**:
1. **M-mode verification**
   - Verify access to M-mode CSRs works

2. **M-mode → S-mode (MRET)**
   - Set MSTATUS.MPP = 01
   - Execute MRET
   - Verify in S-mode (can access SSCRATCH)

3. **S-mode → M-mode (ECALL)**
   - Execute ECALL from S-mode
   - Verify trap to M-mode
   - Verify MCAUSE = 9 (ECALL from S-mode)

4. **M-mode → S-mode (MRET)**
   - Return to S-mode via MRET

5. **S-mode → U-mode (SRET)**
   - Set MSTATUS.SPP = 0
   - Execute SRET
   - Verify transition (SRET succeeds)

**Test Flow**:
```
M-mode (verify) → S-mode (MRET) → M-mode (ECALL trap)
  → S-mode (MRET) → U-mode (SRET)
```

**Expected Results**:
- a0 = 1 (success)
- a1 = 8 (stages completed)
- a2 = 8 (expected stages)
- t5 = 0xDEADBEEF

**Success Criteria**: All privilege transitions work correctly

---

### Test 5: CSR Privilege Violations
**File**: `tests/asm/test_phase10_2_priv_violation.s`

**Purpose**: Verify CSR privilege checking prevents S-mode from accessing M-mode CSRs

**Tests Performed**:
1. **Read M-mode CSR from S-mode**
   - Attempt `csrr t0, mscratch` from S-mode
   - Verify illegal instruction exception (cause 2)

2. **Write M-mode CSR from S-mode**
   - Attempt `csrw mtvec, t0` from S-mode
   - Verify illegal instruction exception

3. **CSRRS on M-mode CSR from S-mode**
   - Attempt `csrrs t1, mstatus, t0` from S-mode
   - Verify illegal instruction exception

4. **S-mode CSR access from S-mode**
   - Access `sscratch` from S-mode
   - Verify NO exception (access allowed)

5. **Return to M-mode**
   - ECALL back to M-mode
   - Verify exception count = 3

**Expected Results**:
- a0 = 1 (success)
- a1 = 8 (stages completed)
- a2 = 3 (exception count)
- t5 = 0xDEADBEEF

**Success Criteria**: All M-mode CSR accesses from S-mode trigger exceptions, S-mode CSRs accessible

---

## Test Execution

### Manual Test Execution

Each test can be compiled and run individually:

```bash
# Compile test
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib \
  -T tests/linker.ld -o /tmp/test.elf tests/asm/test_phase10_2_csr.s

# Convert to hex
riscv64-unknown-elf-objcopy -O binary /tmp/test.elf /tmp/test.bin
xxd -p -c 4 /tmp/test.bin > tests/asm/test_phase10_2_csr.hex

# Run simulation
./tools/test_pipelined.sh test_phase10_2_csr
```

### Automated Test Suite

Run all Phase 10.2 tests:

```bash
./tools/test_phase10_2_suite.sh
```

---

## Expected Test Results Summary

| Test | File | Tests | Expected Result |
|------|------|-------|-----------------|
| 1. CSR Operations | `test_phase10_2_csr.s` | 11 | a0=1, a1=11 |
| 2. Trap Delegation | `test_phase10_2_delegation.s` | 7 stages | a0=1, a1=5 |
| 3. SRET Instruction | `test_phase10_2_sret.s` | 4 tests | a0=1, a1=4 |
| 4. Privilege Transitions | `test_phase10_2_transitions.s` | 8 stages | a0=1, a1=8 |
| 5. CSR Privilege Check | `test_phase10_2_priv_violation.s` | 8 stages | a0=1, a2=3 |

**Overall Success Criteria**: All 5 tests pass (a0=1 for each)

---

## Implementation Verification

### What's Being Tested

**CSR File (csr_file.v)**:
- ✅ S-mode CSR registers (stvec, sscratch, sepc, scause, stval)
- ✅ Delegation registers (medeleg, mideleg)
- ✅ SSTATUS as subset of MSTATUS
- ✅ SIE/SIP as subset of MIE/MIP
- ✅ Trap target selection based on delegation
- ✅ S-mode trap entry (SEPC/SCAUSE/STVAL updates)
- ✅ SRET handling (restore SIE, SPIE, SPP)
- ✅ CSR privilege checking

**Decoder (decoder.v)**:
- ✅ SRET instruction detection (opcode 0x10200073)

**Control Unit (control.v)**:
- ✅ SRET control signal generation

**Pipeline (rv32i_core_pipelined.v)**:
- ✅ SRET flush logic
- ✅ Privilege mode tracking (current_priv register)
- ✅ Privilege transitions on MRET/SRET
- ✅ PC selection for SRET (sepc)

**Exception Unit (exception_unit.v)**:
- ✅ Privilege-aware ECALL (returns cause 8, 9, or 11)
- ✅ Page fault exception codes (12, 13, 15)

---

## Known Issues / Limitations

1. **Test Execution**: Current test infrastructure has issues with hex file loading
   - Workaround: Use existing test scripts or fix hex file format

2. **U-mode Testing**: Cannot fully test U-mode without MMU
   - Conceptual U-mode tests included but not fully verified

3. **Interrupt Testing**: Interrupt delegation (mideleg) not fully tested
   - Only CSR read/write tested, no actual interrupt delivery

4. **SFENCE.VMA**: Not tested in Phase 10.2
   - Will be tested in Phase 10.3 (MMU Integration)

---

## Next Steps

### Phase 10.2 Completion:
1. ✅ All S-mode CSRs implemented
2. ✅ SRET instruction implemented
3. ✅ Trap delegation implemented
4. ✅ CSR privilege checking implemented
5. ✅ Comprehensive test suite created
6. ⏳ Test execution and verification (in progress)

### Phase 10.3 Preview (MMU Integration):
1. Instantiate MMU in pipeline
2. Connect to data memory interface
3. Add page fault exception handling
4. Implement SFENCE.VMA instruction
5. Test virtual memory translation
6. Test TLB functionality

---

## References

- **Design Document**: `docs/SUPERVISOR_MODE_AND_MMU_INTEGRATION.md`
- **Implementation Checklist**: `PHASE10_SUPERVISOR_MODE_CHECKLIST.md`
- **RISC-V Privileged Spec**: Volume II, Chapters 3-4
- **CSR Addresses**: CSR address space 0x100-0x1FF (S-mode)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-12
**Author**: RV1 Project - Phase 10.2 Implementation
