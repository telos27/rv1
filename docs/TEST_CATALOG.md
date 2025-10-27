# Test Catalog

**Auto-generated test documentation**
**Generated**: $(date)
**Total Custom Tests**: $(ls -1 tests/asm/*.s 2>/dev/null | wc -l)
**Total Official Tests**: 81

---

## Table of Contents

1. [Custom Tests](#custom-tests)
   - [By Category](#by-category)
   - [Alphabetical Index](#alphabetical-index)
2. [Official Compliance Tests](#official-compliance-tests)
3. [Test Statistics](#test-statistics)

---

## Custom Tests

### By Category


#### Privilege Mode

**Tests**: 7

- **test_priv_basic.s** ✅
  - Test 1: Basic Privilege Mode Testing
  - Lines: 24

- **test_priv_check.s** ✅
  - Check Privilege Mode
  - Lines: 25

- **test_priv_comprehensive.s** ✅
  - Comprehensive Privilege Mode Regression (Phase 7.2)
  - Lines: 151

- **test_priv_macros_demo.s** ✅
  - Privilege Macro Library Demo
  - Lines: 42

- **test_priv_minimal.s** ✅
  - Minimal CSR Test
  - Lines: 16

- **test_priv_rapid_switching.s** ✅
  - Rapid Privilege Mode Switching (Phase 7.1)
  - Lines: 39

- **test_priv_transitions.s** ✅
  - Privilege Mode Transitions
  - Lines: 42


#### Edge Cases

**Tests**: 6

- **test_edge_branch_offset.s** ✅
  - Test Edge Cases: Branch and Jump Offset Limits
  - Lines: 199

- **test_edge_divide.s** ✅
  - Test Edge Cases: Division and Remainder Operations
  - Lines: 142

- **test_edge_fp_special.s** ✅
  - Test Edge Cases: Floating-Point Special Values
  - Lines: 117

- **test_edge_immediates.s** ✅
  - Test Edge Cases: Immediate Value Limits
  - Lines: 122

- **test_edge_integer.s** ✅
  - Test Edge Cases: Integer Arithmetic
  - Lines: 68

- **test_edge_multiply.s** ✅
  - Test Edge Cases: Multiply Operations
  - Lines: 106


#### MMU/Virtual Memory

**Tests**: 1

- **test_mmu_enabled.s** ✅
  - Verify MMU is actually enabled and translating
  - Lines: 17


#### RV64 Specific

**Tests**: 2

- **test_rv64i_arithmetic.s** ❌
  - test_rv64i_arithmetic.s
  - Lines: 104

- **test_rv64i_basic.s** ❌
  - test_rv64i_basic.s
  - Lines: 79


#### Atomic Operations

**Tests**: 1

- **test_atomic_simple.s** ✅
  - Test Program: Basic Atomic Operations (A Extension)
  - Lines: 95


#### A Extension (AMO Operations)

**Tests**: 2

- **test_amo_alignment.s** ✅
  - Test Program: AMO Alignment (Compact)
  - Lines: 36

- **test_amo_aq_rl.s** ✅
  - Test Program: AMO Memory Ordering (Compact)
  - Lines: 41


#### Floating-Point (F+D)

**Tests**: 13

- **test_fp_add_simple.s** ✅
  - Simplest FP Add Test
  - Lines: 29

- **test_fp_basic.s** ✅
  - Basic Floating-Point Test
  - Lines: 48

- **test_fp_compare.s** ✅
  - Floating-Point Compare Test
  - Lines: 65

- **test_fp_compare_simple.s** ✅
  - Simple FP Compare Test - Debug Version
  - Lines: 22

- **test_fp_convert.s** ✅
  - Floating-Point Conversion Test
  - Lines: 79

- **test_fp_csr.s** ✅
  - Floating-Point CSR Test
  - Lines: 50

- **test_fp_fma.s** ✅
  - Floating-Point FMA (Fused Multiply-Add) Test
  - Lines: 58

- **test_fp_load_use.s** ✅
  - Floating-Point Load-Use Hazard Test
  - Lines: 52

- **test_fp_loadstore_nop.s** ✅
  - Test FP Load/Store with NOPs
  - Lines: 25

- **test_fp_loadstore_only.s** ✅
  - Test FP Load/Store Only
  - Lines: 22

- **test_fp_minimal.s** ✅
  - Minimal FP Test - Just test FLW and FSW
  - Lines: 18

- **test_fp_misc.s** ✅
  - Floating-Point Miscellaneous Operations Test
  - Lines: 78

- **test_fp_ultra_minimal.s** ✅
  - Ultra Minimal Test - No FP, just to verify basic execution
  - Lines: 7


#### CSR Instructions

**Tests**: 9

- **test_csr_basic.s** ✅
  - Test CSR instructions
  - Lines: 16

- **test_csr_compare.s** ✅
  - Compare CSR reads - mscratch vs mstatus
  - Lines: 14

- **test_csr_debug.s** ✅
  - CSR Debug - Check what CSR read returns
  - Lines: 13

- **test_csr_illegal_access.s** ✅
  - CSR Illegal Access Verification
  - Lines: 70

- **test_csr_readonly_verify.s** ✅
  - CSR Read-Only Verification (Simplified)
  - Lines: 56
  - Expected: All CSRs return the same value on multiple reads

- **test_csr_scratch.s** ✅
  - Simple CSR Read/Write - mscratch only
  - Lines: 9
  - Expected: mscratch should read back written value

- **test_csr_side_effects.s** ✅
  - CSR Side Effects Verification
  - Lines: 109
  - Expected: Changes propagate correctly between related CSRs

- **test_csr_warl_fields.s** ✅
  - CSR WARL Fields Verification
  - Lines: 114
  - Expected: Illegal values are converted to legal values

- **test_csr_write_read.s** ✅
  - CSR Write-Then-Read
  - Lines: 21


#### Miscellaneous

**Tests**: 135

- **branch_test.s** ✅
  - Branch Instructions Test
  - Lines: 95

- **fibonacci.s** ✅
  - Expected: Expected result: x10 = 55
  - Lines: 27

- **jump_test.s** ✅
  - Jump and Upper Immediate Test
  - Lines: 71

- **load_store.s** ✅
  - Test load and store operations
  - Lines: 14

- **logic_ops.s** ✅
  - Logic Operations Test
  - Lines: 68

- **shift_ops.s** ✅
  - Shift Operations Test
  - Lines: 64

- **simple_add.s** ✅
  - Simple test: Add two numbers
  - Lines: 8

- **test_21_pattern.s** ✅
  - Replicate test 21 pattern from compliance
  - Lines: 24

- **test_amoadd.s** ✅
  - Test Program: AMOADD.W - Atomic Add (Compact Version)
  - Lines: 43

- **test_amoand_or_xor.s** ✅
  - Test Program: AMOAND/AMOOR/AMOXOR - Logical AMOs (Compact)
  - Lines: 41

- **test_amomin_max.s** ✅
  - Test Program: AMOMIN/AMOMAX/AMOMINU/AMOMAXU (Compact)
  - Lines: 51

- **test_amoswap.s** ✅
  - Test Program: AMOSWAP.W - Atomic Swap (Compact Version)
  - Lines: 44

- **test_and_loop.s** ✅
  - Replicate the exact pattern from compliance test 19
  - Lines: 24

- **test_branch_forward.s** ✅
  - Test forwarding after branch
  - Lines: 21

- **test_copy_simple.s** ✅
  - Simple test: Add two numbers
  - Lines: 8

- **test_debug_mret.s** ✅
  - Debug test - just check what MRET does to mstatus
  - Lines: 21

- **test_debug_mstatus.s** ✅
  - Debug mstatus read - check what's failing
  - Lines: 21

- **test_delegation_disable.s** ✅
  - Delegation Disable
  - Lines: 50

- **test_delegation_to_current_mode.s** ✅
  - Delegation to Current Mode
  - Lines: 36

- **test_div_by_zero.s** ✅
  - Test division by zero behavior
  - Lines: 24

- **test_div_comprehensive.s** ✅
  - Comprehensive DIV/DIVU/REM/REMU test
  - Lines: 35

- **test_div_simple.s** ✅
  - Simple DIV test to debug the division bug
  - Lines: 15

- **test_ebreak_timing.s** ✅
  - Test EBREAK timing - when do register writes complete?
  - Lines: 12

- **test_ecall_simple.s** ✅
  - Simple ECALL Test
  - Lines: 29

- **test_ecall_smode.s** ✅
  - ECALL from S-mode and Trap Delegation
  - Lines: 57

- **test_enter_smode.s** ✅
  - Enter S-mode
  - Lines: 38

- **test_exception_breakpoint.s** ✅
  - test_exception_breakpoint.s
  - Lines: 129

- **test_exception_ecall_mmode.s** ✅
  - test_exception_ecall_mmode.s
  - Lines: 49

- **test_exception_instr_misaligned.s** ✅
  - test_exception_instr_misaligned.s
  - Lines: 114

- **test_exception_page_faults.s** ✅
  - test_exception_page_faults.s
  - Lines: 25

- **test_fcvt_edges.s** ✅
  - Test FCVT.S.W Edge Cases
  - Lines: 83

- **test_fcvt_fp2int.s** ✅
  - Test FCVT.W.S and FCVT.WU.S (Float → Integer)
  - Lines: 119

- **test_fcvt_negatives.s** ✅
  - Test FCVT.S.W with negative integers
  - Lines: 24

- **test_fcvt_simple.s** ✅
  - Simple FCVT.S.W test - convert integer to float
  - Lines: 17

- **test_fcvt_unsigned.s** ✅
  - Test FCVT.S.WU (Unsigned Integer → Float)
  - Lines: 71

- **test_fcvt_w_simple.s** ✅
  - Simple test for fcvt.w.s with 0.9
  - Lines: 20
  - Expected: result=0, fflags=0x01 (NX)

- **test_fcvt_w_test7.s** ✅
  - Test fcvt.w.s 1.1 specifically (test #7 from compliance suite)
  - Lines: 22
  - Expected: result=1, flags=0x01 (NX)

- **test_fdiv_debug.s** ✅
  - No description available
  - Lines: 28

- **test_fld_minimal.s** ❌
  - Minimal FLD Test
  - Lines: 16

- **test_fmv_xw.s** ✅
  - Test FMV.X.W instruction (FP to Integer register move)
  - Lines: 24

- **test_forwarding_and.s** ✅
  - Minimal test to expose data forwarding bug with AND instruction
  - Lines: 29

- **test_fsqrt_edge.s** ✅
  - No description available
  - Lines: 29

- **test_fsqrt_simple.s** ✅
  - No description available
  - Lines: 17

- **test_int_load.s** ✅
  - Test Integer Load (sanity check)
  - Lines: 17

- **test_interrupt_masking.s** ✅
  - Test 3.5: Interrupt Masking
  - Lines: 92

- **test_interrupt_pending.s** ✅
  - Test 3.4: Interrupt Pending Bits
  - Lines: 78

- **test_interrupt_software.s** ✅
  - Test 3.1: Software Interrupt CSRs
  - Lines: 59

- **test_lb_detailed.s** ✅
  - Detailed LB (load byte) test
  - Lines: 42

- **test_li.s** ✅
  - Test LI pseudo-instruction
  - Lines: 11

- **test_load_high_addr.s** ✅
  - Test loading from high address space (0x80000000+)
  - Lines: 14

- **test_load_minimal.s** ✅
  - Minimal load test to debug pipeline bug
  - Lines: 14
  - Expected: Load should return the stored value

- **test_load_preinitialized.s** ✅
  - Test loading from pre-initialized memory
  - Lines: 20

- **test_load_to_branch.s** ✅
  - Minimal test for load-to-branch hazard
  - Lines: 16

- **test_load_use.s** ✅
  - Test load-use hazard detection
  - Lines: 21

- **test_lr_only.s** ✅
  - Test LR instruction only
  - Lines: 15

- **test_lr_sc_direct.s** ✅
  - Test LR/SC back-to-back
  - Lines: 17

- **test_lr_sc_minimal.s** ✅
  - Minimal LR/SC Test
  - Lines: 22

- **test_lrsc_debug.s** ✅
  - Test LR/SC basic operation
  - Lines: 37

- **test_lrsc_minimal.s** ✅
  - Minimal LR/SC test to debug forwarding hazard
  - Lines: 23

- **test_lui_1nop_minimal.s** ✅
  - Minimal test for 1-NOP LUI bug
  - Lines: 9

- **test_lui_addi.s** ✅
  - Minimal test for LUI followed by ADDI (same register)
  - Lines: 14

- **test_lui_spacing.s** ✅
  - Test LUI with different amounts of spacing before ADDI
  - Lines: 28

- **test_macro_simple.s** ✅
  - Basic Register Operations
  - Lines: 9

- **test_marker_check.s** ✅
  - Test marker mechanism
  - Lines: 11

- **test_medeleg.s** ✅
  - MEDELEG CSR Test
  - Lines: 22

- **test_misaligned.s** ✅
  - Test misaligned memory access
  - Lines: 27

- **test_misaligned_debug.s** ✅
  - Test misaligned halfword store + byte load (test 92 reproduction)
  - Lines: 24

- **test_misaligned_simple.s** ✅
  - Simple misaligned access test
  - Lines: 18

- **test_mixed_real.s** ✅
  - test_mixed_real.s - Real mixed 16-bit and 32-bit instructions
  - Lines: 15

- **test_mret_simple.s** ✅
  - Simple MRET test
  - Lines: 25

- **test_mret_trap_simple.s** ✅
  - Simple test: MRET in U-mode should trap
  - Lines: 19

- **test_mret_umode_minimal.s** ✅
  - Minimal test: MRET in U-mode should trap
  - Lines: 28
  - Expected: Illegal instruction exception (cause=2)

- **test_mstatus_basic.s** ✅
  - Basic mstatus read/write
  - Lines: 16

- **test_mstatus_csrrw.s** ✅
  - MSTATUS CSR Read/Write Test
  - Lines: 16

- **test_mstatus_direct.s** ✅
  - Direct test - write and read mstatus
  - Lines: 24

- **test_mstatus_interrupt_enables.s** ✅
  - Test 2.5: Interrupt Enable Verification
  - Lines: 83

- **test_mstatus_nested_traps.s** ✅
  - Test 2.4: Sequential Trap Handling
  - Lines: 102

- **test_mstatus_state_mret.s** ✅
  - Test 2.1: MRET State Transitions
  - Lines: 72

- **test_mstatus_state_mret_simple.s** ✅
  - Simple test for MRET state transitions
  - Lines: 40

- **test_mstatus_state_sret.s** ✅
  - Test 2.2: SRET State Transitions
  - Lines: 131

- **test_mstatus_state_trap.s** ✅
  - Test 2.3: Trap Entry State Transitions
  - Lines: 68

- **test_nop.s** ✅
  - Minimal NOP test to verify pipeline still works
  - Lines: 9

- **test_page_fault_invalid.s** ✅
  - Page Fault - Invalid Page (V=0)
  - Lines: 44

- **test_page_fault_smode.s** ✅
  - Page Fault in S-mode
  - Lines: 54

- **test_phase10_2_csr.s** ✅
  - Phase 10.2 - Supervisor Mode CSRs
  - Lines: 99

- **test_phase10_2_delegation.s** ✅
  - Phase 10.2 - Trap Delegation to S-mode
  - Lines: 61

- **test_phase10_2_priv_violation.s** ✅
  - Phase 10.2 - CSR Privilege Violation
  - Lines: 97

- **test_phase10_2_sret.s** ✅
  - Phase 10.2 - SRET Instruction
  - Lines: 97

- **test_phase10_2_transitions.s** ✅
  - Phase 10.2 - Privilege Mode Transitions
  - Lines: 90

- **test_raw_hazards.s** ✅
  - Test RAW (Read-After-Write) Hazard Handling
  - Lines: 25

- **test_rvc_basic.s** ❌
  - test_rvc_basic.s - Basic RVC (Compressed) Instruction Test
  - Lines: 31

- **test_rvc_control.s** ❌
  - test_rvc_control.s - RVC Control Flow Test
  - Lines: 34

- **test_rvc_debug_jump.s** ❌
  - Test for debugging JAL to halfword-aligned address
  - Lines: 28

- **test_rvc_minimal.s** ✅
  - test_rvc_minimal.s - Minimal RVC test with only 4-byte aligned compressed instructions
  - Lines: 10

- **test_rvc_mixed.s** ❌
  - test_rvc_mixed.s - Mixed Compressed and Non-Compressed Instructions Test
  - Lines: 62

- **test_rvc_simple.s** ✅
  - test_rvc_simple.s - Simple RVC Integration Test
  - Lines: 11

- **test_rvc_stack.s** ❌
  - test_rvc_stack.s - RVC Stack Operations Test
  - Lines: 44

- **test_sc_only.s** ✅
  - Test SC instruction only (should fail since no prior LR)
  - Lines: 16

- **test_shifts_debug.s** ✅
  - Test program to debug right shift operations
  - Lines: 21

- **test_simple.s** ✅
  - test_simple.s
  - Lines: 14

- **test_simple_check.s** ✅
  - No description available
  - Lines: 12

- **test_simple_csr.s** ✅
  - Simple CSR test - just test one CSR
  - Lines: 12

- **test_simple_fp_load.s** ✅
  - Simple FP Load Test - Matches simple_add pattern
  - Lines: 9

- **test_simple_raw.s** ✅
  - Simple RAW hazard test
  - Lines: 9

- **test_smode_csr.s** ✅
  - Supervisor Mode CSR Read/Write
  - Lines: 41

- **test_smode_entry.s** ✅
  - Test S-mode entry and sstatus read
  - Lines: 26

- **test_smode_priv_check.s** ✅
  - No description available
  - Lines: 37

- **test_sret.s** ✅
  - SRET instruction
  - Lines: 14

- **test_sret_check_mmode.s** ✅
  - Test SRET by checking mstatus from M-mode afterward
  - Lines: 37

- **test_sret_debug.s** ✅
  - No description available
  - Lines: 38

- **test_sret_debug2.s** ✅
  - No description available
  - Lines: 32

- **test_sret_debug3.s** ✅
  - Test SRET SIE/SPIE updates
  - Lines: 37

- **test_sret_minimal.s** ✅
  - Minimal SRET test - just execute SRET and check SPIE
  - Lines: 30

- **test_sret_mstatus_trace.s** ✅
  - No description available
  - Lines: 44

- **test_sret_no_csr_after.s** ✅
  - Test SRET SPIE without any CSR reads after SRET
  - Lines: 38

- **test_sret_sie_spie.s** ✅
  - Test SRET SIE/SPIE handling
  - Lines: 38

- **test_sret_simple.s** ✅
  - Minimal SRET test to debug SIE/SPIE behavior
  - Lines: 41

- **test_sret_spie_debug.s** ✅
  - Minimal test to debug SRET SPIE update issue
  - Lines: 42

- **test_sret_spie_mem_dump.s** ✅
  - Test SRET SPIE with memory dumps for inspection
  - Lines: 37

- **test_sret_spie_simple.s** ✅
  - Ultra-minimal test to debug SRET SPIE update
  - Lines: 36

- **test_sret_stage2_only.s** ✅
  - Test only stage 2 of SRET test
  - Lines: 36

- **test_stage1_and_2.s** ✅
  - Test stages 1 and 2 only
  - Lines: 47

- **test_stage1_only.s** ✅
  - Test stage 1 only: SPIE=0, SIE=1 → SRET → SIE=0, SPIE=1
  - Lines: 40

- **test_store_load.s** ✅
  - Test simple store and load
  - Lines: 16

- **test_stvec_simple.s** ✅
  - Simple STVEC test with NOPs to avoid hazards
  - Lines: 21

- **test_supervisor_basic.s** ✅
  - Basic Supervisor Mode CSR Access and SRET
  - Lines: 50

- **test_supervisor_complete.s** ✅
  - Comprehensive Supervisor Mode Test
  - Lines: 54

- **test_umode_csr_violation.s** ✅
  - test_umode_csr_violation.s
  - Lines: 47

- **test_umode_ecall.s** ✅
  - test_umode_ecall.s
  - Lines: 29

- **test_umode_entry_from_mmode.s** ✅
  - test_umode_entry_from_mmode.s
  - Lines: 28

- **test_umode_entry_from_smode.s** ✅
  - test_umode_entry_from_smode.s
  - Lines: 31

- **test_umode_illegal_instr.s** ✅
  - test_umode_illegal_instr.s
  - Lines: 25

- **test_vm_identity.s** ✅
  - Basic Virtual Memory with Identity Mapping
  - Lines: 48

- **test_x28_write.s** ✅
  - Test writing to x28
  - Lines: 7

- **test_xret_privilege_trap.s** ✅
  - test_xret_privilege_trap.s
  - Lines: 60


#### M Extension (Multiply/Divide)

**Tests**: 10

- **test_m_after.s** ✅
  - Test instructions after MUL
  - Lines: 15

- **test_m_basic.s** ✅
  - RV32M Basic Test
  - Lines: 96

- **test_m_debug.s** ✅
  - Minimal M extension debug test
  - Lines: 29

- **test_m_debug2.s** ✅
  - No description available
  - Lines: 13

- **test_m_hazard.s** ✅
  - Test M Extension Data Hazard
  - Lines: 19

- **test_m_incremental.s** ✅
  - Incremental M extension test - test each instruction individually
  - Lines: 64

- **test_m_lui_issue.s** ✅
  - Test to isolate LUI immediately after MUL issue
  - Lines: 30

- **test_m_seq.s** ✅
  - Test sequence of M operations
  - Lines: 21

- **test_m_simple.s** ✅
  - Simplest possible M test - single MUL
  - Lines: 12

- **test_m_simple_nops.s** ✅
  - M test with NOPs after MUL
  - Lines: 15


---

### Alphabetical Index

- **branch_test** - Branch Instructions Test
  - Category: Miscellaneous
- **fibonacci** - Expected: Expected result: x10 = 55
  - Category: Miscellaneous
- **jump_test** - Jump and Upper Immediate Test
  - Category: Miscellaneous
- **load_store** - Test load and store operations
  - Category: Miscellaneous
- **logic_ops** - Logic Operations Test
  - Category: Miscellaneous
- **shift_ops** - Shift Operations Test
  - Category: Miscellaneous
- **simple_add** - Simple test: Add two numbers
  - Category: Miscellaneous
- **test_21_pattern** - Replicate test 21 pattern from compliance
  - Category: Miscellaneous
- **test_amo_alignment** - Test Program: AMO Alignment (Compact)
  - Category: A Extension (AMO Operations)
- **test_amo_aq_rl** - Test Program: AMO Memory Ordering (Compact)
  - Category: A Extension (AMO Operations)
- **test_amoadd** - Test Program: AMOADD.W - Atomic Add (Compact Version)
  - Category: Miscellaneous
- **test_amoand_or_xor** - Test Program: AMOAND/AMOOR/AMOXOR - Logical AMOs (Compact)
  - Category: Miscellaneous
- **test_amomin_max** - Test Program: AMOMIN/AMOMAX/AMOMINU/AMOMAXU (Compact)
  - Category: Miscellaneous
- **test_amoswap** - Test Program: AMOSWAP.W - Atomic Swap (Compact Version)
  - Category: Miscellaneous
- **test_and_loop** - Replicate the exact pattern from compliance test 19
  - Category: Miscellaneous
- **test_atomic_simple** - Test Program: Basic Atomic Operations (A Extension)
  - Category: Atomic Operations
- **test_branch_forward** - Test forwarding after branch
  - Category: Miscellaneous
- **test_copy_simple** - Simple test: Add two numbers
  - Category: Miscellaneous
- **test_csr_basic** - Test CSR instructions
  - Category: CSR Instructions
- **test_csr_compare** - Compare CSR reads - mscratch vs mstatus
  - Category: CSR Instructions
- **test_csr_debug** - CSR Debug - Check what CSR read returns
  - Category: CSR Instructions
- **test_csr_illegal_access** - CSR Illegal Access Verification
  - Category: CSR Instructions
- **test_csr_readonly_verify** - CSR Read-Only Verification (Simplified)
  - Category: CSR Instructions
- **test_csr_scratch** - Simple CSR Read/Write - mscratch only
  - Category: CSR Instructions
- **test_csr_side_effects** - CSR Side Effects Verification
  - Category: CSR Instructions
- **test_csr_warl_fields** - CSR WARL Fields Verification
  - Category: CSR Instructions
- **test_csr_write_read** - CSR Write-Then-Read
  - Category: CSR Instructions
- **test_debug_mret** - Debug test - just check what MRET does to mstatus
  - Category: Miscellaneous
- **test_debug_mstatus** - Debug mstatus read - check what's failing
  - Category: Miscellaneous
- **test_delegation_disable** - Delegation Disable
  - Category: Miscellaneous
- **test_delegation_to_current_mode** - Delegation to Current Mode
  - Category: Miscellaneous
- **test_div_by_zero** - Test division by zero behavior
  - Category: Miscellaneous
- **test_div_comprehensive** - Comprehensive DIV/DIVU/REM/REMU test
  - Category: Miscellaneous
- **test_div_simple** - Simple DIV test to debug the division bug
  - Category: Miscellaneous
- **test_ebreak_timing** - Test EBREAK timing - when do register writes complete?
  - Category: Miscellaneous
- **test_ecall_simple** - Simple ECALL Test
  - Category: Miscellaneous
- **test_ecall_smode** - ECALL from S-mode and Trap Delegation
  - Category: Miscellaneous
- **test_edge_branch_offset** - Test Edge Cases: Branch and Jump Offset Limits
  - Category: Edge Cases
- **test_edge_divide** - Test Edge Cases: Division and Remainder Operations
  - Category: Edge Cases
- **test_edge_fp_special** - Test Edge Cases: Floating-Point Special Values
  - Category: Edge Cases
- **test_edge_immediates** - Test Edge Cases: Immediate Value Limits
  - Category: Edge Cases
- **test_edge_integer** - Test Edge Cases: Integer Arithmetic
  - Category: Edge Cases
- **test_edge_multiply** - Test Edge Cases: Multiply Operations
  - Category: Edge Cases
- **test_enter_smode** - Enter S-mode
  - Category: Miscellaneous
- **test_exception_breakpoint** - test_exception_breakpoint.s
  - Category: Miscellaneous
- **test_exception_ecall_mmode** - test_exception_ecall_mmode.s
  - Category: Miscellaneous
- **test_exception_instr_misaligned** - test_exception_instr_misaligned.s
  - Category: Miscellaneous
- **test_exception_page_faults** - test_exception_page_faults.s
  - Category: Miscellaneous
- **test_fcvt_edges** - Test FCVT.S.W Edge Cases
  - Category: Miscellaneous
- **test_fcvt_fp2int** - Test FCVT.W.S and FCVT.WU.S (Float → Integer)
  - Category: Miscellaneous
- **test_fcvt_negatives** - Test FCVT.S.W with negative integers
  - Category: Miscellaneous
- **test_fcvt_simple** - Simple FCVT.S.W test - convert integer to float
  - Category: Miscellaneous
- **test_fcvt_unsigned** - Test FCVT.S.WU (Unsigned Integer → Float)
  - Category: Miscellaneous
- **test_fcvt_w_simple** - Simple test for fcvt.w.s with 0.9
  - Category: Miscellaneous
- **test_fcvt_w_test7** - Test fcvt.w.s 1.1 specifically (test #7 from compliance suite)
  - Category: Miscellaneous
- **test_fdiv_debug** - No description available
  - Category: Miscellaneous
- **test_fld_minimal** - Minimal FLD Test
  - Category: Miscellaneous
- **test_fmv_xw** - Test FMV.X.W instruction (FP to Integer register move)
  - Category: Miscellaneous
- **test_forwarding_and** - Minimal test to expose data forwarding bug with AND instruction
  - Category: Miscellaneous
- **test_fp_add_simple** - Simplest FP Add Test
  - Category: Floating-Point (F+D)
- **test_fp_basic** - Basic Floating-Point Test
  - Category: Floating-Point (F+D)
- **test_fp_compare** - Floating-Point Compare Test
  - Category: Floating-Point (F+D)
- **test_fp_compare_simple** - Simple FP Compare Test - Debug Version
  - Category: Floating-Point (F+D)
- **test_fp_convert** - Floating-Point Conversion Test
  - Category: Floating-Point (F+D)
- **test_fp_csr** - Floating-Point CSR Test
  - Category: Floating-Point (F+D)
- **test_fp_fma** - Floating-Point FMA (Fused Multiply-Add) Test
  - Category: Floating-Point (F+D)
- **test_fp_load_use** - Floating-Point Load-Use Hazard Test
  - Category: Floating-Point (F+D)
- **test_fp_loadstore_nop** - Test FP Load/Store with NOPs
  - Category: Floating-Point (F+D)
- **test_fp_loadstore_only** - Test FP Load/Store Only
  - Category: Floating-Point (F+D)
- **test_fp_minimal** - Minimal FP Test - Just test FLW and FSW
  - Category: Floating-Point (F+D)
- **test_fp_misc** - Floating-Point Miscellaneous Operations Test
  - Category: Floating-Point (F+D)
- **test_fp_ultra_minimal** - Ultra Minimal Test - No FP, just to verify basic execution
  - Category: Floating-Point (F+D)
- **test_fsqrt_edge** - No description available
  - Category: Miscellaneous
- **test_fsqrt_simple** - No description available
  - Category: Miscellaneous
- **test_int_load** - Test Integer Load (sanity check)
  - Category: Miscellaneous
- **test_interrupt_masking** - Test 3.5: Interrupt Masking
  - Category: Miscellaneous
- **test_interrupt_pending** - Test 3.4: Interrupt Pending Bits
  - Category: Miscellaneous
- **test_interrupt_software** - Test 3.1: Software Interrupt CSRs
  - Category: Miscellaneous
- **test_lb_detailed** - Detailed LB (load byte) test
  - Category: Miscellaneous
- **test_li** - Test LI pseudo-instruction
  - Category: Miscellaneous
- **test_load_high_addr** - Test loading from high address space (0x80000000+)
  - Category: Miscellaneous
- **test_load_minimal** - Minimal load test to debug pipeline bug
  - Category: Miscellaneous
- **test_load_preinitialized** - Test loading from pre-initialized memory
  - Category: Miscellaneous
- **test_load_to_branch** - Minimal test for load-to-branch hazard
  - Category: Miscellaneous
- **test_load_use** - Test load-use hazard detection
  - Category: Miscellaneous
- **test_lr_only** - Test LR instruction only
  - Category: Miscellaneous
- **test_lr_sc_direct** - Test LR/SC back-to-back
  - Category: Miscellaneous
- **test_lr_sc_minimal** - Minimal LR/SC Test
  - Category: Miscellaneous
- **test_lrsc_debug** - Test LR/SC basic operation
  - Category: Miscellaneous
- **test_lrsc_minimal** - Minimal LR/SC test to debug forwarding hazard
  - Category: Miscellaneous
- **test_lui_1nop_minimal** - Minimal test for 1-NOP LUI bug
  - Category: Miscellaneous
- **test_lui_addi** - Minimal test for LUI followed by ADDI (same register)
  - Category: Miscellaneous
- **test_lui_spacing** - Test LUI with different amounts of spacing before ADDI
  - Category: Miscellaneous
- **test_m_after** - Test instructions after MUL
  - Category: M Extension (Multiply/Divide)
- **test_m_basic** - RV32M Basic Test
  - Category: M Extension (Multiply/Divide)
- **test_m_debug** - Minimal M extension debug test
  - Category: M Extension (Multiply/Divide)
- **test_m_debug2** - No description available
  - Category: M Extension (Multiply/Divide)
- **test_m_hazard** - Test M Extension Data Hazard
  - Category: M Extension (Multiply/Divide)
- **test_m_incremental** - Incremental M extension test - test each instruction individually
  - Category: M Extension (Multiply/Divide)
- **test_m_lui_issue** - Test to isolate LUI immediately after MUL issue
  - Category: M Extension (Multiply/Divide)
- **test_m_seq** - Test sequence of M operations
  - Category: M Extension (Multiply/Divide)
- **test_m_simple** - Simplest possible M test - single MUL
  - Category: M Extension (Multiply/Divide)
- **test_m_simple_nops** - M test with NOPs after MUL
  - Category: M Extension (Multiply/Divide)
- **test_macro_simple** - Basic Register Operations
  - Category: Miscellaneous
- **test_marker_check** - Test marker mechanism
  - Category: Miscellaneous
- **test_medeleg** - MEDELEG CSR Test
  - Category: Miscellaneous
- **test_misaligned** - Test misaligned memory access
  - Category: Miscellaneous
- **test_misaligned_debug** - Test misaligned halfword store + byte load (test 92 reproduction)
  - Category: Miscellaneous
- **test_misaligned_simple** - Simple misaligned access test
  - Category: Miscellaneous
- **test_mixed_real** - test_mixed_real.s - Real mixed 16-bit and 32-bit instructions
  - Category: Miscellaneous
- **test_mmu_enabled** - Verify MMU is actually enabled and translating
  - Category: MMU/Virtual Memory
- **test_mret_simple** - Simple MRET test
  - Category: Miscellaneous
- **test_mret_trap_simple** - Simple test: MRET in U-mode should trap
  - Category: Miscellaneous
- **test_mret_umode_minimal** - Minimal test: MRET in U-mode should trap
  - Category: Miscellaneous
- **test_mstatus_basic** - Basic mstatus read/write
  - Category: Miscellaneous
- **test_mstatus_csrrw** - MSTATUS CSR Read/Write Test
  - Category: Miscellaneous
- **test_mstatus_direct** - Direct test - write and read mstatus
  - Category: Miscellaneous
- **test_mstatus_interrupt_enables** - Test 2.5: Interrupt Enable Verification
  - Category: Miscellaneous
- **test_mstatus_nested_traps** - Test 2.4: Sequential Trap Handling
  - Category: Miscellaneous
- **test_mstatus_state_mret** - Test 2.1: MRET State Transitions
  - Category: Miscellaneous
- **test_mstatus_state_mret_simple** - Simple test for MRET state transitions
  - Category: Miscellaneous
- **test_mstatus_state_sret** - Test 2.2: SRET State Transitions
  - Category: Miscellaneous
- **test_mstatus_state_trap** - Test 2.3: Trap Entry State Transitions
  - Category: Miscellaneous
- **test_nop** - Minimal NOP test to verify pipeline still works
  - Category: Miscellaneous
- **test_page_fault_invalid** - Page Fault - Invalid Page (V=0)
  - Category: Miscellaneous
- **test_page_fault_smode** - Page Fault in S-mode
  - Category: Miscellaneous
- **test_phase10_2_csr** - Phase 10.2 - Supervisor Mode CSRs
  - Category: Miscellaneous
- **test_phase10_2_delegation** - Phase 10.2 - Trap Delegation to S-mode
  - Category: Miscellaneous
- **test_phase10_2_priv_violation** - Phase 10.2 - CSR Privilege Violation
  - Category: Miscellaneous
- **test_phase10_2_sret** - Phase 10.2 - SRET Instruction
  - Category: Miscellaneous
- **test_phase10_2_transitions** - Phase 10.2 - Privilege Mode Transitions
  - Category: Miscellaneous
- **test_priv_basic** - Test 1: Basic Privilege Mode Testing
  - Category: Privilege Mode
- **test_priv_check** - Check Privilege Mode
  - Category: Privilege Mode
- **test_priv_comprehensive** - Comprehensive Privilege Mode Regression (Phase 7.2)
  - Category: Privilege Mode
- **test_priv_macros_demo** - Privilege Macro Library Demo
  - Category: Privilege Mode
- **test_priv_minimal** - Minimal CSR Test
  - Category: Privilege Mode
- **test_priv_rapid_switching** - Rapid Privilege Mode Switching (Phase 7.1)
  - Category: Privilege Mode
- **test_priv_transitions** - Privilege Mode Transitions
  - Category: Privilege Mode
- **test_raw_hazards** - Test RAW (Read-After-Write) Hazard Handling
  - Category: Miscellaneous
- **test_rv64i_arithmetic** - test_rv64i_arithmetic.s
  - Category: RV64 Specific
- **test_rv64i_basic** - test_rv64i_basic.s
  - Category: RV64 Specific
- **test_rvc_basic** - test_rvc_basic.s - Basic RVC (Compressed) Instruction Test
  - Category: Miscellaneous
- **test_rvc_control** - test_rvc_control.s - RVC Control Flow Test
  - Category: Miscellaneous
- **test_rvc_debug_jump** - Test for debugging JAL to halfword-aligned address
  - Category: Miscellaneous
- **test_rvc_minimal** - test_rvc_minimal.s - Minimal RVC test with only 4-byte aligned compressed instructions
  - Category: Miscellaneous
- **test_rvc_mixed** - test_rvc_mixed.s - Mixed Compressed and Non-Compressed Instructions Test
  - Category: Miscellaneous
- **test_rvc_simple** - test_rvc_simple.s - Simple RVC Integration Test
  - Category: Miscellaneous
- **test_rvc_stack** - test_rvc_stack.s - RVC Stack Operations Test
  - Category: Miscellaneous
- **test_sc_only** - Test SC instruction only (should fail since no prior LR)
  - Category: Miscellaneous
- **test_shifts_debug** - Test program to debug right shift operations
  - Category: Miscellaneous
- **test_simple** - test_simple.s
  - Category: Miscellaneous
- **test_simple_check** - No description available
  - Category: Miscellaneous
- **test_simple_csr** - Simple CSR test - just test one CSR
  - Category: Miscellaneous
- **test_simple_fp_load** - Simple FP Load Test - Matches simple_add pattern
  - Category: Miscellaneous
- **test_simple_raw** - Simple RAW hazard test
  - Category: Miscellaneous
- **test_smode_csr** - Supervisor Mode CSR Read/Write
  - Category: Miscellaneous
- **test_smode_entry** - Test S-mode entry and sstatus read
  - Category: Miscellaneous
- **test_smode_priv_check** - No description available
  - Category: Miscellaneous
- **test_sret** - SRET instruction
  - Category: Miscellaneous
- **test_sret_check_mmode** - Test SRET by checking mstatus from M-mode afterward
  - Category: Miscellaneous
- **test_sret_debug** - No description available
  - Category: Miscellaneous
- **test_sret_debug2** - No description available
  - Category: Miscellaneous
- **test_sret_debug3** - Test SRET SIE/SPIE updates
  - Category: Miscellaneous
- **test_sret_minimal** - Minimal SRET test - just execute SRET and check SPIE
  - Category: Miscellaneous
- **test_sret_mstatus_trace** - No description available
  - Category: Miscellaneous
- **test_sret_no_csr_after** - Test SRET SPIE without any CSR reads after SRET
  - Category: Miscellaneous
- **test_sret_sie_spie** - Test SRET SIE/SPIE handling
  - Category: Miscellaneous
- **test_sret_simple** - Minimal SRET test to debug SIE/SPIE behavior
  - Category: Miscellaneous
- **test_sret_spie_debug** - Minimal test to debug SRET SPIE update issue
  - Category: Miscellaneous
- **test_sret_spie_mem_dump** - Test SRET SPIE with memory dumps for inspection
  - Category: Miscellaneous
- **test_sret_spie_simple** - Ultra-minimal test to debug SRET SPIE update
  - Category: Miscellaneous
- **test_sret_stage2_only** - Test only stage 2 of SRET test
  - Category: Miscellaneous
- **test_stage1_and_2** - Test stages 1 and 2 only
  - Category: Miscellaneous
- **test_stage1_only** - Test stage 1 only: SPIE=0, SIE=1 → SRET → SIE=0, SPIE=1
  - Category: Miscellaneous
- **test_store_load** - Test simple store and load
  - Category: Miscellaneous
- **test_stvec_simple** - Simple STVEC test with NOPs to avoid hazards
  - Category: Miscellaneous
- **test_supervisor_basic** - Basic Supervisor Mode CSR Access and SRET
  - Category: Miscellaneous
- **test_supervisor_complete** - Comprehensive Supervisor Mode Test
  - Category: Miscellaneous
- **test_umode_csr_violation** - test_umode_csr_violation.s
  - Category: Miscellaneous
- **test_umode_ecall** - test_umode_ecall.s
  - Category: Miscellaneous
- **test_umode_entry_from_mmode** - test_umode_entry_from_mmode.s
  - Category: Miscellaneous
- **test_umode_entry_from_smode** - test_umode_entry_from_smode.s
  - Category: Miscellaneous
- **test_umode_illegal_instr** - test_umode_illegal_instr.s
  - Category: Miscellaneous
- **test_vm_identity** - Basic Virtual Memory with Identity Mapping
  - Category: Miscellaneous
- **test_x28_write** - Test writing to x28
  - Category: Miscellaneous
- **test_xret_privilege_trap** - test_xret_privilege_trap.s
  - Category: Miscellaneous

---

## Official Compliance Tests

Official RISC-V compliance tests from riscv-tests repository.

### RV32I Base Integer (42 tests)
- rv32ui-p-add, addi, and, andi, auipc
- rv32ui-p-beq, bge, bgeu, blt, bltu, bne
- rv32ui-p-fence_i
- rv32ui-p-jal, jalr
- rv32ui-p-lb, lbu, ld_st, lh, lhu, lui, lw
- rv32ui-p-ma_data
- rv32ui-p-or, ori
- rv32ui-p-sb, sh, simple, sll, slli
- rv32ui-p-slt, slti, sltiu, sltu
- rv32ui-p-sra, srai, srl, srli, st_ld
- rv32ui-p-sub, sw
- rv32ui-p-xor, xori

### RV32M Multiply/Divide (8 tests)
- rv32um-p-div, divu
- rv32um-p-mul, mulh, mulhsu, mulhu
- rv32um-p-rem, remu

### RV32A Atomic Operations (10 tests)
- rv32ua-p-amoadd_w, amoand_w
- rv32ua-p-amomax_w, amomaxu_w
- rv32ua-p-amomin_w, amominu_w
- rv32ua-p-amoor_w, amoswap_w, amoxor_w
- rv32ua-p-lrsc

### RV32F Single-Precision FP (11 tests)
- rv32uf-p-fadd, fclass, fcmp, fcvt, fcvt_w
- rv32uf-p-fdiv, fmadd, fmin
- rv32uf-p-ldst, move, recoding

### RV32D Double-Precision FP (9 tests)
- rv32ud-p-fadd, fclass, fcmp, fcvt, fcvt_w
- rv32ud-p-fdiv, fmadd, fmin, ldst

### RV32C Compressed Instructions (1 test)
- rv32uc-p-rvc


---

## Test Statistics

### Custom Test Breakdown
| Category | Count |
|----------|-------|
| RV32I Base | 0 |
| M Extension | 10 |
| A Extension | 8 |
| F Extension | 26 |
| D Extension | 0 |
| C Extension | 0 |
| CSR/Privilege | 9 |
| Edge Cases | 6 |
| **Total Custom** | **186** |

### Hex File Status
- Assembly files (.s): 186
- Hex files (.hex): 178
- Missing hex files: 8

### Overall Summary
- **Custom Tests**: 186
- **Official Tests**: 81
- **Total Tests**: 267
- **Compliance**: 100% (81/81 official tests passing) ✅

---

## Usage

### Running Tests

**Individual test**:
```bash
env XLEN=32 ./tools/test_pipelined.sh <test_name>
```

**All custom tests**:
```bash
make test-custom-all
```

**Official tests**:
```bash
env XLEN=32 ./tools/run_official_tests.sh all
```

**By extension**:
```bash
make test-m    # M extension
make test-f    # F extension
make test-d    # D extension
```

### Regenerating This Catalog

```bash
./tools/generate_test_catalog.sh > docs/TEST_CATALOG.md
```

---

**Last Generated**: Sun Oct 26 20:35:48 PDT 2025
**Generator**: tools/generate_test_catalog.sh
