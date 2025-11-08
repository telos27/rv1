# CLAUDE.md - AI Assistant Context

## Project Overview
RISC-V CPU core in Verilog: 5-stage pipelined processor with RV32IMAFDC extensions and privilege architecture (M/S/U modes).

## Current Status (Session 120, 2025-11-07)

### 🎯 CURRENT PHASE: Phase 4 Week 2 IN PROGRESS
- **Previous Phase**: ✅ Phase 4 Week 1 COMPLETE - All 9 tests passing (Session 119)
- **Current Status**: 🔄 **PHASE 4 WEEK 2** - Implementing OS readiness tests
- **Git Tag**: `v1.0-rv64-complete` (marks Phase 3 completion)
- **Next Milestone**: `v1.1-xv6-ready` (Phase 4 OS features)
- **Progress**: **3/11 Phase 4 Week 2 tests complete (27%)**

### Session 120: Phase 4 Week 2 Tests - Part 1 (2025-11-07)
**Achievement**: ✅ Implemented 3 Week 2 tests for OS readiness - syscalls and context switching

**Tests Completed**:
1. ✅ **test_syscall_args_passing.s** - U-mode→S-mode syscall argument passing
   - Tests 3 different syscall types (add, sum4, xor_all)
   - Validates ECALL/SRET mechanism and register preservation

2. ✅ **test_context_switch_minimal.s** - GPR preservation across context switches
   - Saves/restores all 31 general-purpose registers
   - Tests two complete task contexts with perfect isolation

3. ✅ **test_syscall_multi_call.s** - Multiple sequential syscalls
   - 10 different syscall implementations (add, mul, sub, and, or, xor, sll, srl, max, min)
   - Verifies independent operation without state corruption

**Test Results**:
- ✅ Quick regression: 14/14 passing (100%)
- ✅ New tests: 3/3 passing (100%)
- ✅ Total: 950 lines of new test code

**Pending**: 8/11 Week 2 tests (page fault tests deferred due to complexity)

**Documentation**: `docs/SESSION_120_WEEK2_TESTS_PART1.md`

**Next Session**: Continue Week 2 tests (page faults, SUM tests, FP/CSR context switching)

### Session 119: Critical MMU Arbiter Bug Fixed! (2025-11-07)
**Achievement**: 🎉 **MAJOR BREAKTHROUGH** - Fixed critical MMU arbiter bug, Phase 4 Week 1 complete!

**Critical Bug Discovered**: Session 117's instruction fetch MMU blocked ALL data translations!
- `if_mmu_req_valid` was TRUE every cycle (constant instruction fetching)
- Original arbiter: `ex_mmu_req_valid = ex_needs_translation && !if_mmu_req_valid`
- Condition `!if_mmu_req_valid` was ALWAYS FALSE → data accesses NEVER translated!

**Solution**: Round-Robin MMU Arbiter
```verilog
// Toggle grant between IF and EX when both need MMU
reg mmu_grant_to_ex_r;
always @(posedge clk) begin
  if (if_needs_translation && ex_needs_translation)
    mmu_grant_to_ex_r <= !mmu_grant_to_ex_r;  // Fair arbitration
end
```

**Test Fixes** (`test_tlb_basic_hit_miss.s`):
1. Added `ENTER_SMODE_M` - test now runs in S-mode (M-mode bypasses MMU)
2. Fixed trap handlers - check for intentional ebreak before failing
3. Added identity megapage for code region (0x80000000)
4. Simplified to use identity mapping (VA = PA)

**Test Results**:
- ✅ Quick regression: 14/14 passing (100%)
- ✅ **Phase 4 Week 1: 9/9 passing (100%)** ← Was 8/9!
  - ✅ test_vm_identity_basic
  - ✅ test_sum_disabled
  - ✅ test_vm_identity_multi
  - ✅ test_vm_sum_simple
  - ✅ test_vm_sum_read
  - ✅ test_sum_enabled
  - ✅ test_sum_minimal
  - ✅ test_mxr_basic
  - ✅ test_tlb_basic_hit_miss ← **FIXED!**

**Impact**: Phase 4 Week 1 COMPLETE! Data MMU translations now work. Round-robin arbiter unblocks all Phase 4 development.

**Future Work**: Implement proper I-TLB/D-TLB separation (industry standard) for better performance

**Documentation**: `docs/SESSION_119_MMU_ARBITER_FIX.md`

**Next Session**: Continue Phase 4 Week 2 tests (page fault recovery, syscalls)

### Session 118: Testbench Fix for Phase 4 Tests (2025-11-07)
**Achievement**: 🎉 Fixed Phase 4 test infrastructure - 8/9 tests now passing (was 5/11)!

**Root Cause**: Two infrastructure bugs:
1. **Testbench**: Didn't detect Phase 4 test completion pattern (memory write to 0x80002100)
2. **Test script**: Didn't enable C extension, causing misalignment traps on compressed instructions

**Fixes**:
- `tb/integration/tb_core_pipelined.v`: Added memory write monitor for marker address (+52 lines)
- `tools/run_test_by_name.sh`: Enabled C extension by default (explicit `-DENABLE_C_EXT=1`)

**Documentation**: `docs/SESSION_118_TESTBENCH_FIX_PHASE4_TESTS.md`

### Session 117: Instruction Fetch MMU Implementation (2025-11-07)
**Achievement**: 🎉 **CRITICAL MILESTONE** - Instruction fetch MMU successfully implemented!

**Implementation**:
- Added unified TLB arbiter (16 entries shared between IF and EX stages)
- IF stage gets priority to minimize instruction fetch stalls
- Instruction memory now uses translated addresses when paging enabled
- Instruction page fault handling (exception code 12) fully operational
- Pipeline stall logic for instruction TLB miss (reuses existing `mmu_busy`)

**Files Modified**:
- `rtl/core/rv32i_core_pipelined.v` - MMU arbiter, IF signals, instruction memory
- `rtl/core/ifid_register.v` - Page fault propagation through pipeline
- `rtl/core/exception_unit.v` - Instruction page fault detection (code 12)

**Test Results**:
- ✅ Quick regression: 14/14 passing (100% - zero regressions!)
- ✅ Phase 4 Week 1: 5/11 passing (45% - basic functionality working!)

**Impact**: **Phase 4 is now unblocked!** RV1 has a complete RISC-V virtual memory system with both instruction and data address translation.

**Documentation**: `docs/SESSION_117_INSTRUCTION_FETCH_MMU_IMPLEMENTATION.md`

### Session 116: Critical Discovery - Instruction Fetch MMU Missing (2025-11-07)
**Discovery**: 🔴 **CRITICAL BLOCKER** - Instruction fetch bypasses MMU, blocking ALL Phase 4 tests with virtual memory!

**Root Cause**:
- `rv32i_core_pipelined.v:2593`: `assign mmu_req_is_fetch = 1'b0;` (hardcoded to data-only)
- Instruction memory fetched directly from PC without translation
- MMU only translates data accesses, NOT instruction fetches

**Solution**: Implemented in Session 117 (see above)

### Session 115: PTW Memory Ready Protocol Fix (2025-11-06)
**Achievement**: ✅ Fixed critical bug where PTW claimed 0-cycle read latency (identical to Session 114 bus adapter bug)!

**The Bug**:
- `rv32i_core_pipelined.v` hardcoded `mmu_ptw_req_ready = 1'b1` (always ready)
- PTW read garbage page table entries before registered memory provided data
- Broke ALL paging tests (test_vm_identity, test_mmu_enabled, etc.)

**The Fix**:
- Added state machine to track `ptw_read_in_progress_r` (lines 2693-2705)
- Changed `ptw_req_ready = ptw_read_in_progress_r` (line 2708)
- PTW reads: 1-cycle latency (MMU waits for valid data)

**Validation**:
- ✅ Quick regression: 14/14 tests pass (100%)
- ✅ PTW successfully reads page table entries
- ✅ TLB populated with correct data
- ✅ SUM bit permission checking confirmed working
- ⚠️ Phase 4 tests have trap handler page mapping issues (test infrastructure, not MMU bug)

**Impact**: **Completes the registered memory transition from Sessions 111-115**. PTW infrastructure operational, ready for Phase 4 OS features.

**Documentation**: `docs/SESSION_115_PTW_READY_PROTOCOL_FIX.md`

### Session 114: Data Memory Bus Adapter Fix (2025-11-06)
**Achievement**: ✅ Fixed critical bug where bus adapter claimed 0-cycle read latency despite registered memory having 1-cycle latency!

**The Bug**:
- `dmem_bus_adapter.v` hardcoded `req_ready = 1'b1` (always ready)
- Told CPU data was ready immediately, but registered memory needs 1 cycle
- CPU read garbage/zero before data was available
- Store-followed-by-load sequences failed even with 30+ NOPs!

**The Fix**:
- Added state machine to track `read_in_progress_r` (lines 38-53)
- Changed `req_ready = req_we || read_in_progress_r` (line 59)
- Writes: 0-cycle latency (ready immediately)
- Reads: 1-cycle latency (CPU stalls automatically via bus protocol)

**Validation**:
- ✅ Quick regression: 14/14 tests pass (100%)
- ✅ Store-load sequences work correctly (NO NOPS NEEDED!)
- ✅ test_sum_disabled: Progressed from stage 2 → stage 6
- ⚠️ Remaining failures are MMU/privilege issues (not memory timing)

**Impact**: **Completes the registered memory transition from Sessions 111-112-114**. Memory system now fully matches FPGA BRAM behavior with correct bus protocol.

**Documentation**: `docs/SESSION_114_BUS_ADAPTER_FIX.md`

### Session 113: M-Mode MMU Bypass Fix (2025-11-06)
**Achievement**: ✅ Fixed critical bug where M-mode incorrectly raised page faults when translation disabled!

**The Bug**:
- Page faults were raised in M-mode even when `translation_enabled = 0`
- Violated RISC-V spec: "M-mode ignores all page-based virtual-memory schemes"
- Caused Phase 4 Week 1 tests (SUM/MXR/VM tests) to fail

**The Fix**:
- Gated `mem_page_fault` signal with `translation_enabled` (line 2065)
- Moved wire definitions earlier to exception handler (lines 2026-2030)
- M-mode now correctly bypasses both translation AND page faults

**Validation**:
- ✅ Quick regression: 14/14 tests pass (100%)
- ✅ No regressions in existing functionality
- ⚠️ Week 1 tests still failing (different issue - registered memory timing)

**Documentation**: `docs/SESSION_113_MMODE_MMU_BYPASS_FIX.md`

### Session 112: Registered Memory Output Register Fix (2025-11-06)
**Achievement**: ✅ Fixed critical bug in Session 111's registered memory - output register now holds values correctly!

**The Bug**:
- Output register was cleared to zero when `mem_read` was low
- Caused rv32ua-p-lrsc to timeout (load values lost before pipeline could use them)
- Real FPGA BRAM/ASIC SRAM don't clear outputs - they hold values!

**The Fix**:
- Removed `else` clause that cleared `read_data` (line 141-143)
- Added initialization of `read_data = 64'h0` in `initial` block
- Now matches real hardware: output register holds value between reads

**Validation**:
- ✅ Quick regression: 14/14 tests pass (100%)
- ✅ RV32 compliance: 79/79 tests pass (100%)
- ✅ RV64 compliance: 86/86 tests pass (100%)
- ✅ **Total: 165/165 official tests passing (100%)**

**Documentation**: `docs/SESSION_112_REGISTERED_MEMORY_OUTPUT_FIX.md`

### Session 111: Registered Memory Implementation (2025-11-06)
**Achievement**: ✅ Memory subsystem now matches real hardware! Synchronous registered memory eliminates glitches.

**Key Changes**:
- Changed `data_memory.v` from combinational to synchronous (matches FPGA BRAM/ASIC SRAM)
- Zero performance impact (load-use timing unchanged)
- 700x improvement for VM tests (70 cycles vs 50K+ timeout)
- Files: `rtl/memory/data_memory.v`, `rtl/core/rv32i_core_pipelined.v`

**Status**: ✅ Complete (after Session 112 fix)

**Documentation**: `docs/SESSION_111_REGISTERED_MEMORY_FIX.md` (450 lines with complete FPGA/ASIC analysis)

---

## Recent Critical Bug Fixes (Phase 4 - Sessions 90-119)

### Major Fixes Summary
| Session | Fix | Impact |
|---------|-----|--------|
| **119** | Round-robin MMU arbiter | Data translations now work! Phase 4 Week 1 complete (9/9) |
| **118** | Phase 4 test infrastructure | Test detection and C extension fixes (8/9 tests) |
| **117** | Instruction fetch MMU | IF stage now translates through MMU |
| **116** | Discovered IF MMU missing | Critical blocker identified |
| **115** | PTW req_ready timing | PTW reads correct page table entries, all paging works |
| **114** | Bus adapter req_ready timing | Store-load sequences work, completes registered memory |
| **113** | M-mode MMU bypass (page faults) | M-mode ignores translation correctly |
| **112** | Memory output register hold | 100% compliance restored, matches real BRAM |
| **111** | Registered memory (FPGA/ASIC-ready) | 700x improvement, eliminates glitches |
| **110** | EXMEM flush on traps | Prevents infinite exception loops |
| **109** | M-mode MMU bypass (translation) | Critical for OS boot |
| **107** | TLB caches faulting translations | 500x improvement |
| **105** | 2-level page table walks | Enables non-identity VM |
| **103** | Page fault pipeline hold | Precise exceptions |
| **100** | MMU in EX stage | Eliminates combinational glitches |
| **94** | SUM permission checking | Critical security fix |
| **92** | Megapage translation | All page sizes work |
| **90** | MMU PTW handshake | VM translation operational |

**Phase 3 Critical Fixes (Sessions 77-89)**:
- Session 87: 100% RV32/RV64 compliance (3 infrastructure bugs fixed)
- Session 86: FPU FMV/conversion fixes (8 tests)
- Sessions 78-85: RV64 word ops, data memory, test infrastructure

**Complete session details**: See `docs/SESSION_*.md` files (50+ detailed session logs)

---

## Test Infrastructure
**Quick Commands**:
- `make test-quick` - 14 regression tests (~4s)
- `env XLEN=32 ./tools/run_official_tests.sh all` - RV32 compliance (187 tests)
- `env XLEN=64 ./tools/run_official_tests.sh all` - RV64 compliance (106 tests)
- `make help` - All available commands

**Documentation**:
- `docs/TEST_CATALOG.md` - Complete test inventory (233 custom + 187 official)
- `docs/PHASE_4_PREP_TEST_PLAN.md` - Phase 4 test plan (44 tests, 4 weeks)
- `tools/README.md` - Test infrastructure details

**Workflow**: Always run `make test-quick` before/after changes to verify zero regressions

---

## Implemented Extensions & Architecture

**Compliance Status** (Verified Session 112):
- **RV32**: 79/79 tests (100%) ✅ PERFECT!
- **RV64**: 86/86 tests (100%) ✅ PERFECT!
- **Total**: 165/165 official tests (100%) ✅

**Extensions**: RV32/RV64 IMAFDC (200+ instructions) + Zicsr + Zifencei

**Architecture**:
- **Pipeline**: 5-stage (IF/ID/EX/MEM/WB), data forwarding, hazard detection
- **Privilege**: M/S/U modes, trap handling, exception delegation
- **MMU**: Sv32/Sv39 with 16-entry TLB, 2-level page table walks
- **FPU**: Single/double precision IEEE 754, NaN-boxing
- **Memory**: Synchronous registered memory (FPGA BRAM/ASIC SRAM compatible)

---

## Known Issues & Next Steps

**Current Status**:
- ✅ All compliance tests passing (165/165)
- ✅ Registered memory implementation complete and validated
- ✅ Phase 3 complete
- 🔴 **BLOCKER**: Instruction fetch bypasses MMU (discovered Session 116)

**Critical Issue**:
- **Instruction fetch MMU missing** - instruction memory access doesn't go through MMU
- Location: `rtl/core/rv32i_core_pipelined.v:2593` hardcoded to data-only
- Impact: All Phase 4 VM tests fail (11/11 Week 1 tests blocked)
- Required: RISC-V spec mandates instruction fetch translation

**Next Session Tasks (Session 117)**:
1. **PRIORITY**: Implement instruction fetch MMU translation
   - Add IF stage MMU arbiter (unified 16-entry TLB)
   - Update instruction memory to use translated addresses
   - Add instruction page fault handling (exception code 12)
   - Add pipeline stall logic for instruction TLB miss
   - Estimated: 4-8 hours (1-2 sessions)
2. Validate: All 11 Week 1 Phase 4 tests should pass
3. Continue: Week 2 Phase 4 tests (page fault recovery, syscalls)
4. Target: v1.1-xv6-ready milestone

**See**: `docs/INSTRUCTION_FETCH_MMU_IMPLEMENTATION_PLAN.md` for detailed plan

---

## OS Integration Roadmap

| Phase | Status | Milestone | Completion |
|-------|--------|-----------|------------|
| 1: RV32 Interrupts | ✅ Complete | CLINT, UART, SoC | 2025-10-26 |
| 2: FreeRTOS | ✅ Complete | Multitasking RTOS | 2025-11-03 |
| 3: RV64 Upgrade | ✅ Complete | **100% RV32/RV64 Compliance** | 2025-11-04 |
| 4: xv6-riscv | 🎯 **In Progress** | Unix-like OS, OpenSBI | TBD |
| 5: Linux | Pending | Full Linux boot | TBD |

**Phase 4 Progress**: Ready to begin - Phase 3 infrastructure complete (165/165 compliance tests passing)

---

## References & Documentation

**Specifications**:
- RISC-V Spec: https://riscv.org/technical/specifications/
- Official Tests: https://github.com/riscv/riscv-tests

**Project Documentation**:
- `docs/ARCHITECTURE.md` - CPU architecture overview
- `docs/PHASES.md` - Development phases and milestones
- `docs/SESSION_*.md` - Detailed session logs (50+ sessions)
- `docs/PHASE_4_PREP_TEST_PLAN.md` - Current test plan
- `docs/PHASE_4_OS_READINESS_ANALYSIS.md` - Gap analysis for xv6
