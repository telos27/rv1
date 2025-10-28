# Session 42: UART ufifo Bug - Root Cause & Fix

**Date**: 2025-10-28
**Status**: ✅ **BUG FIXED** - Reverted to old UART implementation
**Duration**: ~2 hours

---

## Problem Statement

Session 41 discovered a **NEW critical bug** different from the character duplication issue:
- **Expected**: test_uart_abc writes 'A', 'B', 'C' to UART
- **Actual**: UART transmits **undefined data (0xxx, 0xxx, 0xxx)**
- **Impact**: Data never reaches UART correctly - this is NOT duplication, it's garbage data

---

## Investigation: Data Path Tracing

### Step 1: Added Debug Instrumentation

Modified `tb/integration/tb_soc.v` to trace data path:
- **Bus level**: Monitor `master_req_wdata` → `uart_req_wdata`
- **UART level**: Monitor `req_wdata`, FIFO writes, TX state machine
- **FIFO level**: Monitor read data from ufifo

Added debug flags to `tools/test_soc.sh`:
```bash
if [ ! -z "$DEBUG_UART_BUS" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_UART_BUS"
fi
if [ ! -z "$DEBUG_UART_CORE" ]; then
    DEBUG_FLAGS="$DEBUG_FLAGS -DDEBUG_UART_CORE"
fi
```

### Step 2: Data Path Verification

Ran test with debug enabled:
```
[DEBUG-BUS] Cycle 5: UART write master_wdata[7:0]=0x41 uart_wdata=0x41
[DEBUG-UART] Cycle 5: UART RX req_addr=0 req_wdata=0x41
[DEBUG-UART] Cycle 5: FIFO WRITE data=0x41
[DEBUG-UART] Cycle 7: FIFO READ rdata=0x41
[DEBUG-UART] Cycle 7: TX state 0 -> 1 tx_data=0x00 rdata=0x41
[DEBUG-UART] Cycle 7: TX state 1 -> 2 tx_data=0x00 rdata=0xxx  ❌
[DEBUG-UART] Cycle 9: TX state 2 -> 0 tx_data=0xxx rdata=0xxx  ❌
[0xxx]  ← UART outputs undefined data!
```

**Analysis**:
1. ✅ Bus routes data correctly: `0x41 → 0x41`
2. ✅ UART receives: `req_wdata=0x41`
3. ✅ FIFO write: `data=0x41`
4. ✅ FIFO read (cycle 7): `rdata=0x41` (correct!)
5. ❌ **BUG**: Next cycle (state 1→2), `rdata` becomes **undefined (0xxx)**!
6. ❌ TX_WAIT assigns `tx_data <= tx_fifo_rdata` but reads garbage

---

## Root Cause: wbuart32 ufifo Timing Issue

### The Problem

The `external/wbuart32/rtl/ufifo.v` module's output data becomes undefined between clock cycles:

**TX State Machine** (uart_16550_ufifo.v lines 225-246):
```verilog
TX_IDLE: begin
  if (tx_fifo_empty_n && !tx_valid) begin
    tx_fifo_rd_reg <= 1'b1;  // Issue read
    tx_state <= TX_READ;
  end
end

TX_READ: begin
  // Read issued, wait for data
  tx_state <= TX_WAIT;
end

TX_WAIT: begin
  tx_data <= tx_fifo_rdata;  // ❌ rdata is UNDEFINED here!
  tx_valid <= 1'b1;
  tx_state <= TX_IDLE;
end
```

**Timing**:
- Cycle 7 (IDLE→READ): FIFO read issued, `rdata=0x41` ✓
- Cycle 7 (READ→WAIT): `rdata=0xxx` ❌ (data disappeared!)
- Cycle 9 (WAIT→IDLE): `tx_data=0xxx` assigned

### Why ufifo's rdata becomes undefined

The ufifo module (line 209):
```verilog
assign o_data = (osrc) ? last_write : r_data;
```

The `osrc` signal and `r_data` register have complex timing logic that doesn't hold data stable across the multi-cycle TX state machine. When the FIFO is read:
1. First cycle: `r_data` gets updated with FIFO contents
2. Next cycle: `osrc` or other internal state changes → `o_data` becomes undefined

This is a **timing mismatch** between ufifo's single-cycle read assumption and the UART's multi-cycle state machine.

---

## Solution: Revert to Old UART Implementation

### Decision

The wbuart32 ufifo integration (Session 39) introduced this bug. The old `uart_16550.v` with simple internal FIFO worked correctly.

**Reverted to old implementation**:
```bash
cp rtl/peripherals/uart_16550_ufifo.v rtl/peripherals/uart_16550_ufifo.v.broken_backup
cp rtl/peripherals/uart_16550_old.v.bak rtl/peripherals/uart_16550.v
mv rtl/peripherals/uart_16550_ufifo.v rtl/peripherals/uart_16550_ufifo.v.broken_backup
```

### Changes Made

#### 1. rtl/rv_soc.v (line 212)
```verilog
// OLD (broken):
uart_16550_ufifo #(
  .BASE_ADDR(32'h1000_0000),
  .LGFLEN(4)
) uart_inst (

// NEW (fixed):
uart_16550 #(
  .BASE_ADDR(32'h1000_0000)
) uart_inst (
```

#### 2. tools/test_soc.sh (line 124-129)
Removed ufifo from compilation:
```bash
# OLD:
external/wbuart32/rtl/ufifo.v \

# NEW: (line removed)
```

#### 3. tools/test_freertos.sh (line 66-71)
Removed ufifo from compilation:
```bash
# OLD:
external/wbuart32/rtl/ufifo.v \

# NEW: (line removed)
```

#### 4. tb/integration/tb_soc.v (lines 158-174)
Updated debug instrumentation for old UART signals:
```verilog
// OLD (ufifo signals):
DUT.uart_inst.tx_fifo_wr
DUT.uart_inst.tx_state

// NEW (old UART signals):
DUT.uart_inst.req_valid
DUT.uart_inst.tx_fifo_wptr
DUT.uart_inst.tx_fifo_count
```

---

## Verification Results

### test_uart_abc: ✅ **FIXED!**
```
ABC
TEST PASSED
Cycles: 42
```

Characters output correctly: 'A', 'B', 'C' (was 0xxx, 0xxx, 0xxx)

### Quick Regression: ✅ **14/14 PASSING**
```
Total:   14 tests
Passed:  14
Failed:  0
Time:    4s
```

No regressions from UART revert!

### FreeRTOS: ⚠️ **Character Duplication Remains**
```
Output: "FALALAsAsrtrtn nil! ! *"
Expected: "FATAL: Assertion failed!"
```

**Analysis**: This is a **different bug** from the undefined data issue:
- Each character appears **twice** with ~20 cycle spacing
- This resembles Session 34's write pulse duplication bug
- May need investigation in next session

---

## Technical Analysis

### Why wbuart32 ufifo Failed

The formally-verified ufifo from wbuart32 project is designed for:
- **Single-cycle read**: Master reads `o_data` in same cycle as `i_rd=1`
- **Wishbone bus protocol**: Synchronous single-cycle transactions

Our UART TX state machine uses:
- **Multi-cycle read**: Read issued in one cycle, data used 1-2 cycles later
- **Local FIFO interface**: Not Wishbone-compatible

**Mismatch**: ufifo's `o_data` timing doesn't hold stable across multiple cycles.

### Why Old UART Works

The original `uart_16550.v` FIFO (lines 79-85):
```verilog
reg [7:0] tx_fifo [0:FIFO_DEPTH-1];
reg [4:0] tx_fifo_wptr;
reg [4:0] tx_fifo_rptr;

// Direct memory access - data stable until pointer changes
wire [7:0] fifo_data = tx_fifo[tx_fifo_rptr];
```

**Simple design**: Direct array access → data remains stable until pointer changes.

---

## Lessons Learned

### 1. Interface Compatibility is Critical
- Formal verification of a module doesn't guarantee compatibility with all interfaces
- ufifo is correct for its intended use (Wishbone bus), but incompatible with our multi-cycle state machine

### 2. Debug Instrumentation is Powerful
- Added targeted debug monitors to trace data through entire path
- Cycle-accurate tracing revealed the exact point where data became undefined

### 3. Sometimes Simpler is Better
- The old simple FIFO (direct array access) works reliably
- The formally-verified ufifo has complex bypass logic that introduces timing issues

### 4. Minimal Test Cases
- `test_uart_abc.s` (writing just 'ABC') isolated the problem perfectly
- Much faster to debug than full FreeRTOS boot

---

## Open Questions for Next Session

### 1. FreeRTOS Character Duplication
- Is this related to Session 34's write pulse fix?
- Why does test_uart_abc work but FreeRTOS duplicates?
- Possible hypothesis: Multiple writes in rapid succession trigger the bug

### 2. Alternative FIFO Solutions
- Could implement synchronous dual-port RAM for proper read-during-write handling (Session 37's recommendation)
- Or stick with current simple FIFO since it works?

---

## Statistics

- **Debug Time**: ~2 hours
- **Root Cause**: wbuart32 ufifo timing incompatibility
- **Solution**: Revert to old uart_16550.v
- **Verification**: 14/14 regression passing, test_uart_abc fixed
- **Remaining Issues**: FreeRTOS character duplication (separate bug)

---

## Files Modified

### Core Changes
- `rtl/rv_soc.v`: Changed UART instantiation (uart_16550_ufifo → uart_16550)
- `rtl/peripherals/uart_16550.v`: Restored from backup
- `rtl/peripherals/uart_16550_ufifo.v`: Moved to .broken_backup

### Build System
- `tools/test_soc.sh`: Removed ufifo from compilation, added DEBUG_UART_* support
- `tools/test_freertos.sh`: Removed ufifo from compilation

### Test Infrastructure
- `tb/integration/tb_soc.v`: Added comprehensive UART debug instrumentation
- `tests/asm/test_uart_abc.s`: Minimal test case (existing from Session 41)

---

## References

- **Session 37**: UART FIFO read-during-write hazard identified
- **Session 38**: Multiple UART FIFO fix attempts with ufifo
- **Session 39**: wbuart32 formally-verified FIFO integration (introduced this bug)
- **Session 40**: Bus protocol root cause analysis
- **Session 41**: Bus handshaking implementation, undefined data discovery
- **Session 42**: Root cause identified, reverted to old UART (this session)

**Related Files**:
- `rtl/peripherals/uart_16550.v`: Simple UART with working FIFO
- `rtl/peripherals/uart_16550_ufifo.v.broken_backup`: Broken wbuart32 version
- `external/wbuart32/rtl/ufifo.v`: Formally-verified FIFO (incompatible timing)
- `tb/integration/tb_soc.v`: Debug instrumentation
- `tests/asm/test_uart_abc.s`: Minimal test case

---

**Status**: UART undefined data bug FIXED ✅ - Simple tests working, FreeRTOS duplication needs investigation in next session 🚧
