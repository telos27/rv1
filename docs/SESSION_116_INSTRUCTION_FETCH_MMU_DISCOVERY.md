# Session 116: Critical Discovery - Instruction Fetch MMU Missing

**Date**: 2025-11-07
**Status**: 🔴 **BLOCKER IDENTIFIED** - Instruction fetch bypasses MMU completely
**Impact**: All Phase 4 tests with paging + trap handlers fail

---

## Executive Summary

Discovered a **critical architectural limitation**: instruction fetches bypass the MMU entirely, only data accesses are translated. This blocks all Phase 4 OS readiness tests and is a fundamental requirement for virtual memory support.

**Root Cause**: `rtl/core/rv32i_core_pipelined.v:2593`
```verilog
assign mmu_req_is_fetch = 1'b0;  // Data access (instruction fetch MMU in IF stage)
```

**Impact**:
- ❌ All Week 1 SUM/MXR tests fail (4 tests)
- ❌ All Week 1 VM tests fail (3 tests)
- ❌ All Week 1 TLB tests fail (3 tests)
- ❌ Trap handlers at virtual addresses cannot execute
- ❌ Instruction page faults (exception code 12) cannot occur
- ❌ Execute permission checking doesn't work
- ❌ User/supervisor privilege separation for instruction fetch broken

**Next Session**: Implement instruction fetch MMU translation (Session 117)

---

## Background: How We Got Here

### Session 108 (Nov 6, 2025)
- Fixed trap handler execution bugs in test code
- `test_vm_sum_read` and other SUM/MXR tests **PASSED**
- Tests used **identity-mapped megapages** (VA == PA for code)
- Instruction fetch worked because trap handlers were at PA == VA

### Sessions 111-115 (Nov 6, 2025)
- **Session 111**: Registered memory implementation (FPGA/ASIC-ready)
- **Session 112**: Fixed registered memory output register hold bug
- **Session 113**: Fixed M-mode MMU bypass (page faults)
- **Session 114**: Fixed bus adapter timing for registered memory
- **Session 115**: Fixed PTW memory ready protocol

### Session 116 (Nov 7, 2025) - This Session
- Attempted to debug Week 1 tests (all failing)
- Discovered instruction fetches bypass MMU completely
- Root cause: Architectural limitation, not a bug in recent changes

---

## Detailed Analysis

### What Happens Without Instruction Fetch MMU

When paging is enabled and a trap occurs:

1. **Exception triggered** at PC=0x80000134 (load page fault)
2. **Trap taken** to S-mode handler at **VA** 0x80000184
3. **PC updated** to 0x80000184 (virtual address)
4. **Instruction fetch** at PC=0x80000184:
   - Should: Translate VA 0x80000184 → PA via MMU
   - Actually: Uses 0x80000184 as **physical address** directly
   - Result: Fetches from `instruction_memory[0x184 & 0xFFF]`
5. **Problem**: Instruction memory might not have correct code at that physical offset
6. **Even worse**: No permission checking, no page faults for invalid code pages

### Why Tests Passed in Session 108

Tests used **identity-mapped megapages** covering the code region:
```
Page Table Entry 512: VA 0x80000000-0x803FFFFF → PA 0x80000000 (identity)
```

With identity mapping:
- Trap handler at **VA** 0x80000184 maps to **PA** 0x80000184
- Instruction fetch (bypassing MMU) reads **PA** 0x80000184
- Happens to be the **same** address → correct code executed
- This accidentally worked!

But this approach has critical limitations:
- Only works for identity-mapped code (VA == PA)
- Can't support OS with non-identity code mapping
- No instruction page faults possible
- No execute permission checking
- Violates RISC-V specification requirements

### Why Tests Fail Now

After Sessions 111-115 changes (registered memory, timing fixes):
- Timing behavior changed (1-cycle memory latency)
- Pipeline flush behavior may have subtle differences
- Trap handlers try to access data memory with registered timing
- Without proper instruction fetch translation, execution flow breaks

**Even with identity mapping**, there are now timing issues that expose the lack of instruction MMU.

---

## Current Architecture

### Harvard Architecture with Separate Memories

```
┌─────────────────────────────────────────────────┐
│                  CPU Core                        │
│                                                  │
│  ┌──────────┐                  ┌──────────┐     │
│  │ IF Stage │ ──PC──────────→  │   IMEM   │     │
│  │          │                  │ (4KB)    │     │
│  └──────────┘                  └──────────┘     │
│       │                                          │
│       │        ┌─────────┐                       │
│       ├────────│   MMU   │  ← ONLY USED FOR     │
│       │        │ (EX)    │    DATA ACCESS!      │
│       ↓        └─────────┘                       │
│  ┌──────────┐       │                            │
│  │ EX Stage │ ──────┴───────→  ┌──────────┐     │
│  │          │                  │   DMEM   │     │
│  └──────────┘                  │ (16KB)   │     │
│                                └──────────┘     │
└─────────────────────────────────────────────────┘

Problem: PC → IMEM path bypasses MMU completely!
```

### MMU Configuration

**File**: `rtl/core/rv32i_core_pipelined.v`

```verilog
Line 2593: assign mmu_req_is_fetch = 1'b0;  // Hardcoded to data access only!
```

**MMU Inputs** (from `mmu.v`):
```verilog
input  wire             req_is_fetch,     // 1=instruction fetch, 0=data access
```

The MMU **has support** for instruction fetch (parameter exists), but it's **never used** (hardcoded to 0).

### Historical Context

**Session 100** (Oct 2025): "MMU Moved to EX Stage"
- Moved MMU from IF to EX stage for data access
- Listed as "Future Improvement": "Implement instruction-side MMU (IMMU) for IF stage"
- Never implemented - deferred for later

**Why it was deferred**:
1. All tests used identity-mapped code (VA == PA)
2. Data MMU was higher priority
3. Adding instruction MMU is complex (adds latency to fetch)

---

## RISC-V Specification Requirements

From **RISC-V Privileged Spec v1.12** (Chapter 4: Virtual Memory):

### Mandatory Translation for Both Fetch and Data

> "When `satp.MODE` specifies a translation mode, **supervisor and user memory accesses**
> are translated and protected, and **instruction fetches** are translated and protected."

### Page Fault Types

The spec defines three page fault types:
- **Code 12**: Instruction page fault (fetch from invalid/inaccessible page)
- **Code 13**: Load page fault (read from invalid/inaccessible page)
- **Code 15**: Store page fault (write to invalid/inaccessible page)

**Current RV1 Status**:
- ✅ Code 13 (load page fault): Works correctly
- ✅ Code 15 (store page fault): Works correctly
- ❌ Code 12 (instruction page fault): **Cannot occur** (fetch bypasses MMU)

### Permission Bits Applied to Instruction Fetch

Page Table Entry (PTE) permissions must be checked for instruction fetch:
- **X bit**: Execute permission (fetch from X=0 page should fault)
- **U bit**: User/supervisor separation (S-mode fetch from U-page with SUM=0 should fault)
- **V bit**: Valid (fetch from V=0 page should fault)

**Current RV1 Status**: None of these checks happen for instruction fetch!

---

## Test Failures Explained

### Example: `test_sum_disabled`

**Test Setup**:
1. Create page table with user-accessible page (U=1) at VA 0x00010000
2. Identity-map supervisor code at VA 0x80000000 (megapage, U=0)
3. Enable paging (SATP)
4. Enter S-mode with SUM=0
5. Try to load from VA 0x00010000 (should trigger page fault)
6. Trap handler at VA 0x80000184 should catch fault

**Expected Behavior**:
1. Load triggers page fault (code 13) ✅ **Works**
2. Trap to S-mode handler at VA 0x80000184 ✅ **PC updated**
3. **Fetch instructions from VA 0x80000184** ❌ **FAILS HERE**
   - Should: MMU translates VA 0x80000184 → PA (megapage)
   - Actually: CPU fetches from PA 0x80000184 directly (no MMU)
4. Trap handler modifies SEPC to skip faulting instruction
5. SRET returns to modified PC
6. Test continues and passes

**What Actually Happens**:
1. Load triggers page fault ✅
2. PC set to 0x80000184 ✅
3. **Instruction fetch at 0x80000184 bypasses MMU** ❌
4. With registered memory timing, fetch fails or reads wrong data
5. Trap handler doesn't execute properly
6. Exception repeats infinitely or test times out

**Debug Trace**:
```
[EXCEPTION] Load page fault: PC=0x80000134, VA=0x00010000
[TRAP] Taking trap to priv=01, cause=13, PC=0x80000134 saved to SEPC
[PC_UPDATE] TRAP: pc_current=0x80000140 -> pc_next=0x80000184
[EXCEPTION] Load page fault: PC=0x80000134, VA=0x00010000  ← REPEATS!
[EXCEPTION] Load page fault: PC=0x80000134, VA=0x00010000  ← INFINITE LOOP
```

The trap handler never executes, and the faulting instruction keeps repeating.

---

## Why This Blocks Phase 4

### xv6 Requirements

xv6 (and any real OS) requires:
1. **Non-identity virtual memory**: Code/data at different VAs than PAs
2. **Trap handlers at virtual addresses**: Kernel trap vector in virtual address space
3. **Page fault recovery**: Handle instruction page faults for demand paging
4. **Execute permission**: Prevent execution of data pages (W^X security)
5. **User/supervisor isolation**: U-mode can't execute S-mode code pages

**None of these work without instruction fetch MMU!**

### Week 1 Test Status (11 tests)

| Test Category | Tests | Status | Blocker |
|---------------|-------|--------|---------|
| SUM/MXR Permission | 4 | ❌ FAIL | No instruction fetch MMU |
| Non-Identity VM | 3 | ❌ FAIL | No instruction fetch MMU |
| TLB Verification | 3 | ❌ FAIL | No instruction fetch MMU |

**Week 1 Total**: 0/11 tests passing (was 11/11 in Session 108 with identity mapping)

---

## Solution: Implement Instruction Fetch MMU (IMMU)

### Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                     CPU Core                             │
│                                                          │
│  ┌──────────┐        ┌─────────┐      ┌──────────┐      │
│  │ IF Stage │ ──VA──→│  IMMU   │ ─PA─→│   IMEM   │      │
│  │          │        │ (TLB)   │      │ (4KB)    │      │
│  └──────────┘        └─────────┘      └──────────┘      │
│       ↓                   │                              │
│  ┌──────────┐        ┌─────────┐                        │
│  │ ID Stage │        │  Shared │                        │
│  └──────────┘        │   TLB   │                        │
│       ↓              │  (16)   │                        │
│  ┌──────────┐        └─────────┘                        │
│  │ EX Stage │ ──VA──→│  DMMU   │ ─PA─→┌──────────┐      │
│  │          │        │ (Share) │      │   DMEM   │      │
│  └──────────┘        └─────────┘      │ (16KB)   │      │
│                                        └──────────┘      │
└─────────────────────────────────────────────────────────┘

Solution: Add IMMU for instruction fetch translation
```

### Implementation Plan (Next Session)

See: `docs/INSTRUCTION_FETCH_MMU_IMPLEMENTATION_PLAN.md`

**Key Components**:
1. Add instruction fetch MMU in IF stage (combinational TLB lookup)
2. Share TLB between IMMU and DMMU (unified 16-entry TLB)
3. Handle TLB miss with stall + page table walk
4. Add instruction page fault exception (code 12)
5. Update pipeline control for fetch stalls

**Estimated Effort**: 1-2 sessions (4-8 hours)

**Risk**: Medium - impacts critical path (instruction fetch timing)

---

## Conclusion

This session identified a **critical architectural limitation** that blocks Phase 4 OS readiness. While the recent registered memory changes (Sessions 111-115) exposed the issue, the root cause is that **instruction fetch MMU was never implemented**.

**The Fix**: Not optional - must implement instruction fetch MMU translation per RISC-V spec.

**Next Session**: Implement instruction fetch MMU (Session 117)

**Lessons Learned**:
1. Identity-mapped tests can hide architectural bugs
2. Virtual memory requires BOTH instruction and data translation
3. Deferred features can become critical blockers later
4. The RISC-V spec is not optional - all requirements must be met

---

## References

- **RISC-V Privileged Spec v1.12**: Chapter 4 (Virtual Memory)
- **Session 100**: MMU moved to EX stage, IMMU listed as "future improvement"
- **Session 108**: Trap handler tests passing with identity mapping
- **Sessions 111-115**: Registered memory implementation + fixes
- **Next**: `docs/INSTRUCTION_FETCH_MMU_IMPLEMENTATION_PLAN.md`
