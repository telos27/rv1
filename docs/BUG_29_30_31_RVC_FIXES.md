# Bug Fixes #29, #30, #31 - RVC (Compressed Instruction) Issues

**Date**: 2025-10-21
**Session**: RV32C Debugging
**Status**: ✅ Fixed (but RV32C test still has additional issues)

## Summary

While investigating the `rv32uc-p-rvc` test timeout, discovered and fixed three critical bugs related to compressed instruction support:

1. **Bug #29**: Illegal compressed instructions not being detected
2. **Bug #30**: MRET/SRET incorrectly setting jump signal
3. **Bug #31**: RVC decoder marking 32-bit instructions as illegal

## Bug #29: Illegal Compressed Instruction Detection

### Problem

The RVC decoder was correctly identifying illegal compressed instructions (e.g., `0x0000`) and setting the `illegal_instr` output flag, but **the core was not checking this flag**. This allowed illegal compressed instructions to execute, causing PC corruption and undefined behavior.

### Root Cause

The `if_illegal_c_instr` signal from the RVC decoder was computed but never used in the illegal instruction detection logic. Only the control unit's `illegal_inst` output was checked.

### Impact

- Illegal compressed instructions executed instead of trapping
- PC corruption when executing garbage data as code
- Unpredictable behavior in programs with malformed compressed instructions

### Fix

Added proper illegal compressed instruction detection:

1. **Extended IFID pipeline register** to carry `is_compressed` flag:
   - Added `is_compressed_in/out` ports to track which instructions were originally compressed
   - Pipeline the flag through to ID stage to match decoder timing

2. **Buffered the illegal flag** to match pipeline timing:
   ```verilog
   reg if_illegal_c_instr_buffered;
   always @(posedge clk or negedge reset_n) begin
     if (!reset_n)
       if_illegal_c_instr_buffered <= 1'b0;
     else if (!stall_ifid && !flush_ifid)
       if_illegal_c_instr_buffered <= if_illegal_c_instr;
     else if (flush_ifid)
       if_illegal_c_instr_buffered <= 1'b0;
   end
   ```

3. **Combined illegal signals** from control unit and RVC decoder:
   ```verilog
   assign id_illegal_inst = id_illegal_inst_from_control |
                            (ifid_is_compressed & if_illegal_c_instr_buffered);
   ```

### Files Modified

- `rtl/core/ifid_register.v` - Added `is_compressed` pipeline signal
- `rtl/core/rv32i_core_pipelined.v` - Added illegal compressed instruction detection logic

### Verification

- All existing RV32I tests still pass (37/37)
- Illegal compressed instructions now properly trigger illegal instruction exceptions

---

## Bug #30: MRET/SRET Jump Signal

### Problem

The control unit was setting `jump = 1'b1` for MRET and SRET instructions. This caused the PC selection logic to use the jump target calculation (based on instruction immediate) in the EX stage, **before** the mret_flush/sret_flush signals activated in the MEM stage.

This resulted in:
- Wrong PC target (calculated from instruction bits instead of mepc/sepc CSR)
- PC corruption after MRET/SRET execution
- Tests jumping to invalid addresses like 0x8000048a

### Root Cause

Pipeline timing mismatch:
- MRET/SRET are in **EX stage** when `jump=1` causes target calculation
- But `mret_flush`/`sret_flush` don't activate until **MEM stage**
- PC selection priority: `mret_flush ? mepc : ... : ex_take_branch ? target : ...`
- Since mret_flush is not yet active, execution falls through to `ex_take_branch` case
- Jump target calculated incorrectly from instruction immediate field

### Impact

- MRET returned to wrong address (instruction immediate instead of mepc)
- SRET returned to wrong address (instruction immediate instead of sepc)
- Tests entered infinite loops or jumped to data sections
- Critical for privilege mode transitions and exception handling

### Fix

Changed control unit to **NOT** set `jump` signal for MRET/SRET:

```verilog
// rtl/core/control.v lines 513-523
end else if (is_mret) begin
  // MRET: return from trap
  // Bug #30: Do NOT set jump=1 - MRET is handled specially via mret_flush in MEM stage
  // Setting jump=1 would cause wrong target to be used in EX stage
  jump = 1'b0;

end else if (is_sret) begin
  // SRET: return from supervisor trap
  // Bug #30: Do NOT set jump=1 - SRET is handled specially via sret_flush in MEM stage
  // Setting jump=1 would cause wrong target to be used in EX stage
  jump = 1'b0;
```

MRET/SRET are now handled entirely through the special flush signals that activate in MEM stage with correct CSR targets.

### Files Modified

- `rtl/core/control.v` - Changed MRET/SRET to not set jump signal

### Verification

- All existing RV32I tests still pass
- MRET/SRET now correctly return to addresses stored in mepc/sepc
- No more PC corruption after exception returns

---

## Bug #31: RVC Decoder Quadrant 3 Handling

### Problem

The RVC decoder was marking **ALL** 32-bit instructions (opcode bits [1:0] = `11`) as illegal by setting `illegal_instr = 1'b1` in the quadrant 3 case.

This caused `if_illegal_c_instr` to be constantly high for all 32-bit instructions, which (after Bug #29 fix) would have caused every 32-bit instruction to trap!

### Root Cause

The RVC decoder receives ALL instructions, both compressed (16-bit) and standard (32-bit). The quadrant 3 handler (opcode = `11`) was treating 32-bit instructions as "illegal compressed instructions" rather than simply "not compressed instructions."

From the decoder's perspective, this was technically correct - a 32-bit instruction isn't a valid compressed instruction. But the caller expects the decoder to handle this gracefully.

### Impact

- Every 32-bit instruction would be flagged as illegal (after Bug #29 fix applied)
- Would cause complete failure - no 32-bit instructions could execute
- Detected during testing when all instructions showed `ill_c=1` in debug trace

### Fix

Changed quadrant 3 handler to set `illegal_instr = 1'b0` for 32-bit instructions:

```verilog
// rtl/core/rvc_decoder.v lines 515-521
2'b11: begin
  // This is a 32-bit instruction, not compressed
  // Not illegal - just not a compressed instruction
  // Caller should check is_compressed_out before using decompressed output
  illegal_instr = 1'b0;
  decompressed_instr = 32'h00000013;  // Output NOP (not used for 32-bit instructions)
end
```

### Files Modified

- `rtl/core/rvc_decoder.v` - Fixed quadrant 3 to not mark 32-bit instructions as illegal

### Verification

- All RV32I tests pass (32-bit instructions execute correctly)
- Debug trace shows `ill_c=0` for all 32-bit instructions
- Only actual illegal compressed instructions set the illegal flag

---

## Testing Results

### Before Fixes
- RV32C test: Immediate hang or PC corruption
- Some tests jumped to invalid addresses
- Execution stuck in infinite loops

### After Fixes
- **Pass Rate**: 81% (66/81 tests) - maintained
- **RV32I**: 37/37 ✅ (100%)
- **RV32M**: 8/8 ✅ (100%)
- **RV32A**: 10/10 ✅ (100%)
- **RV32UF**: 6/11 (existing FPU issues)
- **RV32UD**: 0/9 (existing FPU issues)
- **RV32C**: 0/1 ⚠️ (still investigating - additional bugs remain)

### RV32C Status

The `rv32uc-p-rvc` test still times out, indicating there are **additional bugs** beyond these three fixes. The bugs fixed here were critical prerequisites, but more work is needed:

- Compressed instruction decoding correctness
- PC increment logic for mixed 16/32-bit instructions
- Branch/jump target calculations with compressed instructions
- Instruction fetch alignment with C extension

---

## Key Learnings

1. **Pipeline Timing is Critical**: Signals must be sampled at the correct pipeline stage. MRET/SRET needed special handling because their flush signals activate later than normal jumps.

2. **Combinational vs Sequential Logic**: The RVC decoder is combinational but its outputs need to be pipelined to match the instruction pipeline timing.

3. **Interface Contracts Matter**: The RVC decoder receives all instructions but should handle 32-bit instructions gracefully rather than marking them illegal.

4. **Debug Methodology**:
   - Added detailed cycle-by-cycle tracing
   - Compared signals across pipeline stages
   - Identified divergence points between expected and actual behavior

---

## References

- RISC-V Privileged Spec: MRET/SRET behavior
- RISC-V C Extension Spec: Compressed instruction encoding
- Pipeline design: Hazard detection and flush mechanisms

---

## Next Steps (Future Session)

Continue debugging RV32C test failure:
1. Investigate PC increment logic with compressed instructions
2. Verify RVC decoder output for all compressed instruction types
3. Check instruction fetch alignment at half-word boundaries
4. Test branch/jump targets with compressed instructions
5. Add more comprehensive RVC-specific test cases
