# Known Issues

This document tracks known bugs and limitations in the RV32IMAFDC implementation.

## Active Issues

None! All critical issues have been resolved as of 2025-10-26 Session 7. ✅

---

## Resolved Issues

### 1. Synchronous Pipeline Trap Latency - test_delegation_disable (RESOLVED 2025-10-26)

**Status**: FIXED ✅ via Writeback Gating (Session 7)
**Priority**: HIGH - Was blocking Phase 6 privilege mode tests
**Affected**: `test_delegation_disable` (instruction after exception was corrupting registers)

#### Description

The `test_delegation_disable` test fails due to an inherent **1-cycle trap latency** in the synchronous pipeline design. When an exception occurs (e.g., ECALL), the instruction immediately following it in the pipeline may execute before the pipeline flush completes, causing unintended side effects.

**Root Cause - Synchronous Pipeline Limitation:**

The pipeline uses synchronous (registered) stage transitions, which creates a fundamental timing issue:

1. **Cycle N**: ECALL in IDEX stage
   - Exception detected: `exception_gated=1`, `trap_flush=1`
   - `flush_idex=1` asserted (combinational)
   - PC updates to trap vector (combinational)
   - But next instruction (`li s0, 7`) already in IFID register from previous cycle

2. **Cycle N (same cycle, later in combinational evaluation)**:
   - IFID instruction advances to IDEX on rising clock edge
   - Instruction `li s0, 7` executes and writes to register file

3. **Cycle N+1**: Flush takes effect
   - IDEX flushed to NOP
   - But `s0` was already corrupted by the `li s0, 7` instruction

**Symptoms:**
- S-mode handler sets `s0=5` before ECALL
- Instruction after ECALL (`li s0, 7`) executes before trap flush
- M-mode handler sees `s0=7` instead of `s0=5`
- Test fails because handler logic depends on preserved `s0` value

**Evidence:**
```
[EXC] Time=0 ECALL: PC=0x0000011c cause=9  # ECALL instruction
[EXC] Time=0 ECALL: PC=0x00000120 cause=9  # Next instruction (li s0, 7) incorrectly flagged
```

**Failing Tests:**
- `test_delegation_disable` - M-mode handler receives corrupted `s0=7` instead of `s0=5`

**Passing Tests:**
- 14/14 quick regression tests ✅
- 81/81 official RISC-V compliance tests ✅
- `test_delegation_to_current_mode` ✅
- `test_umode_entry_from_mmode` ✅
- `test_umode_entry_from_smode` ✅
- 22/34 privilege mode tests ✅

#### Architectural Analysis

**Why Synchronous Flush Fails:**

Pipeline stage registers update on clock edges with priority:
```verilog
always @(posedge clk) begin
  if (flush)
    valid_out <= 0;  // Insert NOP
  else
    valid_out <= valid_in;  // Advance instruction
end
```

Within a single clock cycle:
- Rising edge: Instruction advances from IFID → IDEX
- Combinational: Exception detected, flush asserted
- Next rising edge: Flush takes effect (too late!)

**Attempted Fixes (Session 6):**

1. ✅ **0-Cycle Trap Latency** (`rv32i_core_pipelined.v:565,1567`)
   - Changed `trap_flush = exception_r` → `trap_flush = exception_gated`
   - Changed CSR trap inputs from registered to immediate signals
   - Uses current exception info for immediate trap
   - **Result**: Improved trap timing, but doesn't prevent next instruction from advancing

2. ❌ **Combinational Valid Gating** (attempted, reverted)
   - Tried: `idex_valid_gated = idex_valid && !flush_idex`
   - **Problem**: Creates combinational loop:
     - `exception` → `trap_flush` → `flush_idex` → `idex_valid_gated` → `exception` (oscillation!)
   - **Result**: Simulation hangs, all tests timeout

**Why It's Hard to Fix:**

The fundamental issue is that **exception detection** and **pipeline advancement** both happen on the same clock edge, and advancement happens first (it's the normal clocked behavior). To truly fix this requires:

1. **Asynchronous flush** - Make pipeline registers reset immediately (not recommended - timing issues)
2. **Bypass/gating logic** - Prevent flushed instructions from having side effects (complex)
3. **Pipeline redesign** - Separate exception detection from instruction advancement (major refactor)

#### Solution (Session 7)

**Writeback Gating** - Prevent flushed instructions from committing register writes:

```verilog
// Integer register file (rv32i_core_pipelined.v:853-856)
wire int_reg_write_enable = (memwb_reg_write | memwb_int_reg_write_fp) && memwb_valid;

// FP register file (rv32i_core_pipelined.v:937-938)
wire fp_reg_write_enable = memwb_fp_reg_write && memwb_valid;
```

**How it works:**
- Instructions that cause exceptions are invalidated via `memwb_valid=0`
- Register write enables check `memwb_valid` before committing
- Flushed instructions cannot corrupt architectural state
- Preserves 0-cycle trap latency from Session 6

**Previous Fixes (Sessions 4-6):**
- Session 6: 0-cycle trap latency using `exception_gated`
- Session 5: CSR write exception gating
- Session 4: Exception propagation gating, trap target computation

#### Test Results

**Before Session 7:**
- `test_delegation_disable`: ❌ FAILED (register s0 corrupted)
- Quick regression: 14/14 ✅
- Compliance: 79/79 ✅

**After Session 7:**
- `test_delegation_disable`: ✅ PASSED
- Quick regression: 14/14 ✅
- Compliance: 79/79 ✅
- **Phase 6: 4/4 tests passing (100%)** ✅

---

## Resolved Issues

### 1. Privilege Mode Forwarding Bug (RESOLVED 2025-10-26)

**Status**: FIXED ✅
**Priority**: HIGH - Was blocking Phase 6 privilege mode tests
**Affected**: Pipelined core privilege mode transitions

#### Description

When `MRET` or `SRET` executes and changes the privilege mode, the next instruction may evaluate CSR access permissions using the OLD privilege mode instead of the NEW one, causing incorrect exception delegation behavior.

#### Root Cause

Pipeline hazard in privilege mode updates:

1. `MRET`/`SRET` reaches MEM stage and updates `current_priv` register
2. Next instruction already in IF/ID/EX stages uses OLD `current_priv` for CSR checks
3. CSR illegal instruction exceptions use wrong privilege mode for delegation decisions

**Example Timeline:**
```
Cycle 34: MRET in MEM stage → current_priv = 11→01 (M→S)
          Next instruction at EX stage checks CSR access with curr_priv=11 (stale!)
          Exception delegation fails: medeleg[2]=1 but curr_priv=11 → trap to M-mode
```

#### Evidence

From `test_delegation_to_current_mode` debug output:
```
[PRIV] MRET: priv 11 -> 01 (from MPP) mepc=0x00000070
[CSR_DELEG] get_trap_target_priv: cause=2 curr_priv=11 medeleg=00000004 medeleg[cause]=1
[CSR_DELEG] -> M-mode (curr_priv==M)
```

Even with delegation enabled (`medeleg[2]=1`), the check sees `curr_priv=11` (M-mode), so per RISC-V spec "M-mode traps never delegate," the exception goes to M-mode instead of delegating to S-mode.

#### Impact

**Failing Tests:**
- `test_delegation_to_current_mode` - Phase 6
- `test_delegation_disable` - Phase 6
- Any test with immediate CSR access after MRET/SRET

**Passing Tests:**
- `test_umode_entry_from_mmode` - Works because next instruction is NOT a privileged CSR access
- Basic privilege transitions without CSR access work correctly

**Compliance:**
- 81/81 official RISC-V tests still PASS (they don't test this edge case)
- 19/34 privilege mode tests PASS (those not affected by this bug)

#### Solution Implemented

**1. Privilege Mode Forwarding** (`rv32i_core_pipelined.v:1839-1885`):
```verilog
// Compute new privilege mode from MRET/SRET in MEM stage
wire [1:0] mret_new_priv = mpp;
wire [1:0] sret_new_priv = {1'b0, spp};

// Forward privilege mode when MRET/SRET is in MEM stage
wire forward_priv_mode = (exmem_is_mret || exmem_is_sret) && exmem_valid && !exception;

// Effective privilege mode for EX stage
wire [1:0] effective_priv = forward_priv_mode ?
                            (exmem_is_mret ? mret_new_priv : sret_new_priv) :
                            current_priv;
```

**2. Exception Latching** (`rv32i_core_pipelined.v:447-481`):
- Latch `exception_target_priv_r` when exception first occurs
- Prevents combinational feedback loop (exception → trap_flush → current_priv → trap_target_priv)

**3. Delayed Trap Flush** (`rv32i_core_pipelined.v:522`):
```verilog
// Use registered exception to break feedback loop
assign trap_flush = exception_r && !exception_r_hold;
```

**4. CSR File Updates** (`csr_file.v:46-47, 602`):
- Added `actual_priv` input for trap delegation
- Separated CSR privilege checks (uses `effective_priv`) from trap delegation (uses `actual_priv`)

**Files Modified:**
- `rtl/core/rv32i_core_pipelined.v` - Privilege forwarding, exception latching
- `rtl/core/csr_file.v` - Dual privilege inputs

#### References

- RISC-V Privileged Spec v1.12 Section 3.1.6.1 (Privilege and Global Interrupt-Enable Stack)
- Issue discovered during Phase 6 implementation (Delegation Edge Cases)
- Debug trace: `docs/debug/privilege_forwarding_trace_2025-10-26.log` (if saved)

### 2. Test Infrastructure - Hex File Management (RESOLVED 2025-10-26)

**Status**: FIXED ✅ via Auto-Rebuild (Session 7)
**Priority**: HIGH - Caused frequent workflow disruptions
**Affected**: All custom tests, especially after git operations

#### Description

Hex files were build artifacts (not tracked in git), causing frequent "hex file not found" errors:
- Git operations (`checkout`, `pull`, etc.) deleted untracked hex files
- No staleness detection - stale hex caused mysterious test failures
- Manual rebuild workflow was error-prone
- 184 .s files but only 121 .hex files (63 missing)

#### Solution (Session 7)

**Auto-Rebuild in Test Runner** (`tools/test_pipelined.sh`):
- Automatically rebuilds missing hex files from source
- Timestamp-based staleness detection (source newer than hex)
- Graceful error messages for unbuildable tests

**Smart Batch Rebuild** (`Makefile`):
- `make rebuild-hex` - Only rebuilds changed/missing files
- `make rebuild-hex-force` - Force rebuild all
- Shows statistics: rebuilt/skipped/failed counts

#### Impact

**Before:**
- Tests failed after `git checkout` with "hex file not found"
- Manual `make rebuild-hex` needed frequently
- Stale hex files caused confusing test failures

**After:**
- Tests "just work" regardless of git state ✅
- Auto-rebuild only when needed (fast) ✅
- Clear error messages when tests can't be built ✅

---

## Future Enhancements

1. **Phase 7 Tests**: Implement stress and regression tests (2 pending)
2. **Interrupt Logic**: Complete Phase 3 tests (3 tests need interrupt hardware)
3. **Exception Coverage**: Complete Phase 4 tests (hardware limitations documented)
4. **Documentation**: Waveform examples for privilege mode state machine
