# Next Session Guide: FPU Integration (Phase 8.3)

**Date**: 2025-10-10
**Current Progress**: Phase 8.2 Complete (60% of Phase 8)
**Next Milestone**: Integrate FPU into pipelined core

## What Was Completed This Session

### ✅ FPU Top-Level Integration Module
- **File**: `rtl/core/fpu.v` (475 lines)
- **Status**: Created and compiles successfully
- **Features**:
  - Instantiates all 10 FP arithmetic units
  - Operation multiplexing based on `fp_alu_op` (5-bit control)
  - Busy/done signaling for multi-cycle operations
  - Exception flag aggregation (NV, DZ, OF, UF, NX)
  - Supports both FP and integer results
  - FP→INT and INT→FP bitcast operations (FMV.X.W, FMV.W.X)

### ✅ FPU Units Integrated
1. **FP Adder** (FADD/FSUB) - 3-4 cycles
2. **FP Multiplier** (FMUL) - 3-4 cycles
3. **FP Divider** (FDIV) - 16-32 cycles, SRT radix-2
4. **FP Square Root** (FSQRT) - 16-32 cycles
5. **FP FMA** (FMADD/FMSUB/FNMSUB/FNMADD) - 4-5 cycles, single rounding
6. **FP Sign Injection** (FSGNJ/FSGNJN/FSGNJX) - 1 cycle, combinational
7. **FP Min/Max** (FMIN/FMAX) - 1 cycle
8. **FP Compare** (FEQ/FLT/FLE) - 1 cycle, writes to int register
9. **FP Classify** (FCLASS) - 1 cycle, writes to int register
10. **FP Converter** - TEMPORARILY STUBBED OUT (syntax errors to fix)

### ✅ Integration Planning Document
- **File**: `docs/FPU_INTEGRATION_PLAN.md`
- **Content**: Comprehensive 13-step integration checklist
- **Estimated Effort**: 350-400 lines across 6 modules
- **Time Estimate**: 6-8 hours

### Known Issues
1. **fp_converter.v has syntax errors**: Wire declarations inside case statements (Verilog-2001 incompatible)
   - Temporarily stubbed out in fpu.v
   - Need to refactor: move wire declarations outside case statement
2. **FP Compare operation not fully decoded**: FEQ/FLT/FLE need funct3 differentiation
3. **FP Converter operation not decoded**: FCVT operation type needs funct5

## What to Do Next Session

### Recommended Approach: **Phased Integration**

I strongly recommend a phased approach rather than attempting full integration in one session:

#### **Phase A: Basic FPU Wiring (4-5 hours)**
**Goal**: Get simple FP ADD instruction working (no hazards, no forwarding)

1. Add FP register file instantiation to ID stage
2. Update decoder/control instantiations with FP signals
3. Modify IDEX pipeline register for FP operands
4. Instantiate FPU in EX stage
5. Modify EXMEM pipeline register for FP results
6. Modify MEMWB pipeline register for FP results
7. Add FP write-back path to WB stage
8. Create simple FP ADD test program
9. **Test Milestone**: `FADD.S f1, f2, f3` executes correctly

**Files to Modify**:
- `rtl/core/rv32i_core_pipelined.v` (~150 lines added)
- `rtl/core/idex_register.v` (~30 lines added)
- `rtl/core/exmem_register.v` (~20 lines added)
- `rtl/core/memwb_register.v` (~15 lines added)

#### **Phase B: Multi-Cycle Operations (2-3 hours)**
**Goal**: Handle FPU busy signal and pipeline stalls

1. Add FPU busy signal to hazard detection
2. Stall pipeline when FPU is busy
3. Test multi-cycle operations (FDIV, FSQRT, FMA)
4. **Test Milestone**: `FDIV.S f1, f2, f3` completes after 16-32 cycles

#### **Phase C: Forwarding and Hazards (3-4 hours)**
**Goal**: Handle FP data hazards

1. Extend forwarding unit for FP registers
2. Add FP RAW hazard detection
3. Test back-to-back FP dependencies
4. **Test Milestone**: `FADD f1,f2,f3; FADD f4,f1,f5` works without stalls

#### **Phase D: Load/Store and FCSR (2-3 hours)**
**Goal**: Complete F/D extension functionality

1. Add FP memory operations (FLW/FSW/FLD/FSD)
2. Wire FPU exception flags to fflags CSR
3. Implement dynamic rounding mode
4. Run RISC-V compliance tests
5. **Test Milestone**: F/D extension compliance tests pass

### Quick Start Commands for Next Session

```bash
# 1. Review the integration plan
cat docs/FPU_INTEGRATION_PLAN.md

# 2. Check current pipeline register interfaces
grep -A 20 "module idex_register" rtl/core/idex_register.v
grep -A 20 "module exmem_register" rtl/core/exmem_register.v
grep -A 20 "module memwb_register" rtl/core/memwb_register.v

# 3. Review FPU interface
grep -A 30 "module fpu" rtl/core/fpu.v

# 4. Review control unit FP signals
grep -A 20 "F/D extension control outputs" rtl/core/control.v

# 5. Start with Phase A - begin modifying pipelined core
```

### Expected Session Outcome

By the end of Phase A (4-5 hours):
- ✅ FP register file integrated
- ✅ FPU instantiated in EX stage
- ✅ Pipeline registers extended for FP data
- ✅ Basic FP ADD instruction functional
- ✅ Can execute simple FP test program
- ⏳ Multi-cycle ops, hazards, load/store still pending

This gets you to **~70% Phase 8 completion** (up from 60%).

### Alternative: Full Integration in One Session

If you prefer to do everything at once:
- **Time Required**: 8-10 hours
- **Risk**: Higher (more debugging)
- **Benefit**: Complete F/D extension in one session
- **Recommendation**: Only if you have a full day

## Progress Tracking

**Current Phase 8 Status**:
- ✅ Infrastructure (40% → 20% of phase)
- ✅ All FP arithmetic units (20% → 40% of phase)  
- ⏳ FPU integration (0% → 40% of phase)

**After Phase A** (Basic Wiring):
- Phase 8: 60% → 70%

**After Phase B** (Multi-Cycle):
- Phase 8: 70% → 80%

**After Phase C** (Forwarding):
- Phase 8: 80% → 90%

**After Phase D** (Load/Store):
- Phase 8: 90% → 100% ✅

## Key Files Reference

| File | Lines | Purpose |
|------|-------|---------|
| rtl/core/fpu.v | 475 | FPU top-level (just created) ✅ |
| rtl/core/fp_register_file.v | 60 | FP register file (Phase 8.1) ✅ |
| rtl/core/rv32i_core_pipelined.v | 916 | Main core (needs ~250 lines) ⏳ |
| rtl/core/idex_register.v | ~100 | ID/EX register (needs ~30 lines) ⏳ |
| rtl/core/exmem_register.v | ~80 | EX/MEM register (needs ~20 lines) ⏳ |
| rtl/core/memwb_register.v | ~60 | MEM/WB register (needs ~15 lines) ⏳ |
| docs/FD_EXTENSION_DESIGN.md | 900+ | F/D spec reference |
| docs/FPU_INTEGRATION_PLAN.md | NEW | Step-by-step integration guide ✅ |

## Summary

✅ **This session**: Created FPU top-level module (~475 lines) that ties all FP units together
📋 **Next session**: Begin Phase A - wire FPU into pipeline, starting with basic operations
⏱️ **Time estimate**: 4-5 hours for Phase A (basic FP ADD working)
🎯 **Milestone**: Execute `FADD.S f1, f2, f3` successfully in pipelined core

Good luck with the integration! The phased approach will make debugging much easier.
