# Next Session: Complete A Extension Integration

## Quick Start

**Current Status**: Phase 7 - A Extension 60% Complete
**Last Commit**: `68ef663` - Core modules complete
**Next Goal**: Complete pipeline integration and testing

## What's Been Done ✅

1. **Core Modules** (100% complete)
   - `rtl/core/atomic_unit.v` - All atomic operations
   - `rtl/core/reservation_station.v` - LR/SC tracking
   - `rtl/core/control.v` - AMO opcode support
   - `rtl/core/decoder.v` - Atomic field extraction
   - `rtl/core/idex_register.v` - A extension ports added

2. **Documentation** (100% complete)
   - `docs/A_EXTENSION_DESIGN.md` - Full specification
   - `A_EXTENSION_SESSION_SUMMARY.md` - Session report

3. **Pipeline Integration** (50% complete)
   - ID stage: ✅ Complete
   - EX stage: ⏳ Pending
   - MEM/WB stages: ⏳ Pending

## What Needs to Be Done 🚧

### 1. EX Stage Integration (Priority: HIGH)

**Location**: `rtl/core/rv32i_core_pipelined.v` around line 600

**Task**: Instantiate atomic unit and reservation station

```verilog
// Add after M extension unit (around line 580)

// A Extension: Atomic Unit
wire atomic_start;
wire [XLEN-1:0] atomic_result;
wire atomic_busy;
wire atomic_done;

assign atomic_start = idex_is_atomic && idex_valid && !atomic_busy;

atomic_unit #(
  .XLEN(XLEN)
) a_unit (
  .clk(clk),
  .reset_n(reset_n),
  .start(atomic_start),
  .funct5(idex_funct5),
  .funct3(idex_funct3),
  .aq(idex_aq),
  .rl(idex_rl),
  .addr(ex_alu_operand_a_forwarded),  // rs1 = address
  .src_data(ex_rs2_data_forwarded),   // rs2 = data
  // Memory interface (needs decision - see below)
  .mem_req(atomic_mem_req),
  .mem_we(atomic_mem_we),
  .mem_addr(atomic_mem_addr),
  .mem_wdata(atomic_mem_wdata),
  .mem_size(atomic_mem_size),
  .mem_rdata(atomic_mem_rdata),
  .mem_ready(atomic_mem_ready),
  // Reservation station interface
  .lr_valid(lr_valid),
  .lr_addr(lr_addr),
  .sc_valid(sc_valid),
  .sc_addr(sc_addr),
  .sc_success(sc_success),
  // Outputs
  .result(atomic_result),
  .done(atomic_done),
  .busy(atomic_busy)
);

// Reservation Station
wire lr_valid, sc_valid, sc_success;
wire [XLEN-1:0] lr_addr, sc_addr;

reservation_station #(
  .XLEN(XLEN)
) res_station (
  .clk(clk),
  .reset_n(reset_n),
  .lr_valid(lr_valid),
  .lr_addr(lr_addr),
  .sc_valid(sc_valid),
  .sc_addr(sc_addr),
  .sc_success(sc_success),
  .invalidate(exmem_mem_write && exmem_valid),  // Invalidate on stores
  .inv_addr(exmem_alu_result),
  .exception(exception),
  .interrupt(1'b0)  // TODO: Add interrupt signal when implemented
);

// Hold EXMEM when atomic busy (similar to M extension)
wire hold_exmem_atomic = atomic_busy;
wire hold_exmem = hold_exmem_mul_div || hold_exmem_atomic;  // Combine with M extension
```

### 2. Memory Interface Decision (Priority: HIGH)

**Options**:

**Option A: Direct Memory Access** (Simpler)
- Atomic unit connects directly to data memory
- Multiplex control between normal load/store and atomic
- Need arbiter for mem_req, mem_we, mem_addr, mem_wdata

**Option B: Through Pipeline** (More integrated)
- Atomic uses normal MEM stage
- Atomic unit generates "pseudo load/store" transactions
- Requires more state tracking

**Recommended**: Option A for simplicity

### 3. EXMEM Pipeline Register Updates (Priority: HIGH)

**File**: `rtl/core/exmem_register.v`

Add ports:
```verilog
// Inputs
input  wire [XLEN-1:0]  atomic_result_in,

// Outputs
output reg  [XLEN-1:0]  atomic_result_out,
```

Add to always block (all 3 sections: reset, flush, normal)

### 4. MEMWB Pipeline Register Updates (Priority: HIGH)

**File**: `rtl/core/memwb_register.v`

Same pattern as EXMEM - add `atomic_result` input/output

### 5. Writeback Multiplexer (Priority: HIGH)

**File**: `rtl/core/rv32i_core_pipelined.v` around line 780

Update:
```verilog
assign wb_data = (memwb_wb_sel == 3'b000) ? memwb_alu_result :
                 (memwb_wb_sel == 3'b001) ? memwb_mem_read_data :
                 (memwb_wb_sel == 3'b010) ? memwb_pc_plus_4 :
                 (memwb_wb_sel == 3'b011) ? memwb_csr_rdata :
                 (memwb_wb_sel == 3'b100) ? memwb_mul_div_result :
                 (memwb_wb_sel == 3'b101) ? memwb_atomic_result :  // NEW
                 {XLEN{1'b0}};
```

### 6. Hazard Detection (Priority: MEDIUM)

**File**: `rtl/core/hazard_detection_unit.v`

Add atomic stall logic (similar to M extension):
```verilog
input  wire atomic_busy,

// In stall logic
assign stall = load_use_hazard || mul_div_busy || atomic_busy;
```

### 7. Data Memory Atomic Support (Priority: MEDIUM)

**File**: `rtl/core/data_memory.v`

For now, atomic operations can use normal read/write interface. True atomicity requires:
- Disable interrupts during atomic (simple cores)
- Lock memory during read-modify-write (multicore)

Can defer true atomicity to later.

### 8. Testing (Priority: HIGH)

Create test files in `tests/asm/`:

**test_lr_sc_basic.s**:
```assembly
    la    a0, shared_var
    li    t0, 42
retry:
    lr.w  t1, (a0)      # Load reserved
    addi  t1, t1, 1     # Increment
    sc.w  t2, t1, (a0)  # Store conditional
    bnez  t2, retry     # Retry if failed
    # Success - t1 should be old value, memory updated
```

**test_amo_swap.s**:
```assembly
    la     a0, test_data
    li     t0, 0x12345678
    amoswap.w t1, t0, (a0)  # Swap t0 with memory
    # t1 = old memory value, memory = 0x12345678
```

Similar tests for each AMO operation.

### 9. Build and Test

```bash
# Compile
iverilog -g2012 -I rtl -DCONFIG_RV32I \
  -o sim/rv32ia_test.vvp \
  rtl/core/*.v rtl/memory/*.v \
  tb/integration/tb_core_pipelined.v

# Run
vvp sim/rv32ia_test.vvp

# Debug if needed
gtkwave sim/waves/core_pipelined.vcd
```

## Common Issues to Watch For

1. **Stall Logic**: Ensure atomic_busy properly stalls pipeline
2. **Memory Arbitration**: Atomic and normal mem access don't conflict
3. **Reservation Invalidation**: Test that stores invalidate reservations
4. **Forwarding**: Atomic results should not be forwarded mid-operation
5. **Exception Handling**: Atomic operations should be atomic even with exceptions

## File Locations

**Core modules** (already done):
- `rtl/core/atomic_unit.v`
- `rtl/core/reservation_station.v`

**Need updates**:
- `rtl/core/rv32i_core_pipelined.v` (main integration)
- `rtl/core/exmem_register.v`
- `rtl/core/memwb_register.v`
- `rtl/core/hazard_detection_unit.v`
- `rtl/core/data_memory.v` (optional)

**Test files** (need to create):
- `tests/asm/test_lr_sc_basic.s`
- `tests/asm/test_amo_*.s` (one per operation)

## Success Criteria

- [ ] All modules compile without errors
- [ ] Basic LR/SC test passes
- [ ] All 9 AMO operations work
- [ ] Reservation invalidation works
- [ ] No regression in existing tests
- [ ] Pipeline doesn't deadlock on atomic stalls

## Estimated Time

**Integration**: 1-2 hours
**Testing**: 1-2 hours
**Debug**: 0.5-1 hour
**Total**: 3-5 hours (one focused session)

## Questions to Resolve

1. Memory interface: Direct access or through pipeline?
2. Do we implement true atomicity or just functional behavior for now?
3. Should we add interrupt support for reservation invalidation?

## Reference Documents

- `docs/A_EXTENSION_DESIGN.md` - Full specification
- `A_EXTENSION_SESSION_SUMMARY.md` - What was done this session
- `docs/M_EXTENSION_DESIGN.md` - Similar integration pattern
- RISC-V Unprivileged ISA Manual - A Extension chapter

Good luck with the integration! The hard design work is done - now it's mostly wiring.
