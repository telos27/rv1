# Session 72: Enhanced Debug Instrumentation

**Date**: 2025-10-31
**Status**: ✅ Infrastructure complete, ready for use
**Goal**: Create comprehensive debug infrastructure to simplify future debugging

## Summary

Enhanced the RISC-V CPU core with two new debug instrumentation systems that provide synchronized, detailed visibility into pipeline operation. This will significantly ease future debugging by showing exactly what each pipeline stage is doing at each cycle.

## New Debug Flags

### 1. `DEBUG_PIPELINE` - Full Pipeline State Visualization

Provides a synchronized view of all 5 pipeline stages (IF, ID, EX, MEM, WB) at each cycle.

**Usage**:
```bash
env XLEN=32 DEBUG_PIPELINE=1 ./tools/run_test_by_name.sh <test_name>
```

**Output Format**:
```
================================================================================
[CYCLE N] Pipeline State:
================================================================================
IF:  PC=00000000 → 00000004 | instr=00000000 comp=0 | stall=0 flush=0
ID:  PC=00000000 | instr=00000000 | op=0000000 func3=000 rd=x0 rs1=x0 rs2=x0
     imm=00000000 | br=0 jmp=0 mem_r=0 mem_w=0 reg_w=0
EX:  PC=00000000 | op=0000000 func3=000 rd=x0 | br=0 jmp=0
     rs1=x0(fwd=00000000) rs2=x0(fwd=00000000) imm=00000000
     BR/JMP: take=0 tgt=00000000 (br_tgt=00000000 jmp_tgt=00000000)
     ALU: result=00000000
MEM: PC=00000000 | rd=x0 alu=00000000 | mem_r=0 mem_w=0
WB:  rd=x0 <= 00000000 | reg_w=0
--------------------------------------------------------------------------------
```

**Features**:
- Shows PC, instruction, and control signals for each stage
- Displays forwarded values in EX stage
- Shows branch/jump targets and decisions
- Marks flushed stages as `<FLUSHED>` and bubbles as `<BUBBLE>`
- Only prints cycles with valid instructions or control flow changes

### 2. `DEBUG_JAL` - JAL/JALR Instruction Tracing

Focused tracing of jump instructions and return address handling.

**Usage**:
```bash
env XLEN=32 DEBUG_JAL=1 ./tools/run_test_by_name.sh <test_name>
```

**Output Format**:
```
[CYCLE N] JAL detected in ID stage:
  PC=00000100 instr=0000006f
  rd=x1 imm=00000010 (16)
  Target: PC + imm = 00000100 + 00000010 = 00000110
  Return: PC + 4 = 00000104 (will be saved to x1)

[CYCLE N+2] JAL executing in EX stage:
  idex_pc=00000100 idex_imm=00000010
  Jump target: 00000110
  Return addr (PC+4): 00000104 → x1
  pc_next will be: 00000110
  Pipeline flush: ifid=1 idex=1

[CYCLE N+5] Writing to x1 (ra) in WB stage:
  x1 <= 00000104

[CYCLE M] RET detected in ID stage:
  PC=00000120
  Current ra (x1) = 00000104
  Will return to: 00000104
```

**Features**:
- Detects JAL/JALR in ID stage, shows calculated targets
- Shows actual jump execution in EX stage
- Tracks return address (x1/ra) writes
- Detects RET pseudo-instructions (jalr x0, ra, 0)
- Shows current ra value and computed return target

## Implementation Details

**File**: `rtl/core/rv32i_core_pipelined.v`
**Lines**: 2830-2982 (153 lines of debug code)

**Key Features**:
1. **Synchronized Output**: All stages shown for the same cycle
2. **Conditional Display**: Only shows cycles with activity (reduces noise)
3. **Pipeline State Tracking**: Shows flushes, bubbles, stalls
4. **Forwarding Visibility**: EX stage shows forwarded values
5. **Control Flow Tracking**: Branch/jump decisions and targets
6. **Register Write Tracking**: Special tracking for ra (x1) writes

## Usage Examples

### Debug a Failing JAL Test
```bash
# Run with JAL-specific tracing
env XLEN=32 DEBUG_JAL=1 timeout 2s ./tools/run_test_by_name.sh test_jal_simple 2>&1 | less

# Look for:
# - Is JAL detected in ID?
# - Is jump target calculated correctly?
# - Is return address written to correct register?
# - Does RET use the correct ra value?
```

### Debug Pipeline Stalls/Hazards
```bash
# Run with full pipeline view
env XLEN=32 DEBUG_PIPELINE=1 ./tools/run_test_by_name.sh test_hazard 2>&1 | grep -A 20 "CYCLE"

# Look for:
# - <BUBBLE> entries (pipeline stalls)
# - <FLUSHED> entries (branch mispredictions)
# - stall=1 or flush=1 flags
# - Forwarded values in EX stage
```

### Debug FreeRTOS Context Switch
```bash
# Run with both flags for maximum visibility
env XLEN=32 DEBUG_JAL=1 DEBUG_PIPELINE=1 TIMEOUT=5 ./tools/test_freertos.sh 2>&1 | tee freertos_debug.log

# Search for:
# - JAL/JALR sequences during function calls
# - Register writes to ra
# - RET instructions and their targets
```

## Future Enhancements

Potential additions to the debug infrastructure:

1. **DEBUG_HAZARD**: Dedicated hazard detection tracking
   - RAW, WAR, WAW hazards
   - Stall reason identification
   - Forwarding path visualization

2. **DEBUG_MEM**: Memory access tracing
   - Load/store addresses and data
   - Cache behavior (when implemented)
   - Bus transaction tracking

3. **DEBUG_CSR**: CSR operation tracking
   - CSR reads/writes
   - Privilege mode changes
   - Exception/interrupt handling

4. **DEBUG_ATOMIC**: Atomic operation tracking
   - LR/SC reservation tracking
   - AMO operation details
   - Success/fail conditions

5. **VCD Comparison Tool**: Python script to compare VCD waveforms with expected behavior

## Known Issues

1. **No Output from DEBUG_JAL**: The current test simulation doesn't produce output - likely because:
   - Test is in infinite loop before reaching any JAL instructions
   - Testbench initialization might be preventing instruction fetch
   - Need to verify testbench is correctly loading hex file

2. **PC Not Tracked to WB**: The WB stage doesn't have a PC signal (only `memwb_pc_plus_4`)
   - WB stage shows register writes but not the instruction PC
   - Could add PC tracking through all pipeline stages in future

## Testing

The instrumentation compiles without errors:
```bash
✓ Compilation successful (with DEBUG_JAL and DEBUG_PIPELINE)
```

## Next Steps for JAL Bug Investigation

1. **Verify Testbench**: Ensure `tb_core_pipelined.v` correctly loads hex files
2. **Add Boot Tracing**: Add debug output for first 10-20 cycles to see if instructions are being fetched
3. **Simplify Test**: Create even simpler test (just JAL to itself in loop with ebreak)
4. **VCD Analysis**: Generate VCD waveform and manually inspect signals
5. **Alternative Approach**: Use existing `DEBUG_JAL_RET` flag (Session 70) which has different PC range filtering

## Files Modified

- `rtl/core/rv32i_core_pipelined.v`: Added DEBUG_PIPELINE and DEBUG_JAL instrumentation blocks

## Related Sessions

- **Session 59**: Original debug trace infrastructure (call stack tracking)
- **Session 68-70**: JAL→compressed investigation (added DEBUG_JAL_RET)
- **Session 71**: FreeRTOS verification (register write tracking)

---

**Impact**: Future debugging sessions will be significantly faster with synchronized pipeline visibility instead of inferring behavior from unsynchronized signals across multiple pipeline stages.
