# Known Issues

This document tracks known bugs and limitations in the RV32IMAFDC implementation.

## Active Issues

### FENCE.I Self-Modifying Code Support (Medium Priority)

**Status**: 🐛 FAILING (Pre-existing since Session 33)
**Severity**: Medium
**Test**: `rv32ui-p-fence_i` (official compliance test)
**Introduced**: Session 33 (IMEM Bus Access changes)
**Compliance Impact**: 80/81 passing (98.8%)

**Description**:
The FENCE.I instruction synchronizes instruction and data caches after self-modifying code. The official test writes new instructions to memory and executes them after FENCE.I.

**Current Behavior**:
Test fails at test #5 with `gp=0x5`, indicating the fifth test case is not working correctly.

**Root Cause** (Hypothesis):
Likely related to Session 33's IMEM bus access changes:
- Session 33 added IMEM as read-only slave on bus for .rodata access
- IMEM writes via stores may not properly route to instruction memory
- Write path may be affected by Harvard architecture modifications

**Investigation Status**:
- Session 34/35 write pulse changes did NOT cause this (verified via git bisect)
- Test was passing before Session 33 changes
- IMEM write enable logic exists but may not work with bus architecture

**Workaround**:
None. Self-modifying code is rare in modern RISC-V software. Most use cases:
- JIT compilers (not typical in embedded systems)
- Dynamic code patching (uncommon)
- Boot loaders (can work around limitation)

**Impact Assessment**:
- **FreeRTOS**: ✅ Not affected (doesn't use self-modifying code)
- **Linux**: ✅ Not affected (uses proper I/D cache management)
- **Compliance**: 98.8% (80/81 tests passing)
- **Real-world**: Low impact (self-modifying code rarely used)

**Fix Priority**: Medium
- Not blocking FreeRTOS or OS integration work
- Should be fixed before claiming "full RV32I compliance"
- Low real-world impact

**Estimated Effort**: 2-4 hours
- Debug IMEM write path in Session 33 bus integration
- Verify store-to-IMEM routing through bus interconnect
- Test with fence_i compliance test

---

## Recent Fixes

### Session 36: IMEM Byte-Select for String Access (RESOLVED 2025-10-28)

**Status**: FIXED ✅
**Severity**: Critical
**Impact**: All string constant access from IMEM (.text section)

**Problem**:
FreeRTOS text output corrupted - every other character missing:
- Expected: "Tasks created successfully!"
- Actual: "Tscetdscesul!" (2-byte stride issue)
- String literals stored in .text (IMEM) instead of .rodata

**Root Cause**:
`instruction_memory` module forces halfword alignment for RVC compressed instruction support:
```verilog
wire [XLEN-1:0] halfword_addr = {masked_addr[XLEN-1:1], 1'b0};  // Drops LSB!
```

This breaks byte-level loads (LB/LBU):
- Address 0x4241 → aligned to 0x4240 → returns byte at offset 0 (WRONG!)
- Result: Every odd byte address returns wrong data

**Solution**:
Added byte-select logic in SoC IMEM adapter (`rtl/rv_soc.v:299-333`):
```verilog
wire [7:0] imem_byte_select;
assign imem_byte_select = (imem_req_addr[1:0] == 2'b00) ? imem_data_port_instruction[7:0] :
                          (imem_req_addr[1:0] == 2'b01) ? imem_data_port_instruction[15:8] :
                          (imem_req_addr[1:0] == 2'b10) ? imem_data_port_instruction[23:16] :
                                                           imem_data_port_instruction[31:24];
```

**Verification**:
- Quick regression: 14/14 PASSED ✅
- FreeRTOS strings: Fully readable ✅
- Output: "FATAL: Malloc failed!", "Scheduler returned!", etc.

**Files Modified**: `rtl/rv_soc.v` (lines 299-333 - added byte-select logic)
**Reference**: `docs/SESSION_36_IMEM_BYTE_SELECT_FIX.md`

---

### Session 35: Atomic Operations Write Pulse Exception (RESOLVED 2025-10-27)

**Status**: FIXED ✅
**Severity**: Critical
**Impact**: All atomic operations (LR/SC, AMO)

**Problem**:
Session 34's write pulse optimization broke atomic operations:
- `rv32ua-p-amoswap_w`: FAILED at test #7
- `rv32ua-p-lrsc`: TIMEOUT
- Quick regression: 12/14 (down from 14/14)

**Root Cause**:
One-shot write pulse logic prevented multi-cycle atomic read-modify-write sequences:
- Atomic ops stay in MEM stage for multiple cycles (same PC)
- Write pulse only triggered on FIRST cycle (`mem_stage_new_instr`)
- Subsequent atomic writes blocked → operations incomplete

**Solution**:
Added exception for atomic operations in write pulse logic:
```verilog
wire arb_mem_write_pulse = mmu_ptw_req_valid ? 1'b0 :
                           ex_atomic_busy ? dmem_mem_write :           // Atomic: level signal
                           (dmem_mem_write && mem_stage_new_instr);    // Normal: one-shot pulse
```

**Verification**:
- Quick regression: 14/14 PASSED ✅
- Atomic suite: 10/10 PASSED ✅
- FreeRTOS UART: Clean output, no duplication ✅

**Files Modified**: `rtl/core/rv32i_core_pipelined.v` (lines 2403-2405)
**Reference**: `docs/SESSION_35_ATOMIC_FIX.md`

---

## Previous Resolved Issues

### Session 34: UART Character Duplication (RESOLVED 2025-10-27)

**Status**: FIXED ✅
**Severity**: Critical
**Impact**: All memory-mapped I/O writes (UART, GPIO, timers, etc.)

**Problem**: Every UART character transmitted exactly twice, 2 cycles apart
**Root Cause**: Bus write requests were level signals → duplicate writes when MEM stage held
**Solution**: Convert writes to one-shot pulses (with atomic exception in Session 35)
**Reference**: `docs/SESSION_34_UART_DUPLICATION_FIX.md`

---

### Session 30: IMEM Corruption Bug (RESOLVED 2025-10-27)

---

## Resolved Issues

### 1. IMEM Corruption Bug - Unified Memory Architecture (RESOLVED 2025-10-27)

**Status**: FIXED ✅ (Session 30)
**Priority**: CRITICAL - Blocked FreeRTOS execution
**Affected**: All programs using DMEM (virtually everything)

#### Description

Instruction memory was being corrupted during runtime, causing illegal instruction exceptions. Stores to data memory addresses were also writing to instruction memory at the same indices.

**Symptoms**:
- IMEM[0x210c] initialized correctly as 0x27068693 (ADDI a3,a3,624)
- Runtime fetch returned 0x00000000 (NOP) causing illegal instruction exception
- Corruption happened at cycles 292, 367, 441, 561 (during execution, not initialization)
- Values written: 0x22d2, 0x22e2, 0x22ee, 0x0000 (code addresses from data writes)

#### Root Cause

**Two-part architectural bug:**

1. **DMEM loaded from same hex file as IMEM** (`rtl/rv_soc.v:260`)
   - Both memories initialized with identical data
   - BSS section in DMEM overlapped code in IMEM at same indices
   - Example: IMEM[0x210c] = 0x93 (code), DMEM[0x210c] = 0x93 (same initial data)

2. **ALL stores wrote to BOTH DMEM and IMEM** (`rtl/core/rv32i_core_pipelined.v:681`)
   - FENCE.I self-modifying code support connected ALL stores to IMEM
   - No address filtering on IMEM write port
   - Store to DMEM 0x8000210c → address masked to 0x210c → corrupted IMEM[0x210c]

#### Solution

**Fix #1**: Don't load DMEM from hex file
```verilog
// rtl/rv_soc.v line 260
dmem_bus_adapter #(
  .MEM_FILE("")  // DMEM should NOT be loaded from hex file
) dmem_adapter (...);
```

**Fix #2**: Add address filtering for IMEM writes
```verilog
// rtl/core/rv32i_core_pipelined.v line 674
wire imem_write_enable = exmem_mem_write && exmem_valid && !exception &&
                         (exmem_alu_result < IMEM_SIZE);  // Only IMEM range!
```

**Files Modified**:
- `rtl/rv_soc.v` - Removed MEM_FILE from DMEM
- `rtl/core/rv32i_core_pipelined.v` - Added IMEM write address filter

#### Impact

**Critical bug affecting:**
- All programs using DMEM (BSS, data, stack, heap)
- Harvard architecture memory isolation
- Code integrity during execution
- FENCE.I self-modifying code (now properly restricted to IMEM range)

**Without fix:**
- FreeRTOS cannot execute past address 0x210c
- Any DMEM store with low 16 bits matching code addresses corrupts IMEM
- Silent memory corruption hard to debug

**With fix:**
- IMEM protected from DMEM stores ✅
- FreeRTOS boots correctly ✅
- Quick regression: 14/14 passing ✅
- Harvard architecture isolation restored ✅

#### Verification

**Before fix:**
```
[IMEM-OVERWRITE] Cycle 292: mem[0x210c] = 0xd2  ❌
[IMEM-OVERWRITE] Cycle 367: mem[0x210c] = 0xe2  ❌
[IMEM-OVERWRITE] Cycle 441: mem[0x210c] = 0xee  ❌
[IMEM-OVERWRITE] Cycle 561: mem[0x210c] = 0x00  ❌
[IMEM-FETCH] addr=0x210c, instr=0x00000000  ❌
```

**After fix:**
```
[IMEM-FETCH] addr=0x210c, instr=0x27068693  ✅
  mem[0x210c]=0x93, mem[0x210d]=0x86, mem[0x210e]=0x06, mem[0x210f]=0x27
FreeRTOS executes past 0x210c without exceptions  ✅
```

**Reference**: `docs/SESSION_30_IMEM_BUG_FIX.md`

---

### 2. FreeRTOS Illegal Instruction Exceptions (RESOLVED 2025-10-27)

**Status**: ROOT CAUSE IDENTIFIED AND FIXED ✅ (Sessions 28-30)
**Priority**: CRITICAL - Was blocking FreeRTOS execution
**Affected**: FreeRTOS boot process, trap handler

#### Description

FreeRTOS encountered illegal instruction exceptions at addresses 0x210c, 0x2548, etc. Only 1 UART character transmitted instead of full banner.

#### Root Causes

**Three separate bugs:**

1. **Session 28**: RVC decoder missing compressed FP instructions (C.FLDSP/C.FSDSP)
2. **Session 29**: IMEM read bug investigation - identified memory corruption
3. **Session 30**: IMEM corruption bug - stores to DMEM corrupting IMEM

**Final fix**: Session 30 unified memory architecture fixes (see above)

**References**:
- `docs/SESSION_28_RVC_FP_DECODER.md`
- `docs/SESSION_29_IMEM_BUG_INVESTIGATION.md`
- `docs/SESSION_30_IMEM_BUG_FIX.md`

---

## Resolved Issues (Continued)

### 1. WB→ID Forwarding Not Gating on memwb_valid (RESOLVED 2025-10-27)

**Status**: FIXED ✅ (Session 27)
**Priority**: CRITICAL - Correctness bug affecting all programs
**Affected**: Any instruction with RAW hazard to flushed instruction

#### Description

The forwarding unit forwarded data from WB stage without checking if the instruction was valid (not flushed), causing stale/invalid data from flushed instructions to be forwarded to ID stage.

**Root Cause**:
- Register file writes gated by `memwb_valid` (line 880 of `rv32i_core_pipelined.v`)
- Forwarding unit only checked `memwb_reg_write`, NOT `memwb_valid`
- Result: Could forward garbage data from flushed instructions

**Symptoms**:
- Return address (ra) corruption: JAL writes 0x22ac, but SW saves 0x0
- Stack operations failed intermittently
- Random register data corruption

**Solution**:
- Added `memwb_valid` input to forwarding unit
- Gated all 10 WB forwarding paths with `&& memwb_valid`
- Locations: ID/EX stage integer/FP forwarding (lines 106, 127, 156, 184, 217, 236, 255, 276, 291, 306)

**Files Modified**:
- `rtl/core/forwarding_unit.v` (10 changes)
- `rtl/core/rv32i_core_pipelined.v` (1 change - wiring)

**Impact**: Affects any program that has exceptions, interrupts, or branch mispredictions that flush pipeline stages.

**Reference**: `docs/SESSION_27_CRITICAL_BUG_FIXES.md`

### 2. DMEM Address Decode Limited to 64KB (RESOLVED 2025-10-27)

**Status**: FIXED ✅ (Session 27)
**Priority**: CRITICAL - Prevents use of >64KB memory
**Affected**: Any program using >64KB of DMEM

#### Description

Bus interconnect DMEM address mask was configured for 64KB range (`0xFFFF_0000`), but FreeRTOS uses 1MB of DMEM. Any stack or heap access beyond 64KB would fail address decode, causing writes/reads to go nowhere.

**Root Cause**:
- `DMEM_MASK = 0xFFFF_0000` in `simple_bus.v` (line 92)
- Address decode: `(addr & MASK) == BASE`
- Example: `0x800c_212c & 0xFFFF_0000 = 0x800c_0000 != 0x8000_0000` → No match!

**Symptoms**:
- Memory writes appeared to execute but data was lost
- Memory reads returned 0x0 instead of written values
- Stack beyond 64KB failed (FreeRTOS stack at ~770KB)
- Heap allocations beyond 64KB failed silently

**Solution**:
- Changed `DMEM_MASK` from `0xFFFF_0000` (64KB) to `0xFFF0_0000` (1MB)
- Address decode now works: `0x800c_212c & 0xFFF0_0000 = 0x8000_0000` ✅

**Files Modified**:
- `rtl/interconnect/simple_bus.v` (1 change)

**Impact**: Prevents any program from using more than 64KB of memory. FreeRTOS requires ~1MB for heap/stack/BSS.

**Verification**: Memory operations now work correctly - write 0x22ac to 0x800c212c, read 0x22ac back (was 0x0 before fix).

**Reference**: `docs/SESSION_27_CRITICAL_BUG_FIXES.md`

### 3. Synchronous Pipeline Trap Latency - test_delegation_disable (RESOLVED 2025-10-26)

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

1. **Phase 3 Tests**: Interrupt handling tests (3 tests need interrupt injection capability)
2. **Phase 4 Tests**: Exception coverage (6 tests pending, some blocked by hardware limitations)
3. **Documentation**: Waveform examples for privilege mode state machine
4. **Performance**: Consider branch prediction, caching optimizations
