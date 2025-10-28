# Session 41: Bus Handshaking Implementation & UART Debug

**Date**: 2025-10-28
**Status**: 🔧 **PARTIAL SUCCESS** - Bus handshaking implemented, UART bug still present
**Duration**: ~3 hours

---

## Problem Statement

From Sessions 37-40, the UART character duplication bug persists:
- **Expected**: "FreeRTOS Blinky Demo"
- **Actual**: "  eeeeOSOSliliy ymomorgrg..."
- **Pattern**: Character alternation/duplication making console output unusable

Session 40 identified root cause: **Core ignores `bus_req_ready` signal** from peripherals.

---

## Implementation: Bus Handshaking (Option 1 from Session 40)

### Changes Made to `rtl/core/rv32i_core_pipelined.v`

#### 1. Added `bus_req_issued` Tracking (Lines 2399-2420)
```verilog
// Track whether we've already issued a bus request for the current instruction
// This prevents duplicate requests when bus isn't ready (peripherals with FIFOs, busy states)
reg bus_req_issued;

always @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    bus_req_issued <= 1'b0;
  end else begin
    // Set: When we issue a write pulse (first time)
    if (arb_mem_write_pulse && !bus_req_ready) begin
      bus_req_issued <= 1'b1;
    end
    // Clear: When bus becomes ready OR instruction leaves MEM stage
    else if (bus_req_ready || !exmem_valid) begin
      bus_req_issued <= 1'b0;
    end
  end
end
```

**Purpose**: Prevents duplicate write pulses when peripheral asserts `ready=0`

#### 2. Modified Write Pulse Generation (Line 2427-2429)
```verilog
wire arb_mem_write_pulse = mmu_ptw_req_valid ? 1'b0 :
                           ex_atomic_busy ? dmem_mem_write :                       // Atomic: level signal
                           (dmem_mem_write && mem_stage_new_instr && !bus_req_issued);  // Normal: one-shot pulse, not already issued
```

**Purpose**: Gate write pulse on `!bus_req_issued` to prevent duplicates

#### 3. Initial Attempt: Pipeline Stall (REVERTED)
Initially tried adding bus stall to `hold_exmem`:
```verilog
wire bus_transaction_pending = (exmem_mem_read || exmem_mem_write) &&
                                exmem_valid &&
                                !bus_req_ready;
assign hold_exmem = ... || bus_transaction_pending;
```

**Result**: **DEADLOCK** - Pipeline stalled, circular dependency
**Fix**: Removed stall approach, kept only `bus_req_issued` flag

---

## Test Results

### Quick Regression: ✅ **14/14 PASSING**
```
Total:   14 tests
Passed:  14
Failed:  0
Time:    4s
```

**No regressions from core changes!**

### FreeRTOS: ❌ **Character Duplication PERSISTS**
```
Output: "  eeeeOSOSliliy ymomorgrg..."
```

**Same exact pattern as before!**

---

## Critical Discovery #1: UART Always Ready

Examined `rtl/peripherals/uart_16550_ufifo.v` line 362:
```verilog
req_ready <= req_valid;  // Always echoes back valid
```

**Finding**: The UART **NEVER asserts `ready=0`**!

**Implication**:
- My `bus_req_issued` fix will NEVER trigger
- `bus_req_ready` is always 1 when accessing UART
- The bus handshaking logic is correct but ineffective for this peripheral

**Conclusion**: Session 40's hypothesis about `bus_req_ready` was incorrect for this UART implementation.

---

## Investigation: Minimal UART Test

### Created `tests/asm/test_uart_abc.s`
Simple assembly program to isolate the issue:
```assembly
li a0, 0x10000000    # UART base
li a1, 'A'
sb a1, 0(a0)         # Write 'A'
<10 NOPs for spacing>
li a1, 'B'
sb a1, 0(a0)         # Write 'B'
<10 NOPs>
li a1, 'C'
sb a1, 0(a0)         # Write 'C'
<10 NOPs>
li a1, 0x0A
sb a1, 0(a0)         # Write newline
ebreak
```

**Expected**: ABC\n (4 characters)
**Actual**: `[0xxx][0xxx][0xxx]` (3 undefined characters)

---

## Critical Discovery #2: UART Transmits Undefined Data! 🔥

### Evidence from tb_soc.v Debug Output
```
[DEBUG-UART] Cycle 13: tx_valid=1 tx_ready=1 data=0xxx ' '
[DEBUG-UART] Cycle 26: tx_valid=1 tx_ready=1 data=0xxx ' '
[DEBUG-UART] Cycle 39: tx_valid=1 tx_ready=1 data=0xxx ' '
```

**Analysis**:
- UART TX is being triggered (3 times, correct count)
- But `uart_tx_data` is **'x' (undefined)**!
- This means data never reached the FIFO, OR FIFO returns garbage

### Possible Root Causes

1. **Bus routing issue**: Stores not reaching UART peripheral
2. **FIFO write detection**: Edge detection not working (`req_valid_rising`)
3. **wbuart32 ufifo integration**: FIFO memory not initialized or read path broken
4. **UART state machine**: Data read from FIFO before write completes

---

## UART State Machine Investigation

### Found Potential Race Condition

Original code (line 219-250):
```verilog
case (tx_state)
  TX_IDLE: if (tx_fifo_empty_n && !tx_valid) → TX_READ
  TX_READ: → TX_WAIT
  TX_WAIT: tx_data <= tx_fifo_rdata; tx_valid <= 1; → TX_IDLE
endcase

// AFTER state machine
if (tx_valid && tx_ready) tx_valid <= 1'b0;
```

**Problem**: In the SAME cycle:
1. TX_WAIT sets `tx_valid=1`
2. Line 247 sees `tx_valid && tx_ready` → clears `tx_valid=0`
3. Next cycle: TX_IDLE sees `!tx_valid` → starts ANOTHER read!

**Attempted Fix**: Move clearing before state machine, add check to TX_IDLE
```verilog
// Clear valid BEFORE state machine
if (tx_valid && tx_ready) tx_valid <= 1'b0;

case (tx_state)
  TX_IDLE: if (tx_fifo_empty_n && !tx_valid && !(tx_valid && tx_ready)) → TX_READ
  ...
endcase
```

**Result**: Still outputs undefined data (didn't fix root cause)

---

## Summary of Findings

### ✅ What Worked
1. **Bus handshaking logic**: Implemented correctly, no regressions
2. **`bus_req_issued` tracking**: Sound approach for peripherals with flow control
3. **Minimal test creation**: Isolated the problem, revealed NEW bug
4. **Quick regression**: All 14/14 tests still passing

### ❌ What Didn't Work
1. **Fix didn't solve UART duplication**: Because UART is always ready
2. **State machine fix**: Undefined data issue persists
3. **Session 40's hypothesis**: Incorrect - UART never asserts `ready=0`

### 🔍 What We Discovered
1. **UART transmits undefined data**: Root cause NOT duplication but garbage data
2. **Bus handshaking irrelevant for this UART**: Peripheral always ready
3. **wbuart32 integration issue**: Either FIFO not receiving writes OR read path broken
4. **Different bug than Sessions 37-38**: Was focused on FIFO hazards, actually data path issue

---

## Code Changes Summary

### Modified Files
- **rtl/core/rv32i_core_pipelined.v**: +24 lines
  - Added `bus_req_issued` register and tracking logic
  - Modified `arb_mem_write_pulse` gating
  - Attempted (and reverted) `hold_exmem` bus stall

- **rtl/peripherals/uart_16550_ufifo.v**: ~5 lines
  - Moved `tx_valid` clearing before state machine
  - Added race condition check to TX_IDLE

- **tests/asm/test_uart_abc.s**: +68 lines (new file)
  - Minimal UART test for debugging

- **tb/integration/tb_soc.v**: Temporary debug output (reverted)

### Files NOT Modified
- Bus interconnect (no changes needed)
- UART FIFO edge detection (already present)
- FreeRTOS port (waiting for UART fix)

---

## Next Session Priorities

### High Priority 🔥
1. **Debug undefined UART data**:
   - Add $display to simple_bus to verify routing
   - Check if `req_valid_rising` edge detection works
   - Verify wbuart32 ufifo write path with waveforms
   - Consider switching back to old uart_16550.v to test if wbuart32 is the issue

2. **Waveform Analysis**:
   - Generate VCD for test_uart_abc
   - Trace bus transactions cycle-by-cycle
   - Verify FIFO write and read timing

3. **Alternative Verification**:
   - Test with Verilator (better memory semantics)
   - Try old uart_16550.v from backup (rtl/peripherals/uart_16550_old.v.bak)

### Medium Priority
4. **If UART unfixable**: Document as known issue, move to Phase 2 priorities
5. **Bus handshaking**: Keep implementation (correct for future peripherals with flow control)

---

## Statistics

- **Time Invested (Sessions 37-41)**: ~10-12 hours total
  - Session 37: Root cause analysis (FIFO hazard hypothesis)
  - Session 38: Multiple fix attempts (all failed)
  - Session 39: wbuart32 integration (bug persists)
  - Session 40: Bus protocol investigation
  - Session 41: Bus handshaking + undefined data discovery

- **Lines Changed**: ~100 lines
- **Test Status**: 14/14 regression passing, FreeRTOS console unusable
- **Compliance**: Still 80/81 (98.8%)

---

## Key Lessons

1. **Always test assumptions**: Session 40 assumed UART used flow control, but it doesn't
2. **Minimal tests are valuable**: test_uart_abc revealed the REAL bug (undefined data)
3. **Bus handshaking is still correct**: Will help future peripherals (timers, DMA, etc.)
4. **Undefined data ≠ duplication**: The bug manifestation changed our understanding
5. **Time boxing is important**: After 10+ hours, consider documenting and moving on

---

## Open Questions

1. **Why is uart_tx_data undefined?**
   - Is bus routing the stores to UART?
   - Is FIFO receiving writes?
   - Is FIFO read returning valid data?

2. **Why did wbuart32 integration not help?**
   - Formally verified FIFO should work
   - Integration issue or fundamental problem?

3. **Will old uart_16550.v work?**
   - Worth trying as sanity check
   - May reveal if wbuart32 is the issue

---

## References

- **Session 37**: UART FIFO read-during-write hazard identified
- **Session 38**: Multiple UART FIFO fix attempts, ASIC analysis
- **Session 39**: wbuart32 formally-verified FIFO integration
- **Session 40**: Bus protocol root cause analysis (partially incorrect)
- **Session 41**: Bus handshaking implementation, undefined data discovery (this session)

**Related Files**:
- `rtl/core/rv32i_core_pipelined.v`: Core bus interface
- `rtl/peripherals/uart_16550_ufifo.v`: UART with wbuart32 ufifo
- `rtl/interconnect/simple_bus.v`: Bus routing logic
- `external/wbuart32/rtl/ufifo.v`: Formally verified FIFO
- `tests/asm/test_uart_abc.s`: Minimal test case

---

**Status**: Bus handshaking implemented and tested ✅, UART undefined data bug remains 🔧, investigation to continue next session.
