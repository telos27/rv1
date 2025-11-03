# Session 77: MEPC Interrupt Bug - Root Cause Identified

**Date**: 2025-11-01
**Status**: 🔍 **BUG IDENTIFIED** - MEPC saves wrong PC value on interrupts
**Impact**: Critical bug affecting interrupt handling - incorrect return address

---

## Problem Statement

Following up on Session 76's finding that timer interrupts weren't working correctly in `tb_soc.v`, this session investigated why MEPC (Machine Exception PC) was being saved as 0x00000000 instead of the correct interrupted PC address.

Session 76 concluded the issue was a "test infrastructure bug" but couldn't identify the specific cause.

---

## Investigation Process

### 1. Initial Analysis (Session 76 Review)

**Session 76 Observations**:
- Timer interrupt fired at cycle 114
- MEPC saved as 0x00000000 (incorrect)
- MTVEC = 0x80000038 (correct - trap_handler address)
- Concluded: "initialization code never executed"

**Session 77 Hypothesis**:
- If MTVEC is correct, initialization DID execute
- Need to trace PC from cycle 0 to understand actual execution flow

### 2. PC Trace Implementation

**Added Debug Infrastructure** (`rtl/core/rv32i_core_pipelined.v:2918-2938`):
```verilog
`ifdef DEBUG_PC_TRACE
integer pc_trace_cycle;
initial pc_trace_cycle = 0;

always @(posedge clk) begin
  if (!reset_n) begin
    pc_trace_cycle = 0;
    $display("[PC_TRACE] RESET ASSERTED");
  end else begin
    pc_trace_cycle = pc_trace_cycle + 1;
    if (pc_trace_cycle <= 150) begin
      $display("[PC_TRACE] cycle=%0d PC=0x%08h instr=0x%08h valid=%b stall=%b",
               pc_trace_cycle, pc_current, if_instruction, ifid_valid, stall_pc);
    end
  end
end
`endif
```

**Updated** `tools/test_soc.sh` to support `DEBUG_PC_TRACE` flag.

### 3. PC Trace Results (Cycles 1-125)

**Key Findings from Trace**:

```
cycle=1:  PC=0x80000000 (auipc t0, 0x0)          - _start: Setup MTVEC
cycle=2:  PC=0x80000004 (addi  t0, t0, 56)       - Calculate trap_handler addr
cycle=3:  PC=0x80000008 (csrw  mtvec, t0)        - Write MTVEC = 0x80000038 ✓
cycle=5:  PC=0x8000000e (csrs  mstatus, t0)      - Enable interrupts (MIE)
cycle=8:  PC=0x80000016 (csrw  mie, t0)          - Enable timer interrupt
cycle=12: PC=0x80000020 (lw    t1, 0(t0))        - Read MTIME
cycle=13: PC=0x80000024 (addi  t1, t1, 100)      - Program MTIMECMP
cycle=17: PC=0x8000002c (sw    t1, 0(t0))        - Write MTIMECMP
cycle=19: PC=0x80000034 (li    a0, 0)            - Initialize success flag
cycle=20: PC=0x80000036 (j     0x80000036)       - wait_loop: infinite jump
```

**Wait Loop Behavior** (cycles 20-114):
```
cycle=20: PC=0x80000036 (j 0x80000036) valid=1 stall=1
cycle=21: PC=0x80000036 (j 0x80000036) valid=1 stall=0
cycle=22: PC=0x80000038 (li a0, 1)     valid=1 stall=0  <- Prefetch!
cycle=23: PC=0x8000003a (lui t0, ...)  valid=1 stall=0
cycle=24: PC=0x80000036 (j 0x80000036) valid=0 stall=0  <- Back to loop
```

**Critical Discovery**: The CPU **speculatively prefetches** ahead while executing the tight loop!
- PC=0x80000036: wait_loop (2-byte compressed jump)
- PC=0x80000038: trap_handler (fetched but NOT executed)
- Loop repeats every 3 cycles

**Initialization Was Successful!**:
- All CSRs properly configured ✓
- MTVEC = 0x80000038 ✓
- MSTATUS.MIE = 1 ✓
- MIE.MTIE = 1 ✓
- MTIMECMP programmed ✓

Session 76's conclusion was **incorrect** - initialization code executed perfectly!

### 4. Interrupt Behavior at Cycle 114

**Observed Sequence**:
```
[PC_TRACE] cycle=114 PC=0x80000036 instr=0x0000006f valid=0 stall=0
[INTR_IN]  cycle=114 mtip_in=1 msip_in=0 meip_in=0 seip_in=0
[TRAP]     cycle=114 exception_gated=1 PC=80000038 trap_vector=80000038 mepc=00000000
[PC_TRACE] cycle=115 PC=0x80000038 instr=0x00100513 valid=1 stall=0
[TRAP_PC]  cycle=115 exception_taken PC=80000038 mepc=80000038
```

**Discrepancy Identified**:
- PC_TRACE shows: `cycle=114 PC=0x80000036` (wait_loop - correct!)
- TRAP debug shows: `cycle=114 PC=80000038` (trap_handler - wrong!)
- MEPC saved as: 0x00000000 at cycle 114, then 0x80000038 at cycle 115

**Debug Timing Issue**:
- PC_TRACE uses `always @(posedge clk)` - samples BEFORE clock edge
- TRAP debug uses `always @(posedge clk)` - samples AFTER clock edge
- Both should sample at same time, but see different values!

**Explanation**: The TRAP debug block samples `pc_current` AFTER it has been updated to `trap_vector`!

### 5. Root Cause Analysis

**The Bug** (`rtl/core/rv32i_core_pipelined.v:1915`):
```verilog
assign exception_pc = sync_exception ? sync_exception_pc : pc_current;
```

**Problem**: `exception_pc` is **combinational**, assigned from `pc_current`.

**Timing Issue**:
1. Cycle 114: `interrupt_pending=1`, `exception_gated=1` detected
2. Cycle 114: `trap_flush=1` → `pc_next = trap_vector` (0x80000038)
3. Cycle 114: `exception_pc = pc_current` sampled
4. **Cycle 114→115 edge**: `pc_current` updates to 0x80000038 (trap_vector)
5. **Cycle 114→115 edge**: CSR writes `exception_pc` to MEPC
6. Cycle 115: MEPC = 0x80000038 (WRONG! Should be 0x80000036)

**The Race Condition**:
- `exception_pc` is assigned combinationally from `pc_current`
- `pc_current` updates on the same clock edge that MEPC is written
- Depending on Verilog evaluation order, `exception_pc` may sample the OLD or NEW `pc_current`

**Why MEPC=0x00000000 at first**:
- First interrupt at cycle 114
- MEPC was never written before (initialized to 0)
- Debug reads MEPC BEFORE the CSR write completes
- Next cycle (115), MEPC has been written with the wrong value (0x80000038)

**Enhanced Debug Output**:
Added `exception_pc` to TRAP debug (line 1844):
```
[TRAP] cycle=114 exception_gated=1 PC=80000038 trap_vector=80000038 mepc=00000000 exception_pc=80000038
```

Confirms: `exception_pc` is getting 0x80000038 instead of 0x80000036!

---

## Root Cause Summary

**Bug**: MEPC saves wrong PC on interrupts due to combinational assignment race condition

**Location**: `rtl/core/rv32i_core_pipelined.v:1915`

**Mechanism**:
1. Interrupt detected → `pc_next` set to `trap_vector`
2. `exception_pc = pc_current` evaluated combinationally
3. `pc_current` and MEPC both update on same clock edge
4. Race condition: `exception_pc` may sample new `pc_current` value
5. MEPC gets saved with `trap_vector` instead of interrupted PC

**Impact**:
- Interrupts save wrong return address (trap_vector instead of interrupted PC)
- MRET returns to trap_vector, not interrupted instruction
- Causes infinite trap loop (interrupt fires again immediately)
- Affects ALL interrupt types (timer, software, external)

---

## Fix Strategy (For Session 78)

### Option 1: Register exception_pc (Preferred)

Sample `pc_current` BEFORE trap occurs:

```verilog
// Register exception_pc one cycle early
reg [XLEN-1:0] exception_pc_pre;
always @(posedge clk) begin
  if (exception_gated && !exception_taken_r) begin
    exception_pc_pre <= pc_current;
  end
end

// Use registered value for CSR
assign exception_pc = exception_pc_pre;
```

**Pros**: Clean, explicit timing
**Cons**: Adds one register

### Option 2: Use pipeline stage PC

Use PC from a specific pipeline stage that hasn't been flushed yet:

```verilog
assign exception_pc = sync_exception ? sync_exception_pc : ifid_pc;
```

**Pros**: No additional registers
**Cons**: May not handle all edge cases correctly

### Option 3: Save PC before trap_flush

Modify PC update logic to preserve old PC:

```verilog
reg [XLEN-1:0] pc_save;
always @(posedge clk) begin
  if (trap_flush) begin
    pc_save <= pc_current;  // Save before jump
  end
end

assign exception_pc = sync_exception ? sync_exception_pc : pc_save;
```

**Recommendation**: **Option 1** - Most explicit and correct

---

## Verification Plan

### 1. Unit Test
Create minimal interrupt test that checks MEPC value:
```assembly
_start:
    # Setup interrupts
    la t0, trap_handler
    csrw mtvec, t0

    # Enable timer interrupt (short delay)
    li t0, 100
    # Write MTIMECMP...

wait:
    li a0, 0xDEADBEEF  # Marker PC
    j wait             # Loop here

trap_handler:
    csrr t0, mepc      # Read saved PC
    li t1, 0xDEADBEEF  # Expected PC (wait loop)
    bne t0, t1, fail
    # Clear interrupt, return
    mret

fail:
    li a0, 0xBADBAD
    ebreak
```

### 2. Regression Tests
- Re-run all 14 quick regression tests
- Verify no regressions from fix

### 3. FreeRTOS Test
- Test timer interrupts with FreeRTOS
- Verify scheduler works correctly
- Check task switching after fix

---

## Files Modified (Session 77)

### Debug Infrastructure
1. **rtl/core/rv32i_core_pipelined.v**:
   - Added `DEBUG_PC_TRACE` block (lines 2918-2938)
   - Enhanced TRAP debug with `exception_pc` (line 1844)

2. **tools/test_soc.sh**:
   - Added `DEBUG_PC_TRACE` flag support (lines 54-56)

---

## Key Insights

### 1. Session 76 Misdiagnosis
Session 76 concluded "test infrastructure bug" and "initialization code never executed", but:
- PC trace proves initialization executed perfectly
- All CSRs configured correctly
- Real bug is in MEPC calculation, not test setup

### 2. Debug Timing Matters
- Debug statements in different `always` blocks can see different values
- Sequential blocks sample AFTER clock edge (new register values)
- Can lead to misleading debug output
- Always verify with waveforms or multiple debug points

### 3. Combinational Timing Hazards
- Combinational assignments from registers that update on same edge are dangerous
- Creates race conditions in simulation
- May synthesize differently than simulates
- Better to explicitly register intermediate values

### 4. Speculative Prefetch Behavior
- CPU fetches ahead even in tight loops
- Compressed instructions (2-byte) cause non-sequential prefetch
- Prefetch is normal and correct behavior
- Don't confuse prefetch PC with execution PC

---

## Test Commands

```bash
# Run with PC trace
env XLEN=32 DEBUG_PC_TRACE=1 TIMEOUT=5 ./tools/test_soc.sh test_timer_interrupt_simple

# Run with interrupt debug
env XLEN=32 DEBUG_INTERRUPT=1 DEBUG_CLINT=1 TIMEOUT=5 ./tools/test_soc.sh test_timer_interrupt_simple

# Combined debug
env XLEN=32 DEBUG_PC_TRACE=1 DEBUG_INTERRUPT=1 TIMEOUT=5 ./tools/test_soc.sh test_timer_interrupt_simple
```

---

## Related Sessions

- **Session 75**: Fixed CLINT timer bug (req_ready timing)
- **Session 76**: Validated timer interrupt hardware, identified "wrong PC" issue
- **Session 77**: Root caused MEPC bug via PC tracing
- **Session 78** (Next): Fix MEPC calculation and verify with tests

---

## Status

**Session 77**: ✅ **ROOT CAUSE IDENTIFIED**
- Timer interrupt hardware works perfectly ✓
- Test initialization works correctly ✓
- **MEPC calculation has race condition bug** ⚠️
- Fix strategy defined ✓
- Ready for implementation in Session 78

🎯 **Bug fully understood - ready to fix!**
