# CLAUDE.md - AI Assistant Context

## Project Overview
RISC-V CPU core in Verilog: 5-stage pipelined processor with RV32IMAFDC extensions and privilege architecture (M/S/U modes).

## Current Status (Session 79, 2025-11-03)

### 🎯 CURRENT PHASE: Phase 3 - RV64 Upgrade (In Progress)
- **Previous Phase**: ✅ **Phase 2 COMPLETE** - FreeRTOS fully operational!
- **Current Focus**: ✅ **RV64I Load/Store COMPLETE** - LD, LWU, SD validated!
- **Documentation**: See `docs/SESSION_79_RV64I_LOAD_STORE_FIX.md` for latest progress

### 🎉 Phase 3 Achievements (Sessions 77-79, Day 1-3)
**Milestone**: RV64I instruction set implementation and validation

**Validated Instructions**:
  - ✅ **Word Operations** (Session 78): All 9 RV64I-W instructions (ADDIW, ADDW, SUBW, SLLIW, SRLIW, SRAIW, SLLW, SRLW, SRAW)
  - ✅ **Load/Store** (Session 79): All 3 RV64I load/store instructions (LD, LWU, SD)
  - ✅ **Configuration** (Session 77-78): XLEN=64 parameter support, memory expansion

**Critical Fix** (Session 79):
  - **RV64 Testbench Bus Interface** - Added missing dmem_bus_adapter, fixed load instructions

### 🎉 Phase 2 Achievements (Sessions 62-76, 2 weeks)
**Milestone**: FreeRTOS v11.1.0 fully operational with multitasking, timer interrupts, and I/O

**Validated Functionality**:
  - ✅ **Multitasking**: Multiple tasks running concurrently
  - ✅ **Timer Interrupts**: CLINT delivering 1ms periodic interrupts
  - ✅ **Context Switching**: Preemptive (timer) and voluntary (ECALL) working
  - ✅ **UART I/O**: Task messages transmitted successfully
  - ✅ **Interrupt Handling**: Complete trap entry/exit, CSR state management
  - ✅ **Scheduler**: Task queue management, delay services operational

**Critical Bugs Fixed**:
  1. **MRET/Exception Priority** (Sessions 62, 74) - Eliminated PC/register corruption
  2. **C Extension Config** (Session 66) - Enabled compressed instructions at 2-byte boundaries
  3. **CLINT Bus Interface** (Session 75) - Fixed req_ready timing for timer interrupt delivery
  4. **MSTATUS.MIE Restoration** (Session 76) - Enabled interrupts after context restore

**Git Milestone**: Tagged `phase-2-complete` (commit 712d673)

### 📋 Phase 3 Plan: RV64 Upgrade (2-3 weeks)
**Scope**:
  - Extend XLEN from 32 to 64 bits (datapath, registers, CSRs)
  - Implement Sv39 MMU (3-level page tables vs current Sv32 2-level)
  - Expand memory subsystem (1MB IMEM, 4MB DMEM)
  - Run RV64 compliance tests (87 tests: RV64IMAFDC)
  - Validate FreeRTOS still works on RV64

**Next Steps**:
  - Review RV64I specification differences
  - Plan Sv39 MMU architecture changes
  - Identify modules requiring 64-bit modifications
  - Set up RV64 test infrastructure

### Latest Sessions (79, 78-cont, 78, 77, 76, 75, 74, 73, 72, 71, 70, 69, 68, 67)

**Session 79** (2025-11-03): RV64I Load/Store Instructions - Testbench Bus Interface Fix ✅🎉🎉🎉
- **Goal**: Validate RV64I load/store instructions (LD, LWU, SD)
- **Achievement**: ✅ **All 3 RV64I load/store instructions working!**
- **Problem Found**: RV64 testbench missing bus interface connections
  - Core has bus master interface (bus_req_valid, bus_req_addr, etc.)
  - RV64 testbench didn't connect these ports
  - Unconnected `bus_req_ready` and `bus_req_rdata` caused undefined behavior
  - Loads returned 0 because `bus_req_rdata` was undefined
- **The Fix** (`tb/integration/tb_core_pipelined_rv64.v`):
  - Added bus interface signal declarations (valid, addr, wdata, we, size, ready, rdata)
  - Connected all bus interface ports to core
  - Instantiated `dmem_bus_adapter` module to handle data memory access
  - Added missing interrupt ports (meip_in, seip_in)
- **Test Results**:
  - ✅ **LD** (Load Doubleword): Loads 64-bit values correctly
  - ✅ **LWU** (Load Word Unsigned): Zero-extends 32-bit to 64-bit (0x00000000fedcba98)
  - ✅ **SD** (Store Doubleword): Stores 64-bit values correctly
  - ✅ **64-bit SD+LD**: Full 64-bit value (0x123456789ABCDEF0) verified
- **Key Insight**: Hardware was already correct!
  - Data memory module already supported LD/LWU/SD (funct3 handling)
  - Decoder and control logic already handled RV64I instructions
  - Only testbench was broken - no RTL changes needed
- **Additional Fixes**:
  - Updated `tools/run_test_by_name.sh` to respect XLEN environment variable
  - Updated `tb/integration/tb_core_pipelined.v` with RV64 reset vector support
- **Impact**: RV64I load/store complete, ready for compliance testing
- See: `docs/SESSION_79_RV64I_LOAD_STORE_FIX.md`

**Session 78 Continued** (2025-11-03): SRAIW Bug Fixed - Word Operations Complete! 🎉🎉🎉
- **Goal**: Debug comprehensive word operations test failure
- **Achievement**: ✅ **All 9 RV64I word operations validated and working!**
- **Bug Found**: SRAIW/SRAW arithmetic shift failing
  - **Root Cause**: Operand preparation was zero-extending ALL operands
  - **Problem**: Arithmetic right shifts need sign-extension to preserve sign bit
  - Example: `SRAIW -1, 1` produced `0x7FFFFFFF` instead of `-1`
- **The Fix** (`rtl/core/rv32i_core_pipelined.v:1422-1436`):
  - Added `is_arith_shift_word` detection (funct3=101 && funct7[5])
  - Sign-extend operand A for SRAIW/SRAW (preserves sign during shift)
  - Zero-extend operand A for all other word operations (correct behavior)
- **Debug Infrastructure**:
  - Added cycle-by-cycle execution tracing
  - Shows IF/EX/WB stages with full operand/result visibility
  - Critical for identifying exact failure point (Test 7: SRAIW)
- **Verification Results**:
  - ✅ `test_rv64i_addiw_simple` - PASSES (16 cycles)
  - ✅ `test_addiw_minimal` - PASSES (17 cycles)
  - ✅ `test_rv64i_word_ops` - **PASSES (61 cycles, a0=1)** 🎉
- **All 9 Word Operations Validated**:
  1. ✅ ADDIW - Add immediate word
  2. ✅ ADDW - Add word
  3. ✅ SUBW - Subtract word
  4. ✅ SLLIW - Shift left logical immediate word
  5. ✅ SRLIW - Shift right logical immediate word
  6. ✅ SRAIW - Shift right arithmetic immediate word (FIXED!)
  7. ✅ SLLW - Shift left logical word
  8. ✅ SRLW - Shift right logical word
  9. ✅ SRAW - Shift right arithmetic word
- **Impact**: RV64I word operations complete, ready for official compliance tests
- See: `docs/SESSION_78_CONTINUED_SRAIW_BUG_FIXED.md`

**Session 78** (2025-11-03): Phase 3 Day 2 - RV64I Word Operations & Configuration Cleanup ✅
- **Goal**: Implement RV64I word operations, clean up RV32/RV64 configuration system
- **Achievement**: ✅ **Word operations implemented, configuration cleaned up!**
- **RV64I Word Operations** (`rtl/core/rv32i_core_pipelined.v:1415-1450`):
  - Implemented ADDIW, ADDW, SUBW, SLLIW, SRLIW, SRAIW, SLLW, SRLW, SRAW
  - **Key insight**: Arithmetic shifts need sign-extension, others use zero-extension
  - Operands: Lower 32 bits extended (sign for arith shifts, zero for others)
  - Results: Bit 31 sign-extended to bits 63:32 after ALU
  - Forwarding: Updated to use sign-extended results
- **Configuration System Cleanup**:
  - Fixed `rv_config.vh`: Removed `undef` that overrode command-line defines
  - Updated `tools/asm_to_hex.sh`: Auto-detects XLEN, sets architecture/ABI
  - Updated `tools/test_pipelined.sh`: Passes XLEN consistently
  - **Single source of truth**: XLEN environment variable
- **Test Infrastructure**:
  - Created `test_rv64i_addiw_simple.s` - ✅ **PASSES** (16 cycles)
  - Created `test_rv64i_word_ops.s` - Comprehensive test (debugged in continuation)
  - Fixed RV64 testbench reset vector: 0x0 → 0x80000000
- **Impact**: Foundation for RV64 support complete, ready for compliance testing
- See: `docs/SESSION_78_PHASE_3_DAY_2.md`

**Session 77** (2025-11-03): Phase 3 Day 1 - RV64 Configuration & Audit ✅
- **Goal**: Start Phase 3 RV64 upgrade - configure and audit codebase
- **Achievement**: ✅ **Configuration complete, build successful, code already 70% RV64-ready!**
- **Configuration Updates**:
  - Changed default XLEN from 32 to 64 in `rv_config.vh`
  - Expanded IMEM: 64KB → 1MB (for xv6/Linux)
  - Expanded DMEM: 1MB → 4MB (for xv6/Linux)
- **Code Audit**:
  - Created `tools/audit_rv64.sh` automated audit script
  - Scanned 30+ modules for hardcoded 32-bit widths
  - Found only 4 issues (CSR read-only registers) - FIXED
- **Key Finding**: ✅ **Codebase already well-prepared for RV64!**
  - Register file, pipeline registers, ALU, MUL/DIV all use XLEN parameter
  - FPU correctly handles 32-bit floats with NaN-boxing
  - CSR file has proper RV32/RV64 MISA generation
  - ~70% of RV64 work already done from previous parameterization!
- **Build Verification**:
  - ✅ `make rv64i` compiles successfully
  - ✅ No errors, only warnings from unused old core
  - ✅ Main pipelined core clean
- **What's Left**:
  - 📋 RV64I instruction decode (LD, SD, LWU, ADDW, etc.)
  - 📋 Update test infrastructure for RV64 tests
  - 📋 Sv39 MMU upgrade (3-level page tables)
- **Impact**: Phase 3 ahead of schedule - excellent groundwork from previous phases!
- See: `docs/SESSION_77_PHASE_3_DAY_1.md`, `docs/PHASE_3_PLAN.md`

**Session 76** (2025-11-03): FreeRTOS Fully Operational - MSTATUS.MIE Bug Fixed! 🎉🎉🎉
- **Goal**: Debug why timer interrupts fire but CPU doesn't take them
- **Achievement**: ✅ **PHASE 2 COMPLETE - FreeRTOS fully operational!**
- **Root Cause**: `portcontextRESTORE_CONTEXT` restored MSTATUS from stack without forcing MIE=1
  - Task stacks initialized with MIE=0 (interrupts disabled during setup)
  - xPortStartFirstTask enables MIE once at startup
  - Every trap handler return restored MIE=0 from stack, disabling all future interrupts
- **The Bug** (software/freertos/port/portContext.h:149-150):
  ```asm
  load_x  t0, portMSTATUS_OFFSET * portWORD_SIZE( sp )
  csrw mstatus, t0                    /* ❌ Restores MIE=0 from stack */
  ```
- **The Fix** (added line 150):
  ```asm
  load_x  t0, portMSTATUS_OFFSET * portWORD_SIZE( sp )
  addi    t0, t0, 0x08                /* ✅ Force MIE=1 */
  csrw mstatus, t0
  ```
- **Verification Results**:
  - ✅ Timer interrupts firing every 1ms (mcause=0x80000007)
  - ✅ Voluntary task switches working (mcause=0x0000000b ECALL)
  - ✅ Both tasks executing and printing UART output
  - ✅ Timer handler rescheduling MTIMECMP correctly
  - ✅ Full multitasking operation confirmed!
- **UART Output**:
  ```
  [Task2] Started! Running at 1Hz
  [Task2] Tick
  ```
- **Impact**: FreeRTOS validated, ready for Phase 3 (RV64 upgrade)
- See: `docs/SESSION_76_FREERTOS_FULLY_OPERATIONAL.md`

### Latest Sessions (76, 75, 74, 73, 72, 71, 70, 69, 68, 67, 66, 65, 64)

**Session 75** (2025-10-31): CLINT Timer Bug FIXED - Critical Breakthrough! 🎉🎉🎉
- **Goal**: Investigate why FreeRTOS stops after 1 tick
- **Achievement**: ✅ **CLINT timer bug fixed - Timer interrupts firing for FIRST TIME EVER!**
- **Investigation Process**:
  - Initially suspected "load bug" → FALSE - timer queue correctly has queueLength=10
  - Discovered timer interrupts never firing despite vPortSetupTimerInterrupt() executing
  - Found bus writes to CLINT failing: `clint_req_valid=1, clint_req_ready=0`
  - Root cause: `req_ready` was registered (1-cycle delay) instead of combinational
- **The Bug** (rtl/peripherals/clint.v:34, 217):
  ```verilog
  output reg  req_ready;           // ❌ Registered
  req_ready <= req_valid;          // ❌ 1-cycle delay
  ```
  - Bus transaction requires `valid && ready` **in same cycle**
  - Registered ready delayed by 1 cycle → transaction fails
  - MTIMECMP never written → Timer never programmed → No interrupts
- **The Fix**:
  ```verilog
  output wire req_ready;           // ✅ Combinational
  assign req_ready = req_valid;    // ✅ Same-cycle response
  ```
  - Also changed `MTIME_PRESCALER` from 10 to 1 (FreeRTOS expects mtime @ CPU freq)
- **Results**:
  - ✅ CLINT writes successful: MTIMECMP = 0x0000cd45 (52,549)
  - ✅ Timer interrupts fire: `[MTIP] Cycle 75497: Timer interrupt pending! mtip=1`
  - ✅ **FIRST TIME EVER** seeing timer interrupts in entire project!
  - ⚠️ CPU doesn't take interrupt yet (stays in idle loop, no trap)
- **Next**: Debug interrupt delivery (MSTATUS.MIE, WFI, MIP.MTIP)
- See: `docs/SESSION_75_CLINT_TIMER_BUG_FIXED.md`

### Latest Sessions (75, 74, 73, 72, 71, 70, 69, 68, 67, 66, 65, 64)

**Session 74** (2025-10-31): MRET/Exception Priority Bug Fixed (AGAIN!) ✅🎉🎉🎉
- **Goal**: Fix FreeRTOS crash at PC=0xa5a5a5a4
- **Achievement**: ✅ **Session 62's fix was incomplete - properly fixed now!**
- **Root Cause Identified**: MRET+exception simultaneous occurrence
  - Session 62 prevented MEPC corruption in CSR module
  - Did NOT prevent exception detection when MRET in pipeline
  - Caused `mret_flush=1` and `exception=1` simultaneously
  - Led to PC corruption → jump to reset (0x00000000) → startup code re-execution → crash
- **The Fix** (ONE line!):
  - Modified line 516: `exception_gated` now blocks when MRET/SRET executing
  - Added `!mret_flush && !sret_flush` to exception_gated condition
  - Ensures MRET always has priority over exceptions
- **Investigation Process**:
  - Added `DEBUG_REG_CORRUPTION` flag to track 0xa5a5a5a5 pattern writes
  - Discovered NO register writes with corrupted values
  - Traced PC flow: exception at cycle 39415 → JALR to 0x0 → startup code → crash
  - Found init_array code executing twice with stale register values
- **Test Results**:
  - ✅ FreeRTOS crash at PC=0xa5a5a5a4 eliminated
  - ✅ No more jump to reset vector (0x00000000)
  - ✅ Scheduler running, UART output working
  - ✅ All regression tests pass (14/14)
- **Impact**: Resolves ALL issues from Sessions 68-73 (were false leads caused by this bug)
  - All CPU hardware validated correctly
  - Sessions 68-73 investigated non-existent bugs (JAL, JALR, stack init, etc.)
- **Debug Infrastructure**: `DEBUG_REG_CORRUPTION` flag (lines 2738-2782)
  - Tracks 0xa5a5a5a5 pattern writes, sp/ra/t0/t1/t2 modifications
- **Files Modified**: `rtl/core/rv32i_core_pipelined.v`
- See: `docs/SESSION_74_MRET_EXCEPTION_PRIORITY_BUG_FIXED.md`

### Latest Sessions (74, 73, 72, 71, 70, 69, 68, 67, 66, 65, 64)

**Session 73** (2025-10-31): JALR Verification - No Bug Found! ✅🎉
- **Goal**: Investigate suspected JALR instruction bug from Session 72
- **Achievement**: ✅ **JALR instruction works perfectly** - Session 72 was false diagnosis!
- **Investigation**:
  - Analyzed entire JALR path: branch_unit, control, RVC decoder, pipeline registers
  - Added `DEBUG_JALR_TRACE` flag with comprehensive pipeline visibility
  - Traced JALR through ID→IDEX→EX stages
- **Test Results**:
  - ✅ `test_jalr_ret_simple` **PASSES** - a0=1 (success indicator)
  - ✅ `idex_jump=1` set correctly in ID stage
  - ✅ `ex_take_branch=1` set correctly in EX stage
  - ✅ Branch target calculation correct (ra=0x0e, target=0x0e)
  - ✅ Return address save/restore working
- **Key Finding**: Session 72's "timeout" was misinterpreted
  - Test actually passes (a0=1) then enters infinite loop (expected behavior)
  - Timeout is normal for tests ending in `j 1b` infinite loop
  - Final register state shows success, not failure
- **FreeRTOS Crash Re-analysis**:
  - NOT a JALR instruction bug
  - JALR executes correctly but jumps to **corrupted address** 0xa5a5a5a5
  - 0xa5a5a5 is FreeRTOS stack fill pattern (uninitialized memory)
  - Real issue: register/stack corruption (context switch, task creation, interrupts)
- **Debug Infrastructure**: New `DEBUG_JALR_TRACE` flag
  - ID stage decode visibility
  - IDEX latch tracking
  - EX stage execution details
  - Branch unit input/output monitoring
- **Conclusion**: Sessions 68-72 investigated **non-existent CPU bugs**
  - All CPU hardware is CORRECT
  - FreeRTOS issue is software-level corruption, not hardware bug
- **Files Modified**: `rtl/core/rv32i_core_pipelined.v`
- See: `docs/SESSION_73_JALR_VERIFICATION_NO_BUG.md`

**Session 72** (2025-10-31): Infinite Loop Investigation - False Alarm! ✅🎉
- **Goal**: Investigate "infinite loop" at 0x200e ↔ 0x4ca
- **Achievement**: ✅ **"Infinite loop" was normal memset() execution** - False alarm!
- **Key Findings**:
  - memset() filling 900+ bytes with pattern 0xa5 (legitimate FreeRTOS stack init)
  - Takes ~7 cycles/byte × 900 bytes = 6,300+ cycles
  - Short timeout (2s) terminated simulation mid-execution, appeared as "infinite loop"
  - With longer timeout (10s), memset completes but FreeRTOS crashes at PC=0xa5a5a5a4
- **False Diagnosis**: ⚠️ Incorrectly concluded "JALR instruction failure"
  - Created `test_jalr_ret_simple` - minimal JALR/RET test
  - Test appeared to fail (timeout) - but actually PASSED (verified in Session 73)
  - Misinterpreted timeout as failure, not expected infinite loop
  - Session 73 proved JALR works correctly
- **Instrumentation**: Added `DEBUG_LOOP_TRACE` flag
  - Comprehensive execution tracing around critical addresses
  - Full pipeline state visibility (IF/ID/EX/MEM/WB)
  - Loop detection with auto-termination
- **Files Modified**: `rtl/core/rv32i_core_pipelined.v`, `tools/test_freertos.sh`
- **Test Created**: `tests/asm/test_jalr_ret_simple.s` (actually passes - verified Session 73)
- See: `docs/SESSION_72_INFINITE_LOOP_INVESTIGATION.md`

### Latest Sessions (73, 72, 71, 70, 69, 68, 67, 66, 65, 64, 63-corrected)

**Session 71** (2025-10-31): FreeRTOS Verification - No Bugs Found! ✅🎉
- **Goal**: Verify suspected FreeRTOS bugs (uninitialized registers, task return address)
- **Achievement**: ✅ **Both "bugs" are correct behavior** - FreeRTOS implementation matches spec!
- **Investigation**:
  - Added register write tracking (`DEBUG_REG_WRITE` flag)
  - Traced all writes to x7 (t2) - only 3 writes, never 0xa5a5a5a5
  - Verified corruption pattern never written to register file
- **"Bug" #1 - Uninitialized Registers**: ✅ **CORRECT per RISC-V ABI**
  - Caller-saved registers (t0-t6, a0-a7) can contain garbage when function starts
  - C functions initialize temporaries before use (compiler guarantees)
  - FreeRTOS only needs to initialize ra and a0 for task start
- **"Bug" #2 - configTASK_RETURN_ADDRESS=0**: ✅ **CORRECT GCC RISC-V default**
  - Official GCC RISC-V port defaults to 0 (not prvTaskExitError like ARM)
  - Acceptable because tasks should never return (infinite loops)
  - If task returns, jumping to 0x00 resets system (fail-safe)
- **Real Bug**: Infinite loop at 0x200e ↔ 0x4ca is NOT register corruption
  - Different issue from Session 70's hypothesis
  - Original Session 68 bug still unresolved
- **Files Modified**: `rtl/core/register_file.v`, `tools/test_freertos.sh`
- See: `docs/SESSION_71_FREERTOS_VERIFICATION_NO_BUGS.md`

### Latest Sessions (71, 70, 69, 68, 67, 66, 65, 64, 63-corrected)

**Session 70** (2025-10-31): JAL Debug Instrumentation - Bug Does Not Exist! ✅🎉
- **Goal**: Add debug instrumentation to identify JAL→compressed PC increment bug
- **Achievement**: ✅ **Proved bug does NOT exist** - JAL→compressed works correctly!
- **Debug Instrumentation**:
  - Added `DEBUG_JAL_RET` flag with comprehensive PC increment tracing
  - Shows PC transitions, compression detection, control path selection
  - Reveals EX stage state (idex_pc, idex_imm, target calculation)
- **Test Results**:
  - ✅ `test_jal_simple`: PASS - Basic JAL functionality correct
  - ✅ `test_jal_compressed_return`: PASS - JAL→compressed pattern works perfectly
  - ⚠️ FreeRTOS: Still crashes, but **different root cause identified**
- **Key Finding**: FreeRTOS crash is **register corruption**, NOT JAL bug
  - JALR tries to jump using `t2 (x7) = 0xa5a5a5a5` (uninitialized stack pattern)
  - Crash at PC=0xa5a5a5a4 (invalid memory address)
  - Likely causes: context switch bug, stack corruption, interrupt handler issue
- **Conclusion**: Sessions 68-69 investigation was **misdiagnosis**
  - Session 66's C extension config fix already resolved any JAL issues
  - PC increment logic is CORRECT for both compressed and non-compressed
  - All CPU hardware verified CORRECT
- **Next**: Investigate register corruption in FreeRTOS (context switch/stack/interrupts)
- See: `docs/SESSION_70_JAL_DEBUG_INSTRUMENTATION.md`

### Latest Sessions (70, 69, 68, 67, 66, 65, 64, 63-corrected)

**Session 69** (2025-10-30): VCD Waveform Analysis - PC Increment Bug Investigation 🔍
- **Goal**: Deep VCD analysis to identify root cause of JAL→compressed bug
- **Process**:
  - Generated 185MB VCD waveform from minimal test case
  - Created Python analysis scripts to extract key signals
  - Traced PC increment logic cycle-by-cycle
  - Analyzed instruction fetch and compression detection
- **Key Finding**: PC increments by +2 instead of +4 after JAL instruction
  - Cycle 9: PC=0x14, fetches JAL (0x018000ef), `if_is_compressed=0` ✓
  - Cycle 10: PC=0x16 ← **WRONG!** Should be 0x18 (PC+4)
  - Compression detection correctly identifies JAL as NOT compressed
  - But PC increment still uses +2 instead of +4
- **Analysis**: Likely timing issue between instruction fetch and PC increment calculation
- **Tools Created**: 6 Python VCD analysis scripts for signal extraction and correlation
- **VCD Insights**:
  - Signal timing clarified: `if_pc` (VCD) = `ifid_pc` (pipeline register, 1 cycle behind)
  - Compression detection logic verified correct
  - PC increment calculation logic verified correct
  - Issue is in TIMING or DATA being used for calculation
- **Next**: Add debug instrumentation for direct console output, test simpler cases
- See: `docs/SESSION_69_VCD_ANALYSIS_PC_INCREMENT_BUG.md`

**Session 68** (2025-10-30): JAL→Compressed Instruction Bug Investigation 🔍
- **Issue**: FreeRTOS hangs in infinite loop between memset() RET and prvInitialiseNewTask()
- **Pattern**: JAL (4-byte) followed by compressed instruction (2-byte) at return address
- **Minimal test**: Created `test_jal_compressed_return.s` that reproduces hang
- **Analysis**:
  - Instruction fetch appears correct (0x589c = C.LW at return address)
  - PC increment logic appears correct (PC+2 for compressed)
  - JAL saves correct return address (ra = 0x4ca)
  - Call depth underflows after first successful returns (0 → 0xFFFFFFFF)
- **Attempted fix**: Selecting bits based on PC[1] - INCORRECT, broke tests, reverted
- **Root cause**: Still under investigation - likely pipeline/timing issue
- **Next**: VCD waveform analysis, pipeline flush investigation (Session 69)
- See: `docs/SESSION_68_JAL_COMPRESSED_RETURN_BUG.md`

**Session 67** (2025-10-29): Testbench False Positive & FPU Binary Fixed! 🎉🎉
- **Bug #1 - Testbench**: Assertion watchpoint at wrong address (0x1c8c instead of 0x23e8)
  - Caused false positive at cycle 33,569 terminating simulation prematurely
  - Fixed: Updated `tb/integration/tb_freertos.v:792` to use correct address
  - Result: Simulation runs full 500K cycles (15x improvement)
- **Bug #2 - Stale Binary**: FreeRTOS compiled with FPU context save despite Session 57 workaround
  - xPortStartFirstTask had FPU instructions causing illegal instruction loop
  - Root cause: Binary compiled BEFORE workaround source code changes
  - Fixed: Rebuilt FreeRTOS (`make clean && make`), FPU instructions now removed
  - Result: No more FPU exceptions, prints full banner via UART
- **Current Issue**: FreeRTOS crashes after "Starting FreeRTOS scheduler..." (PC → 0xa5a5a5XX)
- **Status**: Major progress (2 bugs fixed), new crash exposed (stack/context issue)
- See: `docs/SESSION_67_TESTBENCH_FALSE_POSITIVE_AND_FPU_REBUILD.md`

**Session 66** (2025-10-29): C Extension Misalignment Bug FIXED! 🎉🎉🎉
- **Root Cause**: `CONFIG_RV32I` in rv_config.vh forcibly disabled ENABLE_C_EXT, overriding command-line `-DENABLE_C_EXT=1`
- **Impact**: Caused instruction address misalignment exceptions for 2-byte aligned addresses (0x0e, 0x200e, etc.)
- **Fix**: Modified rv_config.vh to respect command-line overrides using `ifndef` guards
- **Result**: Compressed instructions (RET, C.JR, etc.) now execute correctly at 2-byte boundaries
- **Verification**: 14/14 quick regression tests PASS, FreeRTOS runs 22K+ cycles (vs 500K before)
- **Status**: Critical bug fixed, but FreeRTOS still has infinite loop (different issue)
- See: `docs/SESSION_66_C_EXTENSION_MISALIGNMENT_BUG_FIXED.md`

**Session 65** (2025-10-29): Pipeline Flush Investigation - Hardware Validated! ✅
- **Goal**: Investigate if pipeline flush logic causes JAL/JALR to fail
- **Discovery**: ✅ **Pipeline flush logic is CORRECT!**
- **Investigation Process**:
  1. Attempted "fix": Remove `ex_take_branch` from `flush_idex`
  2. Result: FreeRTOS ran longer BUT broke atomic/RVC tests (2/14 failed)
  3. Analysis: "Fix" allowed wrong-path instructions to execute (incorrect)
  4. Validation: Original code passes all regression tests (14/14) ✅
- **Key Findings**:
  - Branch/jump instructions flush correctly via `ex_take_branch` in both `flush_ifid` and `flush_idex`
  - EX/MEM latches branch instruction BEFORE ID/EX flush happens (Verilog timing)
  - Branch completes through MEM→WB and writes return address correctly ✅
  - Removing `ex_take_branch` from `flush_idex` is WRONG - allows wrong-path execution
- **FreeRTOS Issues**: NOT caused by pipeline logic, need software-level investigation
- **Status**: CPU hardware fully validated, pipeline logic correct
- See: `docs/SESSION_65_PIPELINE_FLUSH_INVESTIGATION.md`

**Session 64** (2025-10-29): Stack Initialization Investigation ⚠️
- **Discovery**: Session 63's conclusion was WRONG! Stack initialization IS working correctly
- **Investigation**: Memory write watchpoints traced all writes to Task B's stack
- **Key Findings**:
  - ✅ `pxPortInitialiseStack()` working correctly - writes ra=0 at cycle 14945
  - ✅ ra=0 is CORRECT per FreeRTOS design (`configTASK_RETURN_ADDRESS = 0`)
  - ✅ No stack corruption - value stays 0x00000000 after initialization
  - ❌ Session 63 misdiagnosed correct behavior as "uninitialized"
- **CPU Status**: ✅ All hardware validated (MRET, pipeline, CSRs, trap handling, stack init)
- **Real Bug**: NOT stack initialization! Possible causes:
  1. JAL/JALR not writing return addresses correctly
  2. Register file forwarding bug (ra writes lost)
  3. Trap handler context save/restore corrupting ra
  4. Different root cause entirely
- **Next**: Test JAL/JALR execution, register file writes, trap handler
- See: `docs/SESSION_64_STACK_INITIALIZATION_INVESTIGATION.md`

**Session 63** (2025-10-29): Context Switch Investigation - CONCLUSION REVISED ⚠️
- **Original Conclusion** (INCORRECT): Task stacks uninitialized
- **Correction** (Session 64): Stack IS initialized correctly, ra=0 is expected value
- **Still Valid**: Session 62 MRET fix correct, CPU hardware validated, crash trace analysis
- See: `docs/SESSION_63_FREERTOS_CONTEXT_SWITCH_BUG.md` (with correction notice)

**Session 62** (2025-10-29): MRET/Exception Priority Bug FIXED 🎉🎉🎉
- **Root Cause**: When MRET flushed pipeline, `trap_entry` to CSR bypassed priority check, corrupting MEPC
- **Fix**: Changed `.trap_entry(exception_gated)` to `.trap_entry(trap_flush)` (rv32i_core_pipelined.v:1633)
- **Result**: FreeRTOS runs 500,000+ cycles (12.7x improvement), scheduler working!
- **Impact**: Session 57's "FPU workaround" no longer needed - can re-enable FPU context save
- See: `docs/SESSION_62_MRET_EXCEPTION_PRIORITY_BUG_FIXED.md`

### Key Bug Fixes (Sessions 46-67)
- ✅ Testbench false positive (Session 67) - CRITICAL fix: assertion watchpoint at wrong address
- ✅ Stale FreeRTOS binary (Session 67) - CRITICAL fix: rebuilt with FPU disabled
- ✅ C extension config bug (Session 66) - CRITICAL fix enabling compressed instructions at 2-byte boundaries
- ✅ MRET/exception priority bug (Session 62) - CRITICAL fix enabling FreeRTOS scheduler
- ✅ M-extension operand latch bug (Session 60) - Back-to-back M-instructions now work
- ✅ Debug infrastructure built (Session 59) - Call stack, watchpoints, register monitoring
- ✅ IMEM data port byte-level access (Session 58) - Strings load correctly
- ✅ MSTATUS.FS field fully implemented (Session 56) - FPU permission checking
- ✅ EX/MEM hold during bus wait (Session 54) - Multi-cycle peripheral writes preserved
- ✅ MTVEC/STVEC 2-byte alignment (Session 53) - C extension compatibility
- ✅ Bus wait stall logic (Session 52) - Pipeline sync with slow peripherals
- ✅ Bus 64-bit read extraction (Session 51) - CLINT register access
- ✅ CLINT mtime prescaler (Session 48) - Atomic 64-bit reads on RV32
- ✅ M-extension forwarding (Session 46) - MULHU data forwarding

**For complete session history, see**: `docs/SESSION_*.md` files

## Compliance & Testing
- **98.8% RV32 Compliance**: 80/81 official tests passing (FENCE.I low priority)
- **Privilege Tests**: 33/34 passing (97%)
- **Quick Regression**: 14/14 tests, ~4s runtime
- **FreeRTOS**: ✅ **FULLY OPERATIONAL** - Multitasking, timer interrupts, context switching all working!

## Test Infrastructure (CRITICAL - USE THIS!)

**Key Resources:**
- `docs/TEST_CATALOG.md` - All 208 tests (127 custom + 81 official)
- `make help` - All available test targets
- `tools/README.md` - Script reference

**Essential Commands:**
```bash
make test-quick           # Quick regression (14 tests in ~7s) ⚡
make help                 # See available commands
make catalog              # Regenerate test catalog
env XLEN=32 ./tools/run_official_tests.sh all  # Full suite
```

**✨ Auto-Rebuild Feature:**
- Individual tests auto-rebuild hex files if missing or stale
- Tests detect when source (.s) is newer than hex and rebuild automatically
- Use `make rebuild-hex` for batch smart rebuild (only changed files)

**Workflow for Development:**
1. Run `make test-quick` BEFORE changes (baseline)
2. Make your changes
3. Run `make test-quick` AFTER changes (verify)
4. Before committing: Run full test suite
5. **No need to manually rebuild hex files!** Tests auto-rebuild as needed

## Project Structure
```
rv1/
├── docs/           # Design documents
├── rtl/core/       # CPU core modules
├── rtl/memory/     # Memory components
├── tb/             # Testbenches
├── tests/          # Test programs
└── tools/          # Helper scripts
```

## Design Constraints
- **HDL**: Verilog-2001 compatible
- **Simulation**: Icarus Verilog primary
- **XLEN**: Configurable 32-bit (RV32) or 64-bit (RV64)
- **Endianness**: Little-endian

## Implemented Extensions (98.8% Compliance - 80/81 tests)

| Extension | Tests | Instructions | Key Features |
|-----------|-------|--------------|--------------|
| **RV32I** | 41/42 ⚠️ | 47 | Integer ops, load/store, branches (FENCE.I issue) |
| **RV32M** | 8/8 ✅ | 13 | MUL/DIV (32-cycle mult, 64-cycle div) |
| **RV32A** | 10/10 ✅ | 22 | LR/SC, AMO operations |
| **RV32F** | 11/11 ✅ | 26 | Single-precision FP, FMA |
| **RV32D** | 9/9 ✅ | 26 | Double-precision FP, NaN-boxing |
| **RV32C** | 1/1 ✅ | 40 | Compressed instructions (25-30% density) |
| **Zicsr** | - | 6 | CSR instructions |

**Note**: FENCE.I test failing (pre-existing since Session 33, low priority)

## Architecture Features

**Pipeline**: 5-stage (IF, ID, EX, MEM, WB)
- Data forwarding, hazard detection
- LR/SC reservation tracking, CSR RAW hazard detection
- Precise exceptions

**Privilege Architecture**: M/S/U modes
- Full trap handling, delegation (M→S via medeleg/mideleg)
- CSRs: mstatus, sstatus, mie, sie, mtvec, stvec, mepc, sepc, mcause, scause, etc.

**Memory Management**: Sv32/Sv39 MMU with 16-entry TLB

**FPU**: Single/double precision, shared 64-bit register file

## Privilege Mode Test Suite

**Status**: 33/34 tests passing (97%)
**Documentation**: `docs/PRIVILEGE_TEST_IMPLEMENTATION_PLAN.md`
**Macros**: `tests/asm/include/priv_test_macros.s` (520+ lines, 50+ macros)

| Phase | Status | Tests | Description |
|-------|--------|-------|-------------|
| 1: U-Mode | ✅ 5/5 | M→U/S→U transitions, ECALL, CSR privilege |
| 2: Status Regs | ✅ 5/5 | MRET/SRET state machine, trap handling |
| 3: Interrupt CSRs | ✅ 4/4 | mip/sip/mie/sie, mideleg |
| 4: Exceptions | ✅ 5/8 | EBREAK, ECALL, delegation |
| 5: CSR Edge Cases | ✅ 4/4 | Read-only CSRs, WARL fields |
| 6: Delegation | ✅ 4/4 | Delegation edge cases |
| 7: Stress Tests | ✅ 2/2 | Mode switching, regression |

## Naming Conventions

**Files**: `snake_case.v`, testbenches `tb_<module>.v`
**Signals**: `_n` (active-low), `_r` (registered), `_next` (next-state)
**Parameters**: UPPERCASE with underscores

## Testing Strategy
1. Unit Tests - Each module independently
2. Instruction Tests - Known results verification
3. Compliance Tests - RISC-V official suite (80/81 ✅)
4. Program Tests - Assembly programs (Fibonacci, sorting)
5. Privilege Tests - M/S/U mode coverage

## When Assisting

**Before Changes:**
1. Check `docs/PHASES.md` for current phase
2. Review `docs/ARCHITECTURE.md` for constraints
3. Verify against RISC-V spec
4. Run `make test-quick` for baseline

**Code Style:**
- 2-space indentation, lines <100 chars
- Comment complex logic, meaningful signal names

**Debug Approach:**
1. Check waveforms → 2. Control signals → 3. Instruction decode → 4. Data path → 5. Timing

## Statistics
- **Instructions**: 184+ (I:47, M:13, A:22, F:26, D:26, C:40, Zicsr:6)
- **Official Tests**: 80/81 (98.8%) ⚠️ (FENCE.I failing, low priority)
- **Custom Tests**: 60+ programs
- **Configuration**: RV32/RV64 via XLEN parameter

## References
- RISC-V ISA Spec: https://riscv.org/technical/specifications/
- Test Suite: https://github.com/riscv/riscv-tests
- Compliance: https://github.com/riscv/riscv-compliance

## Known Issues

See `docs/KNOWN_ISSUES.md` for complete tracking and history.

**Current:**
- ⚠️ FreeRTOS scheduler crash (Session 67) - PC jumps to 0xa5a5a5XX after "Starting scheduler..."
- ⚠️ FPU instruction decode bug (Session 56-57) - FPU context save/restore disabled as workaround

**Low Priority:**
- ⚠️ FENCE.I test (self-modifying code, 80/81 = 98.8%)
- ⚠️ picolibc printf() duplication (workaround: use puts())

## OS Integration Roadmap

**Goal**: Progressive OS validation from embedded RTOS to full Linux (16-24 weeks)
**Documentation**: `docs/OS_INTEGRATION_PLAN.md`, `docs/PHASE_2_COMPLETE.md`

**Current**: Phase 3 STARTING - RV64 Upgrade

| Phase | Status | Duration | Completion | Milestone |
|-------|--------|----------|------------|-----------|
| 1: RV32 Interrupts | ✅ Complete | 2-3 weeks | 2025-10-26 | CLINT, UART, SoC integration |
| 2: FreeRTOS | ✅ **Complete** | 2 weeks | 2025-11-03 | Multitasking RTOS validated! |
| 3: RV64 Upgrade | 🚧 **Starting** | 2-3 weeks | TBD | 64-bit XLEN, Sv39 MMU |
| 4: xv6-riscv | Pending | 3-5 weeks | TBD | Unix-like OS, OpenSBI |
| 5a: Linux nommu | Optional | 3-4 weeks | TBD | Embedded Linux |
| 5b: Linux + MMU | Pending | 4-6 weeks | TBD | Full Linux boot |

## Future Enhancements

**Current Priority**: Phase 3 (RV64 Upgrade) - 64-bit XLEN, Sv39 MMU, xv6-riscv preparation

**Long-term**:
- Extensions: Bit Manipulation (B), Vector (V), Crypto (K)
- Performance: Branch prediction, caching, out-of-order execution
- System: Debug module, PMP, Hypervisor extension
- Verification: Formal verification, FPGA synthesis, ASIC tape-out
