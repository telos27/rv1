# Session 39 Summary: wbuart32 UART Integration Attempt

**Date**: 2025-10-28
**Status**: UART duplication bug still present - root cause investigation ongoing
**Achievement**: Successfully integrated wbuart32's formally-verified FIFO, comprehensive debug instrumentation added

---

## Problem Statement

FreeRTOS UART output shows character duplication/alternation (Sessions 37-38 issue):
- **Expected**: "FreeRTOS Blinky Demo"
- **Actual**: "  eeeeOSOSlililyy mo mo    rgrg:: `` 11  3232AF..."
- **Pattern**: Every other character duplicated or alternating characters repeated

---

## Approach: Replace UART with wbuart32

### Rationale
Session 38 concluded the issue was likely an Icarus Verilog simulator artifact due to read-during-write hazards in the UART FIFO. Decision made to integrate Dan Gisselquist's **formally-verified wbuart32** UART core.

### Investigation Process

#### 1. Evaluated Open-Source UART Options
- **wbuart32** (ZipCPU): Formally verified, excellent FIFO with bypass logic ⭐
- **OpenCores uart16550**: Mature but has documented FIFO stability issues ❌
- **Decision**: Use wbuart32's `ufifo.v` module (best FIFO implementation)

#### 2. Integration Strategy
Created `uart_16550_ufifo.v` wrapper:
- Uses wbuart32's formally-verified `ufifo.v` for TX/RX FIFOs
- Maintains 16550 register interface (8 registers)
- Keeps byte-level testbench interface
- Adapts simple_bus protocol (not full Wishbone)

**Key Feature - ufifo's Bypass Logic** (lines 190-209 in `external/wbuart32/rtl/ufifo.v`):
```verilog
// last_write -- for bypassing the memory read
always @(posedge i_clk)
if (i_wr && (!o_empty_n || (w_read && r_next == wr_addr)))
    last_write <= i_data;

assign o_data = (osrc) ? last_write : r_data;
```
This forwards write data directly when reading from empty FIFO - exactly what we needed!

---

## Implementation

### Files Created/Modified

**New Files**:
- `rtl/peripherals/uart_16550_ufifo.v` (333 lines) - New UART wrapper using ufifo
- `external/wbuart32/` (git submodule) - wbuart32 repository clone

**Modified Files**:
- `rtl/rv_soc.v`: Changed instantiation from `uart_16550` to `uart_16550_ufifo`
- `tools/test_soc.sh`: Added `-I external/wbuart32/rtl/` and `ufifo.v` to build
- `tools/test_freertos.sh`: Added external UART paths to compilation

**Removed**:
- `rtl/peripherals/uart_16550_wbuart.v` (first attempt - too complex)
- `rtl/peripherals/uart_16550.v` → renamed to `.bak` (old implementation)

---

## Bugs Found and Fixed

### Bug #1: TX FIFO Write Timing (CRITICAL)
**Problem**: FIFO writes were continuous level signals, not one-shot pulses
```verilog
// WRONG (original):
assign tx_fifo_wr = req_valid && req_we && (req_addr == REG_RBR_THR);
```

If `req_valid` stays high for multiple cycles waiting for `req_ready`, the FIFO would see multiple writes!

**Fix**: Edge detection for write pulses
```verilog
// CORRECT:
reg req_valid_prev;
always @(posedge clk) req_valid_prev <= req_valid;
assign req_valid_rising = req_valid && !req_valid_prev;
assign tx_fifo_wr = req_valid_rising && req_we && (req_addr == REG_RBR_THR);
```

Applied to both TX and RX FIFO writes (lines 101-110, 148-149).

### Bug #2: TX State Machine Race Condition
**Problem**: `tx_valid` cleared independently of state machine
```verilog
// State machine transitions
case (tx_state)
  TX_IDLE: if (tx_fifo_empty_n && !tx_valid) → TX_READ  // Check !tx_valid
  ...
endcase

// INDEPENDENT clearing (RACE CONDITION!)
if (tx_valid && tx_ready) tx_valid <= 1'b0;
```

State machine could check `!tx_valid`, then immediately clear it, then start new read - causing duplicate reads!

**Fix**: Keep clearing independent but ensure state machine waits properly
```verilog
TX_IDLE: begin
  if (tx_fifo_empty_n && !tx_valid) begin
    tx_fifo_rd_reg <= 1'b1;
    tx_state <= TX_READ;
  end
  // Stay in IDLE if tx_valid is still high (waiting for testbench)
end
```

### Bug #3: TX FIFO Read Timing
**Problem**: Original combinatorial read signal
```verilog
assign tx_fifo_rd = tx_ready && tx_fifo_empty_n && !tx_valid;
```

**Fix**: Registered read signal controlled by state machine (line 102-103, 217-244):
- TX_IDLE → TX_READ (assert read)
- TX_READ → TX_WAIT (deassert read, wait for data)
- TX_WAIT → capture data, set valid → TX_IDLE

### Bug #4: Multiple UART Definitions
**Discovery**: Both `uart_16550.v` (old) and `uart_16550_ufifo.v` (new) existed
- Wildcard `rtl/peripherals/*.v` included BOTH files
- Icarus Verilog may have used wrong module definition

**Fix**: Renamed old UART to `.bak` to avoid conflicts

---

## Debug Instrumentation Added

Comprehensive three-level debug tracing:

### 1. Core Level (`rtl/core/rv32i_core_pipelined.v` lines 2413-2421)
```verilog
`ifdef DEBUG_UART_CORE
always @(posedge clk) begin
  if (arb_mem_write_pulse && (arb_mem_addr[31:16] == 16'h1000)) begin
    $display("[CORE-UART-WR] Cycle %0d: PC=0x%08h write_pulse=%b ...",
             $time/10, exmem_pc, arb_mem_write_pulse, ...);
  end
end
`endif
```

### 2. Bus Level (`rtl/rv_soc.v` lines 368-375)
```verilog
`ifdef DEBUG_UART_BUS
always @(posedge clk) begin
  if (uart_req_valid && uart_req_we) begin
    $display("[BUS-UART-WR] Cycle %0d: bus_req_valid=%b addr=0x%08h data=0x%02h ...",
             $time/10, uart_req_valid, uart_req_we, ...);
  end
end
`endif
```

### 3. UART FIFO Level (`rtl/peripherals/uart_16550_ufifo.v` lines 113-120)
```verilog
`ifdef DEBUG_UART_FIFO
always @(posedge clk) begin
  if (tx_fifo_wr) begin
    $display("[UART-FIFO-WR] Cycle %0d: Write 0x%02h '%c' to TX FIFO ...",
             $time/10, req_wdata, req_wdata, ...);
  end
end
`endif
```

Usage:
```bash
iverilog ... -D DEBUG_UART_CORE=1 -D DEBUG_UART_BUS=1 -D DEBUG_UART_FIFO=1 ...
```

---

## Test Results

### Quick Regression: ✅ 14/14 PASSING
```
Total:   14 tests
Passed:  14
Failed:  0
Time:    4s
```

No regressions from UART changes!

### FreeRTOS: ❌ Character Duplication PERSISTS

**Output Pattern** (identical to Sessions 37-38):
```
Cycle 1391: 'e'
Cycle 1413: 'e'
Cycle 1433: 'e'
Cycle 1455: 'e'
Cycle 1475: 'O'
Cycle 1497: 'S'
Cycle 1517: 'O'
Cycle 1539: 'S'
...
```

Results in: "  eeeeOSOSlililyy mo mo    rgrg:: `` 11  3232AF..."

---

## Critical Finding: Bug Persists Across ALL Implementations

The EXACT SAME duplication pattern appears with:

1. ✅ Original UART (inline FIFOs with arrays)
2. ✅ wbuart32 ufifo wrapper (formally-verified FIFO)
3. ✅ One-shot write pulse fixes
4. ✅ TX state machine fixes
5. ✅ Read timing fixes
6. ✅ With/without old UART file conflicts

**Conclusion**: The problem is **NOT in the UART module itself**!

---

## Hypotheses for Next Session

### Hypothesis #1: Testbench Capture Logic
**Line 126** in `tb/integration/tb_freertos.v`:
```verilog
always @(posedge clk) begin
  if (reset_n && uart_tx_valid && uart_tx_ready) begin
    // Capture character
```

Could there be a race condition in how the testbench samples `uart_tx_valid`?

### Hypothesis #2: Core-Level Duplicate Writes
Despite Session 34's one-shot write pulse fix, the core might still be issuing duplicate writes to UART specifically. The fix works for other peripherals but might have an edge case.

Need to verify with debug flags:
```bash
iverilog -D DEBUG_UART_CORE=1 -D DEBUG_UART_BUS=1 -D DEBUG_UART_FIFO=1
```

### Hypothesis #3: Bus Protocol Issue
The simple_bus interconnect might be duplicating transactions. The UART's `req_ready` signal timing might cause retries.

### Hypothesis #4: Deep Timing/Simulation Artifact
Icarus Verilog may have specific timing semantics that cause this behavior. Would not appear in:
- Real hardware (FPGA/ASIC)
- Other simulators (Verilator, ModelSim, VCS)

---

## Next Steps (Session 40)

### Priority 1: Waveform Analysis
Generate VCD with debug flags enabled, analyze:
1. Core write pulse timing (is it truly one-shot?)
2. Bus transaction timing (any duplicates?)
3. UART FIFO write signals (multiple writes per character?)
4. Testbench capture timing (sampling edge cases?)

Commands:
```bash
iverilog -D DEBUG_UART_CORE=1 -D DEBUG_UART_BUS=1 -D DEBUG_UART_FIFO=1 ...
timeout 5s vvp sim/test_freertos_debug.vvp > debug.log 2>&1
grep -E "CORE-UART-WR|BUS-UART-WR|UART-FIFO-WR" debug.log | head -100
```

### Priority 2: Minimal Reproduction Test
Create a minimal test that:
- Writes a few characters to UART directly (not via FreeRTOS)
- Reduces complexity to isolate the issue
- Example: `tests/asm/test_uart_simple.s` - write "ABC" and observe

### Priority 3: Alternative Verification
- Test with Verilator (different simulator, better memory semantics)
- If available, test on FPGA hardware
- This would confirm if it's simulator-specific

---

## Code Statistics

**New/Modified Lines**:
- `uart_16550_ufifo.v`: 333 lines (new wrapper)
- `rv32i_core_pipelined.v`: +9 lines (debug)
- `rv_soc.v`: +8 lines (debug, UART instantiation)
- `test_soc.sh`: +2 lines (include paths)
- `test_freertos.sh`: +2 lines (include paths)

**Total**: ~354 lines added/modified

---

## Key Learnings

### ✅ What Worked
1. **ufifo integration** - Formally-verified FIFO with proper bypass logic
2. **Write pulse edge detection** - Critical for preventing FIFO overwrites
3. **Comprehensive debug infrastructure** - Three-level monitoring ready for next session
4. **No regressions** - All existing tests still pass

### ❌ What Didn't Work
1. Different UART implementations → same bug
2. FIFO timing fixes → same bug
3. State machine fixes → same bug
4. Removing old UART file → same bug

### 🔍 What We Learned
The bug is **NOT in the UART FIFO logic** - it's somewhere earlier in the data path:
- Core instruction execution?
- Bus protocol?
- Testbench sampling?
- Simulator artifact?

---

## Files Status

### Active
- `rtl/peripherals/uart_16550_ufifo.v` - New UART (in use)
- `external/wbuart32/rtl/ufifo.v` - Formally-verified FIFO
- Debug instrumentation in core, soc, uart

### Backup
- `rtl/peripherals/uart_16550.v.bak` - Original UART (renamed)

### Removed
- `rtl/peripherals/uart_16550_wbuart.v` - First attempt (deleted)

---

## References

- **Session 34**: UART character duplication - FIXED at core level (write pulse)
- **Session 35**: Atomic operations fix - Write pulse exception
- **Session 37**: UART FIFO root cause identified - Read-during-write hazard
- **Session 38**: UART FIFO fix attempts - Comprehensive ASIC analysis
- **Session 39**: wbuart32 integration (this session) - Bug persists, debug added

**External**:
- wbuart32 Repository: https://github.com/ZipCPU/wbuart32
- ufifo.v Documentation: Lines 1-65 in `external/wbuart32/rtl/ufifo.v`

---

## Action Items for Session 40

- [ ] Generate waveforms with all debug flags enabled
- [ ] Analyze exact timing of first 10 UART characters
- [ ] Create minimal UART test (no FreeRTOS complexity)
- [ ] Compare write pulse behavior: UART vs. other peripherals
- [ ] Consider Verilator simulation as alternative verification

---

**Status**: Investigation ongoing - bug is real and must be fixed. The persistence across implementations suggests a fundamental timing or protocol issue, not a UART-specific bug. Next session will focus on waveform analysis and minimal reproduction.
