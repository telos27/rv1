# Session 29: IMEM Read Bug Investigation (2025-10-27)

## Status
🔍 **MAJOR BUG IDENTIFIED - INSTRUCTION MEMORY READ FAILURE AT RUNTIME**

## Problem Summary

FreeRTOS simulation encounters illegal instruction exceptions with `mtval=0x00000013` (NOP), but investigation revealed the root cause is **instruction memory returning zeros instead of actual instruction data** at specific addresses during runtime.

## Investigation Timeline

### 1. Setup & Build (Completed ✅)

**FreeRTOS Version**: Switched from V11.1.0 to V10.5.1 per user request
- Cloned FreeRTOS-Kernel V10.5.1
- Installed picolibc (required dependency)
- Successfully built FreeRTOS binary: 17,656 bytes code, 794KB data

### 2. Exception Trace Analysis (Completed ✅)

**First Trap at Cycle 607**:
```
[TRAP] Exception/Interrupt detected at cycle 607
       mcause = 0x0000000000000002 (interrupt=x, code=2)  ← Illegal instruction
       mepc   = 0x0000210c
       mtval  = 0x00000013  ← NOP instruction!
       PC     = 0x00002500  (trap handler)
```

**Pipeline State When Trap Taken**:
```
Cycle 607:
  IF: PC=0x00002110, raw=0x00000000, final=0x00000013, compressed=1
  ID: instruction=0x00000013, valid=1  ← NOP in ID stage!
  EX: instruction=0x00000013, valid=1
  Exception: code=2, gated=1
```

**Key Discovery**: By the time the trap is taken, the faulting instruction has already left the ID stage and been replaced by a pipeline bubble (NOP). This is why `mtval` contains 0x00000013.

### 3. Binary Verification (Completed ✅)

Checked actual instruction at address 0x210c in ELF:
```
objdump:
    210c:	27068693          	addi	a3,a3,624
```

**Instruction encoding**: `0x27068693` - a perfectly legal ADDI instruction!

Verified hex file contains correct data:
```
Address 0x210c in hex file: 93 86 06 27 (little-endian)
→ 0x27068693 ✓ CORRECT
```

ELF section layout:
```
.text: 0x000044e8 bytes (17,640) starting at VMA 0x00000000
.data: 0x00000010 bytes starting at VMA 0x80000000
```

Address 0x210c (8,448 bytes) is **well within** the .text section (0x0 to 0x44E7).

### 4. Memory Initialization Check (Completed ✅)

Added debug output to `instruction_memory.v` to verify initialization:
```
=== Instruction Memory Loaded ===
MEM_FILE: software/freertos/build/freertos-rv1.hex
Instructions around 0x210c:
  [0x2108] = 0x27068713
  [0x210c] = 0x27068693  ← CORRECT DATA IN MEMORY!
  [0x2110] = 0xcd3db775
```

**Verified**: Memory array contains the correct instruction bytes after initialization.

### 5. Runtime Fetch Analysis (Completed ✅)

Added fetch monitoring to track what IMEM returns during execution:

```
[IMEM-FETCH] addr=0x00002108, hw_addr=0x00002108, instr=0x27068713  ← WORKS! ✓
[IMEM-FETCH] addr=0x0000210c, hw_addr=0x0000210c, instr=0x00000000  ← FAILS! ✗
[IMEM-FETCH] addr=0x0000210e, hw_addr=0x0000210e, instr=0x00000000  ← FAILS! ✗
[IMEM-FETCH] addr=0x00002110, hw_addr=0x00002110, instr=0x00000000  ← FAILS! ✗
```

### 6. Pipeline Trace Analysis (Completed ✅)

Detailed trace around cycle 605 (when PC=0x210c):

```
[PIPELINE] Cycle 603:
  IF: PC=0x00002108, raw=0x27068713, final=0x27068713, compressed=0  ← Works!

[PIPELINE] Cycle 605:
  IF: PC=0x0000210c, raw=0x00000000, final=0x00000013, compressed=1  ← Zeros!
  ID: instruction=0x27068713, valid=1
  EX: instruction=0x00000013, valid=0

[PIPELINE] Cycle 605 (later in cycle):
  IF: PC=0x0000210e, raw=0x00000000, final=0x00000013, compressed=1  ← Zeros!
  ID: instruction=0x00000013, valid=1
  EX: instruction=0x27068713, valid=1

[PIPELINE] Cycle 607:
  IF: PC=0x00002110, raw=0x00000000, final=0x00000013, compressed=1  ← Zeros!
  ID: instruction=0x00000013, valid=1
  EX: instruction=0x00000013, valid=1
  Exception: code=2, gated=1  ← Illegal instruction exception!
```

## Root Cause Identified

**CRITICAL BUG**: Instruction memory read logic returns `0x00000000` when fetching from addresses 0x210c, 0x210e, 0x2110, despite containing correct data.

### Evidence Summary

1. ✅ Memory initialization is correct (verified at startup)
2. ✅ Hex file contains correct data
3. ✅ Fetch from 0x2108 works correctly
4. ✗ Fetch from 0x210c returns zeros (FAILS)
5. ✗ Fetch from 0x210e returns zeros (FAILS)
6. ✗ Fetch from 0x2110 returns zeros (FAILS)
7. ✅ No memory writes detected to these addresses

### Memory Read Logic (rtl/memory/instruction_memory.v)

```verilog
// Memory array (byte-addressed)
reg [7:0] mem [0:MEM_SIZE-1];  // MEM_SIZE = 65536 (64KB)

// Address computation
wire [XLEN-1:0] masked_addr = addr & (MEM_SIZE - 1);
wire [XLEN-1:0] halfword_addr = {masked_addr[XLEN-1:1], 1'b0};

// Instruction fetch
assign instruction = {mem[halfword_addr+3], mem[halfword_addr+2],
                      mem[halfword_addr+1], mem[halfword_addr]};
```

For `addr=0x210c`:
- `masked_addr = 0x210c & 0xFFFF = 0x210c` ✓
- `halfword_addr = 0x210c` (already even) ✓
- Should fetch: `{mem[0x210f], mem[0x210e], mem[0x210d], mem[0x210c]}`
- Expected result: `0x27068693` ✓
- **Actual result: `0x00000000` ✗**

## Hypotheses for Investigation

### Hypothesis 1: Array Indexing Width Mismatch
- Array `mem` has 65536 elements (needs 16-bit index)
- `halfword_addr` is 32-bit (XLEN=32)
- Verilog should truncate to 16 bits, but maybe there's an issue?

### Hypothesis 2: Memory Bank Boundary Issue
- Address 0x2108 works, but 0x210c fails
- 4-byte offset between working and failing addresses
- Could be related to memory organization or banking?

### Hypothesis 3: Timing/Synchronization Issue
- Memory contains correct data at initialization
- Returns zeros at runtime
- Could be a clocking or synchronization problem?

### Hypothesis 4: Synthesis/Simulation Artifact
- Icarus Verilog specific behavior?
- Array access with 32-bit index on 16-bit array?

## Impact

**Severity**: CRITICAL - Blocks FreeRTOS execution
**Scope**: Any instruction fetch from addresses ≥ 0x210c fails
**Workaround**: None identified yet

## Files Modified

1. **rtl/memory/instruction_memory.v**
   - Added initialization debug output for address 0x210c
   - Added runtime fetch monitoring (posedge clk)
   - Added write monitoring for debugging

2. **tb/integration/tb_freertos.v**
   - Added detailed pipeline trace (cycles 603-612)
   - Added trap detail output (ifid_instruction, if_instruction, etc.)
   - Added cycle counter every 1000 cycles

3. **software/freertos/FreeRTOS-Kernel/**
   - Switched from V11.1.0 to V10.5.1

## Next Session Tasks

1. **Isolate IMEM module**: Create standalone testbench to test instruction_memory.v in isolation
2. **Test array indexing**: Verify if 32-bit index on 16-bit array works correctly in Icarus Verilog
3. **Check synthesis**: Try with different simulator (Verilator?) to rule out tool-specific issue
4. **Memory access patterns**: Test if specific addresses or patterns trigger the bug
5. **Simplify design**: Try removing XLEN parameterization, hard-code to 32-bit

## References

- Session 28: RVC FP Decoder Enhancement
- Session 27: Critical Bug Fixes (WB→ID forwarding, DMEM address decode)
- Session 25: First UART Output from FreeRTOS
- RISC-V ISA Spec: Instruction Memory Organization

## Debug Commands

```bash
# Rebuild FreeRTOS
cd software/freertos && make clean && make

# Run with debug output
env XLEN=32 TIMEOUT=10 ./tools/test_freertos.sh 2>&1 | grep "IMEM-FETCH"

# Check instruction at address
riscv64-unknown-elf-objdump -d software/freertos/build/freertos-rv1.elf | grep -A2 "210c:"

# Verify hex file
riscv64-unknown-elf-objdump -s -j .text software/freertos/build/freertos-rv1.elf | grep " 2100 "
```

---

**Session Duration**: ~3 hours
**Commits**: Pending
**Achievement Level**: 🔍 Major progress - root cause identified, but fix still needed
