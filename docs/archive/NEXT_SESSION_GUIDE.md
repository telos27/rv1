# Next Session Guide: M Extension Pipeline Integration

**Date**: 2025-10-10
**Status**: Memory loading bug FIXED ✓, M extension modules complete, pipeline integration pending
**Git**: Committed to main

---

## What Was Accomplished This Session

### ✅ Critical Bug Fix: Instruction Memory Loading
**Problem**: PC was running away to 0x9c3c instead of executing programs correctly
**Root Cause**: `instruction_memory.v` was using `$readmemh` to load 32-bit word hex files directly into an 8-bit byte array
**Solution**:
- Added temporary 32-bit word array for loading
- Convert words to little-endian byte array
- Added debug output to verify loading

**Testing**: test_nop.s now completes in 11 cycles with correct register values (a0=0x600d)

### ✅ M Extension Core Modules (Complete but Not Integrated)
- `rtl/core/mul_unit.v` - Sequential multiplier (32 cycles)
- `rtl/core/div_unit.v` - Non-restoring divider (32 cycles)
- `rtl/core/mul_div_unit.v` - Wrapper module
- All committed to git and tested individually

---

## Next Session: M Extension Pipeline Integration

### The Challenge
The M extension requires **multi-cycle operations** that must properly integrate with the 5-stage pipeline. The key issue is **timing**: ensuring the M unit result is available when the instruction reaches the write-back stage.

### Problem Analysis (from this session)
When trying to integrate, we encountered:
1. **Stall timing issue**: M instruction leaves EX stage before busy signal goes high (busy is registered, has 1-cycle delay)
2. **Result capture issue**: Result becomes ready in EX stage but instruction has already advanced to WB
3. **Writeback timing**: Need to coordinate when reg_write happens with when result is valid

### Recommended Approach for Next Session

**Option 1: Result Bypass Architecture** (Recommended)
- M unit result stays in EX stage in dedicated registers
- When ready signal goes high, result is forwarded directly to WB stage
- Gate reg_write in WB stage to only write when M result is valid
- This avoids complex multi-stage stalling

**Option 2: Full Pipeline Stall** (More complex)
- Stall ID/EX, EX/MEM, and MEM/WB registers while M unit is busy
- Ensure M instruction stays in EX stage for entire operation
- Key: Must prevent instruction from advancing BEFORE busy goes high
- Requires careful handling of stall signal timing

**Option 3: Scoreboarding**
- Let M instruction advance through pipeline normally
- Mark register as "pending" in scoreboard
- Stall dependent instructions until M result is ready
- Write result when ready, even if instruction is out of pipeline

### Files That Need Modification

**For Pipeline Integration**:
1. `rtl/core/control.v` - Add M extension control signals (wb_sel = 3'b100)
2. `rtl/core/decoder.v` - Already has M extension detection
3. `rtl/core/rv32i_core_pipelined.v` - Instantiate M unit, wire signals
4. `rtl/core/hazard_detection_unit.v` - Add M extension stall logic
5. `rtl/core/idex_register.v` - Propagate M extension signals
6. `rtl/core/exmem_register.v` - Propagate M results
7. `rtl/core/memwb_register.v` - Propagate M results

**Key Signals to Add**:
- `is_mul_div` - M instruction flag (from decoder, through pipeline)
- `mul_div_op[3:0]` - Operation select (MUL, MULH, DIV, etc.)
- `mul_div_result[XLEN-1:0]` - Result from M unit
- `mul_div_busy` - M unit busy signal
- `mul_div_ready` - Result ready signal (1-cycle pulse)

### Test Programs Ready
- `tests/asm/test_m_simple.s` - Single MUL (5 × 10 = 50)
- `tests/asm/test_m_basic.s` - 12 comprehensive tests
- `tests/asm/test_nop.s` - Control test (no M instructions)

### Expected Behavior
```
test_m_simple.s should produce:
- a0 = 5
- a1 = 10
- a2 = 0x32 (50 decimal) ← This is the MUL result
- Final a0 = 0x600D (pass indicator)
```

### Debug Strategy
1. Start with `test_nop.s` to ensure no regression
2. Use waveforms to trace M instruction through pipeline
3. Monitor signals: `busy`, `ready`, `result`, `wb_sel`, `reg_write`
4. Check that stall prevents instruction from advancing too early
5. Verify result is captured at correct pipeline stage

### Quick Start Commands
```bash
cd /home/lei/rv1

# Verify memory fix still works
iverilog -g2005-sv -I rtl -o sim/test_nop -DXLEN=32 \
  -DMEM_FILE=\"tests/asm/test_nop.hex\" \
  tb/integration/tb_core_pipelined.v rtl/core/*.v rtl/memory/*.v
timeout 5 vvp sim/test_nop

# After integration, test M extension
iverilog -g2005-sv -I rtl -o sim/test_m_simple -DXLEN=32 \
  -DMEM_FILE=\"tests/asm/test_m_simple.hex\" \
  tb/integration/tb_core_pipelined.v rtl/core/*.v rtl/memory/*.v
timeout 10 vvp sim/test_m_simple
```

---

## Reference Materials

### Documentation Available
- `docs/M_EXTENSION_DESIGN.md` - Full M extension specification
- `M_EXTENSION_PROGRESS.md` - Implementation status
- This session explored multiple integration approaches

### M Extension Modules
All three modules are complete and tested:
- Support RV32M and RV64M (XLEN parameter)
- Handle all RISC-V spec edge cases
- 32-cycle latency for both multiply and divide
- Proper busy/ready handshaking

### RISC-V M Extension Instructions
```
MUL    rd, rs1, rs2  # Lower 32/64 bits of product
MULH   rd, rs1, rs2  # Upper bits (signed × signed)
MULHSU rd, rs1, rs2  # Upper bits (signed × unsigned)
MULHU  rd, rs1, rs2  # Upper bits (unsigned × unsigned)
DIV    rd, rs1, rs2  # Quotient (signed)
DIVU   rd, rs1, rs2  # Quotient (unsigned)
REM    rd, rs1, rs2  # Remainder (signed)
REMU   rd, rs1, rs2  # Remainder (unsigned)

RV64M adds: MULW, DIVW, DIVUW, REMW, REMUW (32-bit operations)
```

---

## Success Criteria

### Minimum Goal
- test_nop.s still passes (no regression)
- test_m_simple.s completes without timeout
- a2 = 0x32 (correct MUL result)

### Full Success
- All 12 tests in test_m_basic.s pass
- M unit stalls pipeline for correct duration
- Results are correctly written to destination registers
- No spurious writes or data hazards

---

## Notes

### What NOT to Do
- Don't try to use the partially-working integration code from this session
- Start fresh with a clear architecture decision (Option 1, 2, or 3 above)
- Don't commit broken integration code

### Architecture Decision
The key architectural question is: **Where should the M result live while waiting for writeback?**
- In EX stage (requires complex forwarding)
- In dedicated result registers (simpler)
- Advancing through pipeline (requires timing coordination)

I recommend Option 1 (Result Bypass) for simplicity.

---

**Last Updated**: 2025-10-10
**Status**: Ready for M extension pipeline integration
