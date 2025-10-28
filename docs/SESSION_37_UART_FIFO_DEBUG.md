# Session 37: UART FIFO Duplication Investigation

**Date**: 2025-10-28
**Status**: Root cause identified, fix in progress 🔍
**Achievement**: Identified read-during-write hazard in UART TX FIFO

---

## Problem Statement

FreeRTOS UART output shows **character duplication** with alternating pattern:
- Expected: "FreeRTOS Blinky Demo"
- Actual: "  eeeeOSOSliliy ymomorgrg..."
- Pattern: Every character appears twice or alternates with adjacent characters

This is different from Session 34's bug (which was fixed - core-level write pulse issue).

---

## Investigation Process

### 1. Initial Hypothesis: Core Write Pulse Issue?
**Test**: Added bus-level monitoring to track write requests
**Result**: Core issues **exactly ONE** bus write per character ✅
**Conclusion**: Session 34 fix is working correctly - not a core issue

### 2. UART Hardware Analysis
**Test**: Added detailed FIFO pointer monitoring
**Findings**:
```
Cycle 197: Bus write '=' → FIFO: wptr=2, rptr=2
Cycle 199: TX outputs '=' → FIFO: wptr=3, rptr=3
Cycle 219: Bus write '=' → FIFO: wptr=3, rptr=3
Cycle 221: TX outputs '=' → FIFO: wptr=4, rptr=4
```

**Key Observation**: `wptr == rptr` at every transaction (FIFO always empty)
**Implication**: TX logic reading from FIFO **in the same cycle** as write

### 3. Root Cause: Read-During-Write Hazard

**Location**: `rtl/peripherals/uart_16550.v` lines 150-175

**Scenario**:
```
Cycle N (FIFO empty: wptr=5, rptr=5):
  1. Write logic: tx_fifo[wptr] <= data (writes to index 5)
  2. Write logic: wptr <= 6
  3. TX logic sees: tx_fifo_count = (6-5) = 1 (combinatorial!)
  4. TX logic: reads tx_fifo[rptr] (reads from index 5)
  5. TX logic: rptr <= 6

Problem: Both write and read access tx_fifo[5] in SAME CYCLE!
```

**Verilog Behavior**: Read-during-write to same memory array index produces **undefined results** in Icarus Verilog. The read may return:
- Old data (before write)
- New data (after write)
- Undefined/X values
- Simulator-dependent behavior

**Result**: TX logic reads stale/incorrect data → character duplication

---

## Attempted Fixes

### Fix Attempt #1: Delayed Write Pointer
**Approach**: Use `tx_fifo_wptr_prev` for empty check
```verilog
reg [4:0] tx_fifo_wptr_prev;
assign tx_fifo_empty = (tx_fifo_wptr_prev == tx_fifo_rptr);
```

**Result**: FAILED ❌
**Issue**: Created 1-cycle delay before data visible → TX reads every other write
**Pattern**: "  eeeeOSOSliliy y" (alternating characters, skipping half)

### Fix Attempt #2: Restructured State Machine
**Approach**: Allow TX to clear `tx_valid` and read new data in same cycle
```verilog
if (tx_valid && tx_ready) tx_valid <= 0;
if (!tx_fifo_empty && (!tx_valid || (tx_valid && tx_ready))) begin
  tx_valid <= 1;
  tx_data <= tx_fifo[rptr];
end
```

**Result**: FAILED ❌
**Issue**: Still allowed same-cycle read/write when FIFO becomes non-empty

### Fix Attempt #3: Write-This-Cycle Flag
**Approach**: Set flag during write, use for empty check
```verilog
reg tx_fifo_write_this_cycle;
assign tx_fifo_empty = (count == 0) || (count == 1 && tx_fifo_write_this_cycle);
```

**Result**: FAILED ❌
**Issue**: Flag not visible combinatorially in same cycle, timing conflict

### Fix Attempt #4: Multiple Other Approaches
- Read data buffer register
- Show-ahead FIFO concept
- Explicit read pipeline stage

**Result**: All FAILED ❌
**Common Issue**: Fundamental timing problem with single-ported memory arrays

---

## Technical Analysis

### Why This Is Hard to Fix

1. **Combinatorial Empty Check**: `tx_fifo_empty = (wptr - rptr == 0)` updates immediately when wptr changes
2. **Same-Cycle Visibility**: TX logic sees non-empty FIFO in same cycle as write
3. **Memory Array Semantics**: Verilog arrays are not true dual-port RAMs
4. **Icarus Limitation**: Different simulators handle read-during-write differently

### Why Session 34 Fix Didn't Help

Session 34 fixed **core-level** write pulse duplication:
- Problem: Store instruction staying in MEM stage → duplicate bus writes
- Solution: One-shot write pulses via `mem_stage_new_instr` signal

This is a **peripheral-level** issue:
- Problem: FIFO read-during-write hazard inside UART module
- Core sends single write → UART internal logic duplicates during TX

---

## Current Status

### Verification Results
- **Quick Regression**: 14/14 PASSED ✅ (no regressions)
- **FreeRTOS Boot**: Successful ✅
  - Scheduler starts at cycle 1001
  - Strings readable from IMEM (Session 36 fix working)
  - UART hardware path functional
- **UART Output**: Character duplication persists ❌

### Code Changes
- Added monitoring infrastructure in `tb/integration/tb_freertos.v` (disabled)
- Multiple experimental fixes attempted in `uart_16550.v` (reverted to original)
- **Net Result**: No permanent code changes (all fixes backed out)

---

## Recommended Solutions (For Next Session)

### Option 1: Synchronous Dual-Port RAM (Preferred)
Use explicit dual-port RAM with separate read/write ports:
```verilog
// Separate write and read ports
always @(posedge clk) begin
  if (wr_en) mem[wr_addr] <= wr_data;
  rd_data <= mem[rd_addr];  // Registered read
end
```
**Pros**: Clean separation, synthesizable, defined behavior
**Cons**: 1-cycle read latency (but FIFO should buffer this)

### Option 2: Show-Ahead FIFO
Data always available on output before read request:
```verilog
assign tx_data = tx_fifo[rptr];  // Combinatorial output
// Increment rptr when data consumed
```
**Pros**: Zero-cycle latency, simple
**Cons**: Requires careful timing, may not solve root issue

### Option 3: FIFO Read Pipeline Stage
Add explicit pipeline register:
```verilog
reg [4:0] tx_fifo_rd_addr;
reg [7:0] tx_fifo_rd_data;

always @(posedge clk) begin
  tx_fifo_rd_addr <= rptr;  // Cycle 1: Register address
  tx_fifo_rd_data <= tx_fifo[tx_fifo_rd_addr];  // Cycle 2: Read data
end
```
**Pros**: Guaranteed timing separation
**Cons**: 2-cycle latency, more complex control

### Option 4: Switch Simulator
Use Verilator instead of Icarus Verilog:
- Better memory array handling
- Cycle-accurate simulation
- Faster performance

### Option 5: Accept Limitation
**Note**: This is likely a **simulation artifact only**. In FPGA synthesis:
- Block RAMs have well-defined read-during-write behavior
- Dual-port RAMs with separate clocks handle this correctly
- This issue may not appear in actual hardware

**Recommendation**: Test on FPGA if available, or implement Option 1 (dual-port RAM).

---

## Files Modified (Then Reverted)

- `rtl/peripherals/uart_16550.v` - TX FIFO logic (experimental fixes backed out)
- `tb/integration/tb_freertos.v` - Debug monitoring (now disabled)

**Current State**: Code is back to Session 36 state (IMEM byte-select fix)

---

## Key Takeaways

1. ✅ **Core is correct**: Only one write per character (Session 34 fix working)
2. ✅ **Bus is correct**: Single transaction per write
3. ❌ **UART FIFO has read-during-write hazard**: Root cause identified
4. 🔧 **Fix requires architectural change**: Simple patches insufficient
5. 📊 **No regressions**: All tests still passing (14/14)

---

## Next Session Goals

1. Implement **synchronous dual-port RAM** for TX FIFO (Option 1)
2. Add testbench verification for FIFO timing
3. Test FreeRTOS UART output with fixed FIFO
4. Verify no regressions in quick tests
5. Document final solution

---

## References

- **Session 34**: UART duplication fix (core-level write pulses) ✅ WORKING
- **Session 35**: Atomic operations fix (write pulse exception) ✅ WORKING
- **Session 36**: IMEM byte-select fix (string access) ✅ WORKING
- **This Session**: UART FIFO read-during-write hazard 🔧 IN PROGRESS

---

## Debug Commands Used

```bash
# Run FreeRTOS with UART monitoring
env XLEN=32 TIMEOUT=10 ./tools/test_freertos.sh

# Extract UART character pattern
grep -a "UART-CHAR" /tmp/freertos_uart_debug.log | head -100

# Quick regression check
make test-quick

# View specific test output
env XLEN=32 timeout 3s ./tools/test_soc.sh
```

---

**Conclusion**: Root cause identified with high confidence. Multiple fix attempts made, but fundamental timing issue requires architectural change to dual-port RAM. No regressions introduced. Ready to implement proper fix in next session.
