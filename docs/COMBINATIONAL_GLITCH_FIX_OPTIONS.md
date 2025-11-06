# Combinational Glitch Fix Options - Detailed Analysis
**Date**: 2025-11-06
**Issue**: Session 99 combinational timing glitch in MMU→Memory→Register path

## Problem Summary

### The Combinational Path
```
EX/MEM Register (exmem_alu_result)
  ↓ [combinational]
MMU TLB Lookup (req_vaddr → req_paddr)
  ↓ [combinational]
Memory Address Decode (addr → masked_addr)
  ↓ [combinational]
Memory Read Array (masked_addr → word_data)
  ↓ [combinational]
Memory Output Mux (word_data → read_data)
  ↓ [sampled]
MEM/WB Register (samples read_data on clock edge)
```

**Total Combinational Depth**: 5+ levels
**Problem**: Glitches during MMU TLB lookup propagate through memory, get sampled by MEM/WB register

### Evidence from Session 99
```verilog
// Same cycle, same address, TWO different outputs:
DMEM: addr=0x80003004 masked=0x00003000 word=0xcafebabe  ← GLITCH!
DMEM: addr=0x80003004 masked=0x00003004 word=0xdeadc0de  ← STABLE
REGFILE: x7 <= 0xcafebabe  ← Sampled glitch!
```

### Root Cause
- MMU TLB lookup creates transient address changes during same cycle
- `data_memory.v` uses `always @(*)` blocks (combinational)
- Glitches propagate through entire memory read path
- MEM/WB register samples value during glitch window

---

## Fix Options Analysis

### Option 1: Register MMU Output (Recommended)
**Approach**: Add pipeline register between MMU and memory access

#### Implementation
```verilog
// In rv32i_core_pipelined.v, around line 2509
// Add new pipeline stage: EXMEM_ADDR

reg [XLEN-1:0] exmem_addr_paddr;  // Registered physical address
reg exmem_addr_valid;             // Valid flag for translated address
reg exmem_addr_page_fault;        // Page fault flag

always @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    exmem_addr_paddr <= {XLEN{1'b0}};
    exmem_addr_valid <= 1'b0;
    exmem_addr_page_fault <= 1'b0;
  end else begin
    // Register MMU output for next cycle
    exmem_addr_paddr <= use_mmu_translation ? mmu_req_paddr : dmem_addr;
    exmem_addr_valid <= mmu_req_ready;
    exmem_addr_page_fault <= mmu_req_page_fault;
  end
end

// Use registered address for memory access
assign arb_mem_addr = mmu_ptw_req_valid ? mmu_ptw_req_addr : exmem_addr_paddr;
```

#### Pros
- ✅ **Simple**: Only ~15 lines of code
- ✅ **Surgical**: Minimal impact on rest of pipeline
- ✅ **Effective**: Completely eliminates glitches
- ✅ **Correct**: Matches standard pipelined processor design

#### Cons
- ⚠️ **Adds 1 cycle latency** to all memory operations (loads/stores)
- ⚠️ **Requires hazard detection updates** for load-use hazards
- ⚠️ **Changes CPI** - all programs will run slightly slower

#### Impact Analysis
1. **Load-Use Hazard**: Currently 1-cycle stall → becomes 2-cycle stall
2. **Store Timing**: Store address registered one cycle later
3. **Performance**: ~5-10% CPI increase (depends on memory access frequency)

#### Required Changes
1. `rtl/core/rv32i_core_pipelined.v`:
   - Add `exmem_addr_*` registers (lines ~2510-2530)
   - Update memory address mux to use registered values
2. `rtl/core/hazard_detection.v`:
   - Extend load-use hazard detection by 1 cycle
   - Check both EXMEM and MEMWB for load hazards
3. `rtl/core/forwarding_unit.v`:
   - May need adjustments for forwarding from later stage

**Estimated Implementation Time**: 2-3 hours

---

### Option 2: Move MMU to EX Stage
**Approach**: Perform translation earlier in pipeline, have stable address in MEM stage

#### Implementation
```verilog
// In rv32i_core_pipelined.v
// Move MMU translation request from MEM to EX stage

// OLD (line 2475):
assign mmu_req_valid = exmem_valid && (exmem_mem_read || exmem_mem_write);
assign mmu_req_vaddr = exmem_alu_result;

// NEW:
assign mmu_req_valid = idex_valid && (idex_mem_read || idex_mem_write);
assign mmu_req_vaddr = ex_alu_result;  // Use ALU output before registering

// Add new EXMEM registers for translation result
reg [XLEN-1:0] exmem_paddr;
reg exmem_translation_fault;

always @(posedge clk) begin
  if (!hold_exmem && !flush_exmem) begin
    exmem_paddr <= mmu_req_paddr;  // Register translated address
    exmem_translation_fault <= mmu_req_page_fault;
  end
end
```

#### Pros
- ✅ **No extra latency**: Translation happens in parallel with EX stage
- ✅ **Clean separation**: Translation (EX) and memory access (MEM) in separate stages
- ✅ **Matches CPU textbooks**: Standard 5-stage pipeline with MMU in EX
- ✅ **Better timing**: More time for TLB lookup before memory access

#### Cons
- ⚠️ **Complex**: Requires reworking EX stage logic
- ⚠️ **Stall handling**: Must stall EX stage during page table walks (not just MEM)
- ⚠️ **Exception timing**: MMU exceptions occur earlier, affects trap handling
- ⚠️ **ALU forwarding**: Must coordinate with ALU result forwarding

#### Impact Analysis
1. **Stall Logic**: EX stage must stall when MMU is busy (currently only MEM stalls)
2. **Exception Handling**: Page faults detected in EX instead of MEM
3. **Forwarding**: MMU needs ALU result before it's registered in EXMEM

#### Required Changes
1. `rtl/core/rv32i_core_pipelined.v`:
   - Move MMU request to EX stage (~line 1500)
   - Add `exmem_paddr` register
   - Update stall logic to include EX stage
2. `rtl/core/exception_unit.v`:
   - Handle page faults from EX stage (currently from MEM)
3. `rtl/core/hazard_detection.v`:
   - Add EX stage MMU stall logic

**Estimated Implementation Time**: 4-6 hours

---

### Option 3: Two-Cycle Memory Access
**Approach**: Split memory access into address and data phases

#### Implementation
```verilog
// In data_memory.v
// Change from combinational to registered read

reg [XLEN-1:0] addr_reg;          // Registered address
reg mem_read_reg;                 // Registered read enable
reg [2:0] funct3_reg;             // Registered funct3

always @(posedge clk) begin
  // Phase 1: Register address
  addr_reg <= addr;
  mem_read_reg <= mem_read;
  funct3_reg <= funct3;
end

// Phase 2: Combinational read using registered address
assign masked_addr = addr_reg & (MEM_SIZE - 1);
// ... rest of read logic uses addr_reg, not addr
```

#### Pros
- ✅ **Isolates glitch source**: Memory sees stable address
- ✅ **Minimal pipeline changes**: No hazard detection updates needed
- ✅ **Realistic**: Models actual SRAM timing (address setup time)

#### Cons
- ⚠️ **Still adds latency**: 1 extra cycle for all memory operations
- ⚠️ **Doesn't fix root cause**: MMU still glitches, just isolated
- ⚠️ **Read-after-write hazard**: Store followed by load needs special handling

#### Impact Analysis
1. **Performance**: Same as Option 1 (~5-10% CPI increase)
2. **Hazard Detection**: Load-use hazards become 2-cycle stalls
3. **Store-Load Forwarding**: Needs bypass from write buffer

**Estimated Implementation Time**: 2-3 hours

---

### Option 4: Add Address Hold Register
**Approach**: Sample and hold address at MEM stage entry, use throughout stage

#### Implementation
```verilog
// In rv32i_core_pipelined.v
reg [XLEN-1:0] mem_addr_hold;    // Sampled at MEM entry
reg mem_addr_valid;

always @(posedge clk) begin
  if (!hold_exmem) begin
    // Sample address when instruction enters MEM stage
    mem_addr_hold <= use_mmu_translation ? mmu_req_paddr : dmem_addr;
    mem_addr_valid <= mmu_req_ready;
  end
  // Hold address if MEM stage is stalled
end

// Use held address for memory (not live MMU output)
assign arb_mem_addr = mmu_ptw_req_valid ? mmu_ptw_req_addr : mem_addr_hold;
```

#### Pros
- ✅ **Zero added latency**: Address sampled at MEM entry, not after
- ✅ **Simple**: Just a few registers
- ✅ **Minimal changes**: Rest of pipeline unchanged

#### Cons
- ❌ **Doesn't solve the problem**: Glitch still happens at sample time!
- ❌ **Race condition**: Sample time is when glitch occurs
- ❌ **Unreliable**: Timing-dependent on when `@(posedge clk)` samples

#### Verdict
**Not recommended** - doesn't actually fix the glitch, just moves the sampling point

---

### Option 5: Synchronous Memory with Registered Output
**Approach**: Use synchronous SRAM model with registered data output

#### Implementation
```verilog
// In data_memory.v
// Model synchronous SRAM: address in cycle N, data out cycle N+1

reg [XLEN-1:0] read_data_reg;

always @(posedge clk) begin
  if (mem_read) begin
    // Register the combinational read
    read_data_reg <= read_data_comb;  // read_data_comb is combinational
  end
end

// Output comes from register, not combinational logic
assign read_data = read_data_reg;
```

#### Pros
- ✅ **Realistic**: Models real SRAM behavior
- ✅ **Filters glitches**: Register breaks combinational path
- ✅ **Minimal changes**: Memory module only

#### Cons
- ⚠️ **Adds latency**: Same as Options 1-3
- ⚠️ **Already tried**: Session 99 attempted this, test failed

#### Status
**Already attempted in Session 99** - test_vm_non_identity_basic failed at Stage 1 (before VM even enabled), indicating this breaks pipeline assumptions.

---

## Comparison Matrix

| Option | Complexity | Latency | Effectiveness | Risk | Time |
|--------|-----------|---------|---------------|------|------|
| 1. Register MMU Output | Low | +1 cycle | ✅ Complete | Medium | 2-3h |
| 2. Move MMU to EX | High | None | ✅ Complete | High | 4-6h |
| 3. Two-Cycle Memory | Medium | +1 cycle | ✅ Complete | Medium | 2-3h |
| 4. Address Hold | Low | None | ❌ Ineffective | Low | 1h |
| 5. Sync Memory Output | Low | +1 cycle | ⚠️ Breaks tests | Low | 1h |

---

## Recommendations

### Recommended: Option 1 (Register MMU Output)
**Why**: Best balance of simplicity, effectiveness, and risk

**Implementation Plan**:
1. Add `exmem_addr_paddr`, `exmem_addr_valid` registers
2. Update memory address mux to use registered values
3. Extend load-use hazard detection by 1 cycle
4. Test with quick regression (14 tests)
5. Verify test_vm_non_identity_basic passes

**Acceptance Criteria**:
- ✅ test_vm_non_identity_basic passes all stages
- ✅ Quick regression: 14/14 tests pass
- ✅ No glitches in simulation output
- ⚠️ CPI increase acceptable (<10%)

### Alternative: Option 2 (Move MMU to EX)
**Why**: Best long-term solution, zero latency penalty

**When to use**: If performance matters more than implementation time

**Trade-off**: Higher complexity and implementation risk

### Not Recommended
- **Option 4**: Doesn't fix the problem
- **Option 5**: Already failed in testing

---

## Implementation Steps (Option 1)

### Step 1: Add Address Pipeline Register
```verilog
// rtl/core/rv32i_core_pipelined.v, after line 2509

// Address pipeline stage to break MMU→Memory combinational path
reg [XLEN-1:0] mem_stage_paddr;      // Physical address for memory access
reg mem_stage_addr_valid;            // Translation complete
reg mem_stage_page_fault;            // Page fault detected

always @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    mem_stage_paddr <= {XLEN{1'b0}};
    mem_stage_addr_valid <= 1'b0;
    mem_stage_page_fault <= 1'b0;
  end else if (!hold_memwb && !flush_memwb) begin
    // Register translated address for next cycle
    mem_stage_paddr <= use_mmu_translation ? mmu_req_paddr : dmem_addr;
    mem_stage_addr_valid <= mmu_req_ready;
    mem_stage_page_fault <= mmu_req_page_fault;
  end
end

// Use registered address (breaks combinational path)
assign arb_mem_addr = mmu_ptw_req_valid ? mmu_ptw_req_addr : mem_stage_paddr;
```

### Step 2: Update Stall Logic
```verilog
// Stall MEM stage if translation not ready
wire mem_translation_stall = (exmem_mem_read || exmem_mem_write) &&
                             !mem_stage_addr_valid;

// Add to existing stall logic
assign stall_pc = stall_ifid | mem_translation_stall | ...;
```

### Step 3: Extend Hazard Detection
```verilog
// rtl/core/hazard_detection.v
// Extend load-use hazard by 1 cycle

// OLD: Check if EXMEM has load
// NEW: Check if EXMEM or MEMWB has load

wire load_in_mem = exmem_mem_read && exmem_valid;
wire load_in_wb = memwb_mem_read && memwb_valid;  // NEW

// Hazard if ID reads register written by load in MEM or WB
assign load_use_hazard = (load_in_mem && ...) ||
                        (load_in_wb && ...);  // NEW
```

### Step 4: Test and Verify
```bash
# Test the fix
env XLEN=32 timeout 3s ./tools/run_test_by_name.sh test_vm_non_identity_basic

# Quick regression
make test-quick

# Full VM test suite
env XLEN=32 timeout 30s ./tools/run_official_tests.sh all
```

---

## Expected Results

### Before Fix (Session 99)
```
Stage 5: Read data via VM (non-identity mapping)
  lw   t1, 0(t0)        # VA 0x90000000+0 -> should be 0xCAFEBABE
  lw   t2, 4(t0)        # VA 0x90000000+4 -> should be 0xDEADC0DE
  x6 = 0xcafebabe ✓
  x7 = 0xcafebabe ✗  (GLITCH - should be 0xdeadc0de)
```

### After Fix (Option 1)
```
Stage 5: Read data via VM (non-identity mapping)
  lw   t1, 0(t0)        # VA 0x90000000+0 -> 0xCAFEBABE
  lw   t2, 4(t0)        # VA 0x90000000+4 -> 0xDEADC0DE
  x6 = 0xcafebabe ✓
  x7 = 0xdeadc0de ✓  (FIXED - correct value)
```

### Performance Impact
```
Before: test_vm_non_identity_basic (estimated 150 cycles)
After:  test_vm_non_identity_basic (estimated 170 cycles, +13%)

Reason: Each load now takes 2 cycles instead of 1 (address then data)
```

---

## Alternative: Accept as Simulation Limitation

### Rationale
- MMU is functionally correct (Session 99 verified translation works)
- Real synthesized hardware would not have this issue
- Setup/hold time analysis prevents glitch sampling
- Clock-to-Q delays filter transient signals

### If We Accept
1. Document in `test_vm_non_identity_basic.s` as known simulation issue
2. Mark test as "functionally passes, timing artifact"
3. Continue with other 37 tests
4. Come back to architectural fix later if needed for xv6

### Trade-off
- ✅ **Fast**: Continue testing immediately
- ✅ **No risk**: No pipeline changes
- ⚠️ **Technical debt**: Issue remains
- ⚠️ **Uncertainty**: May affect other tests

---

## Questions for Decision

1. **Performance vs. Correctness**: Accept 5-10% CPI increase for clean simulation?
2. **Time vs. Completeness**: Spend 2-3 hours now or defer architectural fix?
3. **Testing Priority**: Continue with 37 other tests or fix this first?

---

## Conclusion

**Recommended Path**: Implement Option 1 (Register MMU Output)

**Reasoning**:
- Simple and effective
- Low risk (2-3 hours implementation)
- Proper architectural fix
- Ensures simulation matches hardware
- Unblocks test_vm_non_identity_basic
- Sets good foundation for remaining 37 tests

**Alternative** (if time-constrained): Accept as simulation limitation, continue testing, revisit later.

**Decision Point**: User preference between thorough fix now vs. fast progress with technical debt.
