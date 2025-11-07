# Instruction Fetch MMU Implementation Plan

**Date**: 2025-11-07
**Session**: 117 (next session)
**Estimated Effort**: 1-2 sessions (4-8 hours)
**Priority**: 🔴 **CRITICAL BLOCKER** for Phase 4

---

## Overview

Implement instruction fetch address translation through MMU to enable proper virtual memory support. This is a **mandatory RISC-V feature** currently missing from RV1.

**Goal**: All instruction fetches go through MMU when paging is enabled, with proper permission checks and page fault handling.

---

## Design Options

### Option 1: Separate IMMU and DMMU (Traditional Approach)

**Architecture**:
```
IF Stage: IMMU with dedicated 8-entry I-TLB
EX Stage: DMMU with dedicated 8-entry D-TLB
Total: 16 TLB entries (8+8)
```

**Pros**:
- True Harvard architecture
- No contention between fetch and data access
- Simpler control logic
- Each TLB optimized for its access pattern

**Cons**:
- More hardware (2 MMU instances, 2 TLBs)
- TLB entries not shared (less efficient utilization)
- More complex SFENCE.VMA (must flush both TLBs)
- Higher area cost

### Option 2: Unified TLB with Shared MMU (Recommended)

**Architecture**:
```
Shared: Single 16-entry TLB accessed by both IF and EX
IF Stage: Combinational lookup for I-fetch
EX Stage: Combinational lookup for data access
PTW: Arbitrated between IF and EX stage misses
```

**Pros**:
- Better TLB utilization (16 entries shared intelligently)
- Single TLB to flush on SFENCE.VMA
- Less area (one TLB, one MMU)
- Modern CPUs use this approach (Intel, ARM)

**Cons**:
- Need arbitration for TLB access
- Need arbitration for PTW
- Slightly more complex control logic

**Decision**: **Option 2** (Unified TLB) - better resource utilization, matches modern architectures

---

## Detailed Implementation Plan

### Phase 1: Add Instruction Fetch MMU Signals (30-60 min)

**File**: `rtl/core/rv32i_core_pipelined.v`

#### 1.1 Add IF Stage MMU Request Signals

**Location**: Around line 450 (near existing MMU signals)

```verilog
// Instruction fetch MMU signals
wire            if_mmu_req_valid;
wire [XLEN-1:0] if_mmu_req_vaddr;
wire            if_mmu_req_ready;
wire [XLEN-1:0] if_mmu_req_paddr;
wire            if_mmu_req_page_fault;
wire [XLEN-1:0] if_mmu_req_fault_vaddr;

// Data access MMU signals (existing - rename for clarity)
wire            ex_mmu_req_valid;
wire [XLEN-1:0] ex_mmu_req_vaddr;
wire            ex_mmu_req_is_store;
wire            ex_mmu_req_ready;
wire [XLEN-1:0] ex_mmu_req_paddr;
wire            ex_mmu_req_page_fault;
wire [XLEN-1:0] ex_mmu_req_fault_vaddr;
```

#### 1.2 Add TLB Arbitration Logic

**Location**: Before MMU instantiation (around line 2600)

```verilog
// TLB Arbitration: Priority to instruction fetch (IF before EX in pipeline)
// Both IF and EX can request TLB lookup in the same cycle
// IF gets priority to avoid stalling fetch

wire if_needs_translation = satp_mode_enabled && (current_priv != 2'b11);
wire ex_needs_translation = satp_mode_enabled && (current_priv != 2'b11) &&
                            (idex_mem_read || idex_mem_write);

assign if_mmu_req_valid = if_needs_translation && !stall_pc;
assign if_mmu_req_vaddr = pc_current;

assign ex_mmu_req_valid = ex_needs_translation && !if_mmu_req_valid;
assign ex_mmu_req_vaddr = dmem_addr;
assign ex_mmu_req_is_store = idex_mem_write;

// Multiplex MMU request (IF has priority)
wire            mmu_req_valid   = if_mmu_req_valid || ex_mmu_req_valid;
wire [XLEN-1:0] mmu_req_vaddr   = if_mmu_req_valid ? if_mmu_req_vaddr : ex_mmu_req_vaddr;
wire            mmu_req_is_store = if_mmu_req_valid ? 1'b0 : ex_mmu_req_is_store;
wire            mmu_req_is_fetch = if_mmu_req_valid;
wire [2:0]      mmu_req_size    = if_mmu_req_valid ? 3'b010 : idex_funct3;

// Demultiplex MMU response
assign if_mmu_req_ready      = if_mmu_req_valid && mmu_req_ready;
assign if_mmu_req_paddr      = mmu_req_paddr;
assign if_mmu_req_page_fault = if_mmu_req_valid && mmu_req_page_fault;
assign if_mmu_req_fault_vaddr = mmu_req_fault_vaddr;

assign ex_mmu_req_ready      = ex_mmu_req_valid && mmu_req_ready;
assign ex_mmu_req_paddr      = mmu_req_paddr;
assign ex_mmu_req_page_fault = ex_mmu_req_valid && mmu_req_page_fault;
assign ex_mmu_req_fault_vaddr = mmu_req_fault_vaddr;
```

### Phase 2: Update Instruction Memory Access (30 min)

**File**: `rtl/core/rv32i_core_pipelined.v`

#### 2.1 Use Translated Address for Instruction Fetch

**Location**: Around line 785 (instruction memory instantiation)

**Current**:
```verilog
instruction_memory #(
  .XLEN(XLEN),
  .MEM_SIZE(IMEM_SIZE),
  .MEM_FILE(MEM_FILE)
) imem (
  .clk(clk),
  .addr(pc_current),  // Direct physical address - WRONG!
  .instruction(if_instruction_raw),
  ...
);
```

**New**:
```verilog
// Select address for instruction fetch
// When paging enabled and MMU ready: use translated address
// Otherwise: use PC directly (bare mode or M-mode)
wire [XLEN-1:0] if_fetch_addr = (if_needs_translation && if_mmu_req_ready) ?
                                 if_mmu_req_paddr :
                                 pc_current;

instruction_memory #(
  .XLEN(XLEN),
  .MEM_SIZE(IMEM_SIZE),
  .MEM_FILE(MEM_FILE)
) imem (
  .clk(clk),
  .addr(if_fetch_addr),  // Use translated address!
  .instruction(if_instruction_raw),
  ...
);
```

### Phase 3: Add Instruction Page Fault Handling (60-90 min)

**File**: `rtl/core/exception_unit.v` (or in main core file)

#### 3.1 Add Instruction Page Fault Exception Code

**Location**: Exception code definitions (around line 500)

```verilog
// Exception codes
parameter [4:0] CAUSE_INSTRUCTION_PAGE_FAULT = 5'd12;
parameter [4:0] CAUSE_LOAD_PAGE_FAULT        = 5'd13;
parameter [4:0] CAUSE_STORE_PAGE_FAULT       = 5'd15;
```

#### 3.2 Add IF Stage Exception Signals

**Location**: IF/ID pipeline register inputs

```verilog
// IF stage exception tracking
reg             if_page_fault_r;
reg [XLEN-1:0]  if_page_fault_vaddr_r;

always @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    if_page_fault_r <= 1'b0;
    if_page_fault_vaddr_r <= {XLEN{1'b0}};
  end else if (!stall_pc && !flush_ifid) begin
    if_page_fault_r <= if_mmu_req_page_fault;
    if_page_fault_vaddr_r <= if_mmu_req_fault_vaddr;
  end else if (flush_ifid) begin
    if_page_fault_r <= 1'b0;
  end
end
```

#### 3.3 Propagate Through Pipeline

Add to IF/ID register:
```verilog
.page_fault_in(if_page_fault_r),
.page_fault_vaddr_in(if_page_fault_vaddr_r),
```

Add to exception priority logic:
```verilog
// Exception priority (RISC-V spec Table 3.6)
// Instruction page fault (code 12) has higher priority than load/store faults
wire exception_if_page_fault = ifid_page_fault && ifid_valid;
wire exception_mem_page_fault = (exmem_page_fault && !trap_flush_r && translation_enabled);

assign exception = exception_if_page_fault ||
                   exception_mem_page_fault ||
                   ... // other exceptions

assign exception_code = exception_if_page_fault ? CAUSE_INSTRUCTION_PAGE_FAULT :
                        exception_mem_page_fault ? (exmem_is_store ? CAUSE_STORE_PAGE_FAULT : CAUSE_LOAD_PAGE_FAULT) :
                        ... // other codes
```

### Phase 4: Pipeline Stall for TLB Miss (60-90 min)

#### 4.1 Detect Instruction Fetch Stall Condition

**Location**: Pipeline control signals

```verilog
// Stall IF stage when:
// 1. Instruction fetch needs translation AND
// 2. MMU is not ready (TLB miss, PTW in progress)
wire if_translation_stall = if_needs_translation && if_mmu_req_valid && !if_mmu_req_ready;

// Update stall_pc to include instruction fetch stalls
assign stall_pc = load_use_hazard ||
                  mmu_busy ||  // Existing: data access PTW
                  if_translation_stall ||  // New: instruction fetch PTW
                  pc_stall_gated;
```

#### 4.2 Handle PTW Arbitration

**Location**: MMU PTW arbiter

```verilog
// PTW Arbitration: IF stage has priority (avoid fetch stall if possible)
// But if data access PTW already in progress, let it complete
reg ptw_for_ifetch_r;  // Track which request triggered PTW

always @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    ptw_for_ifetch_r <= 1'b0;
  end else begin
    if (mmu_ptw_req_valid && !mmu_ptw_req_ready) begin
      // PTW starting - remember if it's for instruction fetch
      ptw_for_ifetch_r <= if_mmu_req_valid;
    end else if (mmu_ptw_resp_valid) begin
      // PTW complete
      ptw_for_ifetch_r <= 1'b0;
    end
  end
end
```

### Phase 5: Update MMU Module (30 min)

**File**: `rtl/core/mmu.v`

#### 5.1 Change from Single Request to Arbitrated Requests

**Current interface** (single requestor):
```verilog
input  wire             req_valid,
input  wire [XLEN-1:0]  req_vaddr,
input  wire             req_is_store,
input  wire             req_is_fetch,
```

**Keep same interface** - arbiter in main core handles multiplexing!
The MMU doesn't need to change internally, just:

```verilog
Line 2593: assign mmu_req_is_fetch = 1'b0;  // OLD

// NEW: Wire from arbiter
// (Already handled in Phase 1)
```

Actually, **no MMU module changes needed** if arbiter is in the core!

### Phase 6: Testing and Validation (60-120 min)

#### 6.1 Test Sequence

**Test 1**: Simple identity-mapped fetch
```assembly
# Enable paging with identity mapping
# Execute a few instructions
# Verify TLB hit for instruction fetch
```

**Test 2**: Non-identity instruction mapping
```assembly
# Map VA 0x10000 → PA 0x80000000 (code)
# Jump to VA 0x10000
# Execute instructions
# Verify translation works
```

**Test 3**: Instruction page fault
```assembly
# Create PTE with V=0
# Jump to invalid page
# Verify instruction page fault (code 12)
# Trap handler fixes PTE
# Retry and succeed
```

**Test 4**: Execute permission check
```assembly
# Create PTE with X=0, R=1
# Try to fetch from that page
# Verify instruction page fault
```

**Test 5**: Existing Week 1 tests
```bash
env XLEN=32 timeout 3s ./tools/run_test_by_name.sh test_sum_disabled
env XLEN=32 timeout 3s ./tools/run_test_by_name.sh test_sum_enabled
# ... all 11 Week 1 tests
```

#### 6.2 Validation Checklist

- [ ] Instruction fetch TLB hits work (0-cycle latency)
- [ ] Instruction fetch TLB misses trigger PTW correctly
- [ ] PTW for instruction fetch completes and fills TLB
- [ ] Instruction page faults (code 12) are raised correctly
- [ ] Execute permission (X bit) is checked
- [ ] User/supervisor bit (U bit) is checked for fetch
- [ ] SFENCE.VMA flushes instruction TLB entries
- [ ] M-mode bypasses instruction translation
- [ ] Trap handlers at virtual addresses execute correctly
- [ ] All 11 Week 1 tests pass
- [ ] Quick regression passes (14/14 tests)
- [ ] No performance regression (CPI should be similar)

---

## Performance Implications

### Expected Performance Impact

**TLB Hit** (best case): 0 cycles added
- Combinational lookup in parallel with PC increment
- Same as current direct fetch

**TLB Miss** (worst case): 3-5 cycles added
- 1 cycle: Detect miss, stall pipeline
- 1-2 cycles: PTW level 1 read (registered memory)
- 1-2 cycles: PTW level 0 read (registered memory)
- 1 cycle: Fill TLB, resume

**Typical Case**:
- Instruction locality is high (code executes sequentially)
- TLB hit rate should be >99% for most programs
- Average CPI impact: <0.01 cycles

### TLB Sizing

**Current**: 16 entries (unified for data + instruction)

**Analysis**:
- Instruction working set: Typically 4-8 pages (16-32 KB of code)
- Data working set: Typically 4-8 pages (16-32 KB of data)
- 16 entries shared should handle most cases

**Recommendation**: Keep 16 entries, monitor TLB miss rate
- If miss rate >5%: Consider increasing to 32 entries
- If shared contention is high: Consider split I/D TLBs

---

## Risk Assessment

### Risk 1: Instruction Fetch Timing Path

**Risk**: Adding MMU to IF stage might create critical path

**Mitigation**:
- TLB lookup is combinational (already fast in current MMU)
- Can add pipeline register if needed (increases latency by 1 cycle)
- Test timing after implementation

**Likelihood**: Low (MMU is already optimized)

### Risk 2: Pipeline Stall Complexity

**Risk**: Stalling IF stage might interact badly with existing hazards

**Mitigation**:
- Careful integration with existing stall logic
- Thorough testing of corner cases
- Use existing load-use hazard stall as template

**Likelihood**: Medium (pipeline control is complex)

### Risk 3: TLB Contention

**Risk**: IF and EX both accessing TLB might cause conflicts

**Mitigation**:
- IF has priority (earlier in pipeline)
- EX can wait 1 cycle without performance impact (already has EXMEM register)
- Monitor contention rate during testing

**Likelihood**: Low (temporal separation in pipeline)

### Risk 4: PTW Arbitration Bugs

**Risk**: Arbitrating PTW between IF and EX might have corner cases

**Mitigation**:
- Clear priority scheme (IF > EX)
- Only one PTW active at a time
- Test with concurrent IF and EX misses

**Likelihood**: Medium (arbitration is always tricky)

---

## Implementation Checklist

### Session 117 Tasks

- [ ] Phase 1: Add IF MMU signals and arbiter (30-60 min)
- [ ] Phase 2: Update instruction memory to use translated address (30 min)
- [ ] Phase 3: Add instruction page fault handling (60-90 min)
- [ ] Phase 4: Add pipeline stall for TLB miss (60-90 min)
- [ ] Phase 5: Verify MMU module (30 min)
- [ ] Phase 6: Testing and validation (60-120 min)
- [ ] Documentation: Update SESSION_117 with implementation details
- [ ] Git commit: "Session 117: Implement instruction fetch MMU"

**Total Estimated Time**: 4-7 hours (1-2 sessions)

### Success Criteria

✅ All 11 Week 1 Phase 4 tests pass
✅ Instruction page faults (code 12) work correctly
✅ Quick regression passes (14/14)
✅ No significant performance regression (CPI < 1.5)
✅ Code review: Clean, well-documented, follows existing patterns

---

## Alternative Approaches (If Time Constrained)

### Minimal Implementation (Quick Fix)

If time is limited, could implement a **simpler version**:

1. **Single unified MMU** (keep current architecture)
2. **Add IF stage lookup** (before PC fetch)
3. **Stall on miss** (simple logic)
4. **Skip instruction page faults** (only translate, don't fault)

This would make tests pass but wouldn't be fully RISC-V compliant.

**Not recommended** - better to do it right the first time.

---

## Post-Implementation

### After Session 117

1. **Run full test suite**
   - Quick regression (14 tests)
   - Week 1 Phase 4 tests (11 tests)
   - RV32 compliance (79 tests)
   - Custom tests (231 tests)

2. **Performance analysis**
   - Measure TLB hit/miss rates
   - Check CPI impact
   - Identify any hotspots

3. **Documentation**
   - Update ARCHITECTURE.md with IMMU details
   - Update CLAUDE.md with current status
   - Create SESSION_117 summary

4. **Continue Phase 4**
   - Move to Week 2 tests (page fault recovery, syscalls)
   - Progress toward xv6 readiness

---

## References

- **RISC-V Privileged Spec v1.12**: Chapter 4.3 (Virtual Address Translation)
- **Session 100**: MMU architecture and TLB design
- **Session 116**: Discovery of missing instruction fetch MMU
- **MIT 6.175**: RISC-V Processor Implementation (has good IMMU examples)
- **BOOM (Berkeley Out-of-Order Machine)**: Reference RISC-V implementation

---

## Questions to Resolve During Implementation

1. **TLB entry format**: Does it need separate I/D tracking?
   - Likely no - permissions apply to both

2. **SFENCE.VMA with RS1/RS2**: Does it flush both I and D entries?
   - Yes - spec says "all" entries

3. **Compressed instructions**: Do they still work with translation?
   - Yes - translation is before fetch, not after

4. **Cross-page fetches**: What if instruction spans page boundary?
   - RISC-V spec: Instructions don't span pages (alignment requirement)
   - 4-byte instructions must be 4-byte aligned
   - Compressed can be at any 2-byte boundary within page

5. **M-mode fetch bypass**: Does M-mode instruction fetch bypass MMU?
   - Yes - M-mode ignores paging per spec

---

## Conclusion

Implementing instruction fetch MMU is **non-optional** for Phase 4. The plan above provides a clear, step-by-step approach that:

1. Follows RISC-V specification requirements
2. Uses modern unified TLB architecture
3. Integrates cleanly with existing pipeline
4. Has manageable risk and complexity
5. Can be completed in 1-2 sessions

**Next Session (117)**: Execute this plan and unblock Phase 4!
