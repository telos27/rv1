# Session 16: Bus Interconnect Integration Plan

**Date**: 2025-10-26
**Phase**: 1.3 - Bus Interconnect Implementation
**Status**: Design Complete, Integration In Progress

---

## Progress So Far ✅

1. ✅ **Design Document Created**: `docs/BUS_INTERCONNECT_DESIGN.md`
2. ✅ **Bus Arbiter Module**: `rtl/bus/bus_arbiter.v` (130 lines)
3. ✅ **Bus Arbiter Testbench**: `tb/integration/tb_bus_arbiter.v` (370 lines)
4. ✅ **Bus Arbiter Tests**: 8/8 passing (100%)
5. ✅ **CLINT**: Already has bus-compatible interface
6. ✅ **UART**: Already has bus-compatible interface

---

## Integration Architecture

### Current Architecture (Phase 1.2)
```
┌─────────────────────────────────────┐
│       rv_core_pipelined             │
│   ┌──────────────────────────┐      │
│   │  Data Memory (DMEM)      │      │  (Internal to core)
│   │  - 64KB byte-addressable │      │
│   └──────────────────────────┘      │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│            rv_soc                   │
│   ┌──────┐  ┌──────┐                │
│   │CLINT │  │ UART │  (Not connected)
│   └──────┘  └──────┘                │
└─────────────────────────────────────┘
```

### Target Architecture (Phase 1.3)
```
┌─────────────────────────────────────┐
│       rv_core_pipelined             │
│   ┌──────────────────────────┐      │
│   │  Bus Master Interface    │◄─────┼─── Expose 6 signals
│   │  - addr, wdata, we, etc  │      │
│   └──────────────────────────┘      │
└─────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│            rv_soc                   │
│   ┌──────────────────────────┐      │
│   │   Bus Arbiter            │      │
│   │   - Address decode       │      │
│   │   - Response mux         │      │
│   └──────────────────────────┘      │
│        │        │         │          │
│        ▼        ▼         ▼          │
│   ┌──────┐ ┌───────┐ ┌──────┐       │
│   │ DMEM │ │ CLINT │ │ UART │       │
│   └──────┘ └───────┘ └──────┘       │
└─────────────────────────────────────┘
```

---

## Required Changes

### 1. Core Module (`rtl/core/rv32i_core_pipelined.v`)

#### Changes:
- **Remove** internal DMEM instantiation (lines 2203-2216)
- **Add** bus master interface ports
- **Expose** existing internal signals as module outputs/inputs

#### New Ports:
```verilog
// Bus master interface (to SoC)
output wire             bus_req_valid,
output wire [XLEN-1:0]  bus_req_addr,
output wire [63:0]      bus_req_wdata,
output wire             bus_req_we,
output wire [2:0]       bus_req_size,
input  wire             bus_req_ready,
input  wire [63:0]      bus_req_rdata
```

#### Internal Changes:
- Map `arb_mem_*` signals to bus interface
- Remove DMEM instantiation
- Connect `bus_req_rdata` to `arb_mem_read_data`

**Estimated Lines Changed**: ~20 lines

---

### 2. SoC Module (`rtl/rv_soc.v`)

#### Changes:
- **Instantiate** bus arbiter
- **Instantiate** DMEM (move from core to SoC)
- **Connect** bus arbiter to core, DMEM, CLINT, UART
- **Update** peripheral interface connections

#### New Structure:
```verilog
// Core bus interface
wire             bus_req_valid;
wire [XLEN-1:0]  bus_req_addr;
wire [63:0]      bus_req_wdata;
wire             bus_req_we;
wire [2:0]       bus_req_size;
wire             bus_req_ready;
wire [63:0]      bus_req_rdata;

// DMEM interface
wire             dmem_valid;
wire [XLEN-1:0]  dmem_addr;
wire [63:0]      dmem_wdata;
wire             dmem_we;
wire [2:0]       dmem_size;
wire             dmem_ready;
wire [63:0]      dmem_rdata;

// CLINT interface
wire             clint_valid;
wire [15:0]      clint_addr;
wire [63:0]      clint_wdata;
wire             clint_we;
wire [2:0]       clint_size;
wire             clint_ready;
wire [63:0]      clint_rdata;

// UART interface
wire             uart_valid;
wire [2:0]       uart_addr;
wire [7:0]       uart_wdata;
wire             uart_we;
wire             uart_ready;
wire [7:0]       uart_rdata;

// Instantiate bus arbiter
bus_arbiter #(.XLEN(XLEN)) bus_arb (...);

// Instantiate DMEM
data_memory #(...) dmem (...);

// Connect core with new bus interface
rv_core_pipelined #(...) core (
  ...
  .bus_req_valid(bus_req_valid),
  .bus_req_addr(bus_req_addr),
  ...
);
```

**Estimated Lines Changed**: ~100 lines

---

### 3. Testbenches Update

#### Files to Update:
- `tb/integration/tb_core_pipelined.v`
- `tb/integration/tb_soc.v`
- All unit tests

#### Changes:
- Remove DMEM instantiation from core tests (now in SoC)
- Update signal connections
- **OR** keep backward compatibility by adding DMEM wrapper

**Strategy**: Update `tb_soc.v` first, ensure SoC tests pass, then update other testbenches

---

## Integration Steps (Detailed)

### Step 1: Modify Core ✓
1. Add bus interface ports to module declaration
2. Map internal `arb_mem_*` signals to bus ports
3. Remove DMEM instantiation
4. **Test**: Compile check only (won't run without SoC changes)

### Step 2: Modify SoC ✓
1. Add bus arbiter instantiation
2. Add DMEM instantiation (moved from core)
3. Connect all bus signals
4. Update CLINT/UART connections
5. **Test**: Compile and run `tb_soc.v`

### Step 3: Update Testbenches ✓
1. Update `tb_soc.v` to handle new architecture
2. **Test**: Run basic SoC test
3. Update other testbenches as needed

### Step 4: Run Regression ✓
1. Run `make test-quick` (14/14 tests)
2. Fix any failures
3. Run full compliance suite (81/81 tests)

### Step 5: Integration Tests ✓
1. Write `test_clint_timer.s` - CPU programs MTIMECMP
2. Write `test_uart_transmit.s` - CPU sends "Hello\n"
3. Add to quick regression

---

## Risk Assessment

### Low Risk ✅
- Bus arbiter already tested (8/8 tests passing)
- CLINT/UART already have bus interfaces
- Changes are mostly re-wiring, not new logic

### Medium Risk ⚠️
- Core interface change affects all testbenches
- May break existing tests temporarily
- Need careful signal mapping

### Mitigation
- Make changes incrementally
- Test at each step
- Keep git checkpoint before starting

---

## Timeline Estimate

- **Step 1** (Core changes): 30 minutes
- **Step 2** (SoC changes): 45 minutes
- **Step 3** (Testbench updates): 30 minutes
- **Step 4** (Regression): 15 minutes
- **Step 5** (Integration tests): 60 minutes

**Total**: ~3 hours

---

## Success Criteria

### Phase 1.3 Complete When:
- ✅ Core exposes bus interface
- ✅ SoC integrates bus arbiter, DMEM, CLINT, UART
- ✅ Quick regression passes (14/14)
- ✅ Full compliance passes (81/81)
- ✅ CPU can program CLINT timer via load/store
- ✅ CPU can transmit via UART via load/store
- ✅ Zero regressions

---

## Next Steps

**Option 1**: Proceed with integration (recommended)
- Start with Step 1 (modify core)
- Incremental testing at each step

**Option 2**: Defer integration, write tests first
- Write CLINT/UART tests using current architecture
- Integrate bus later when time permits

**Recommendation**: **Option 1** - The bus arbiter is ready and tested. Integration is straightforward wiring. Better to complete Phase 1.3 now than leave it half-done.

---

**Decision Point**: Should I proceed with the integration? (Y/N)
