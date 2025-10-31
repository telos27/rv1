# Session 71: FreeRTOS Verification - No Bugs Found!

**Date**: 2025-10-31
**Focus**: Verify suspected FreeRTOS bugs (uninitialized registers, task return address)
**Result**: ✅ **No bugs found** - Both issues are correct FreeRTOS/RISC-V behavior

---

## Investigation Goal

Following Session 70's finding that the JAL→compressed bug doesn't exist, we suspected two FreeRTOS bugs:
1. **Bug #1**: Uninitialized registers in task stack (26 registers left with 0xa5a5a5a5)
2. **Bug #2**: `configTASK_RETURN_ADDRESS = 0` causing crash at address 0x00

User correctly pointed out that FreeRTOS is production-tested and requested thorough verification.

---

## Investigation Process

### Added Debug Instrumentation

**File**: `rtl/core/register_file.v`

Added register write tracking to detect when t2 (x7) gets corrupted value:

```verilog
`ifdef DEBUG_REG_WRITE
always @(posedge clk) begin
  if (reset_n && rd_wen && rd_addr != 5'h0) begin
    // Track writes to x7 (t2)
    if (rd_addr == 5'd7) begin
      $display("[REG_WRITE] x7 (t2) <= %h", rd_data);
    end
    // Show any write of corruption pattern
    if (rd_data == 32'ha5a5a5a5 || rd_data == 64'ha5a5a5a5a5a5a5a5) begin
      $display("[REG_WRITE_CORRUPT] x%0d <= %h (corruption pattern!)", rd_addr, rd_data);
    end
  end
end
`endif
```

**File**: `tools/test_freertos.sh`

Added support for `DEBUG_REG_WRITE` flag (lines 90-93).

---

## Test Results

### Register Write Tracking

```bash
env XLEN=32 DEBUG_REG_WRITE=1 TIMEOUT=5 ./tools/test_freertos.sh
```

**Result**: Only 3 writes to x7 during entire FreeRTOS run:
- `x7 (t2) <= 8000004e`
- `x7 (t2) <= 80000270`
- `x7 (t2) <= 80000280`

**Key Finding**: The corrupt value `0xa5a5a5a5` is **NEVER written to x7** via register file writes!

---

## Verification of "Bug #1": Uninitialized Registers

### The Observation

In `software/freertos/FreeRTOS-Kernel/portable/GCC/RISC-V/portASM.S:198-229`, `pxPortInitialiseStack` allocates space for 28 registers but only initializes 2:

```asm
addi a0, a0, -(22 * portWORD_SIZE)  # Space for x11-x31 (22 regs)
store_x a2, 0(a0)                   # Initialize x10/a0 = pvParameters
addi a0, a0, -(6 * portWORD_SIZE)   # Space for x5-x9 (6 regs)
load_x t0, xTaskReturnAddress
store_x t0, 0(a0)                   # Initialize x1/ra = return address
```

**Uninitialized**: x5-x9, x11-x31 (26 registers including t2/x7)

### Why This Is CORRECT Behavior

#### RISC-V Calling Convention

From portASM.S comments (lines 147-159):

| Register | ABI Name | Description | Saver |
|----------|----------|-------------|-------|
| x5-7 | t0-2 | Temporaries | **Caller** |
| x8-9 | s0-s1 | Saved registers | Callee |
| x10-17 | a0-a7 | Function arguments | **Caller** |
| x18-27 | s2-s11 | Saved registers | Callee |
| x28-31 | t3-6 | Temporaries | **Caller** |

**Caller-saved registers** (marked "Caller" above):
- Can contain **arbitrary values** when function is called
- Caller must save them before calling if needed
- Callee can overwrite without preserving

**Callee-saved registers**:
- Must be preserved by called function
- Function prologue saves, epilogue restores

#### Task Start as Function Call

When `xPortStartFirstTask` starts a task (portASM.S:232-280):
1. Loads registers from stack (including uninitialized ones)
2. Executes `ret` to jump to task function
3. Task function behaves like normal C function

**C functions initialize caller-saved registers before use**:
- Compiler generates code to set temporaries (t0-t6) before reading them
- Function arguments (a0-a7) either come from caller or are initialized
- No assumption about initial values

#### Verification from Code Analysis

Task functions `vTask1` and `vTask2` (software/freertos/demos/blinky/main_blinky.c:102-145):
- Properly initialize local variables before use
- Use standard C calling convention
- Compiler ensures temporaries are set before read

**Conclusion**: ✅ **NOT A BUG** - Correct RISC-V ABI behavior

---

## Verification of "Bug #2": configTASK_RETURN_ADDRESS = 0

### The Observation

In `software/freertos/config/FreeRTOSConfig.h`:
```c
#define configTASK_RETURN_ADDRESS  0
```

If a task returns, ra=0 causes jump to address 0x00 (_start), potentially running startup code with uninitialized registers.

### Why This Is CORRECT Behavior

#### Official FreeRTOS GCC RISC-V Port Default

From `software/freertos/FreeRTOS-Kernel/portable/GCC/RISC-V/port.c:55-57`:

```c
#ifdef configTASK_RETURN_ADDRESS
    #define portTASK_RETURN_ADDRESS    configTASK_RETURN_ADDRESS
#else
    #define portTASK_RETURN_ADDRESS    0  // ← Default for GCC RISC-V
#endif
```

**Key finding**: The GCC RISC-V port **defaults to 0** if not configured!

#### Comparison with Other Ports

**ARM ports** (e.g., `portable/GCC/ARM_CM3/port.c:107`):
```c
#ifdef configTASK_RETURN_ADDRESS
    #define portTASK_RETURN_ADDRESS    configTASK_RETURN_ADDRESS
#else
    #define portTASK_RETURN_ADDRESS    prvTaskExitError  // ← ARM default
#endif
```

**IAR RISC-V port** (`portable/IAR/RISC-V/port.c:59`):
```c
#define portTASK_RETURN_ADDRESS    prvTaskExitError
```

**Why the difference?**
- ARM ports define `prvTaskExitError()` function (infinite loop + assertion)
- GCC RISC-V port **does not define** `prvTaskExitError()`
- Jumping to 0x00 achieves similar effect (system reset/restart)

#### Design Rationale

1. **Tasks should never return** - Properly written tasks have infinite loops:
   ```c
   void vTask1(void *pvParameters) {
       while (1) {  // ← Infinite loop
           // Task work
           vTaskDelay(...);
       }
   }
   ```

2. **If task returns (programmer error)**:
   - ARM: Trap in `prvTaskExitError()` infinite loop
   - RISC-V: Jump to 0x00, restart system
   - Both effectively halt execution (fail-safe)

3. **Configurable for debugging**:
   - Can define custom handler via `configTASK_RETURN_ADDRESS`
   - Default behavior is acceptable for production

**Conclusion**: ✅ **NOT A BUG** - Correct default for GCC RISC-V port

---

## Source Code Analysis

### Task Stack Initialization

From `portASM.S:198-229`, the initialized stack layout is:

```
Stack (top to bottom):
Offset 30: mstatus (initialized)
Offset 29: xCriticalNesting = 0 (initialized)
Offset 28-8: x31-x11 space (UNINITIALIZED) ← Caller-saved, OK
Offset 7: x10/a0 = pvParameters (initialized)
Offset 6-2: x9-x5 space (UNINITIALIZED) ← Caller-saved, OK
Offset 1: x1/ra = xTaskReturnAddress (initialized)
Offset 0: pxCode = task function (initialized)
```

### First Task Start Sequence

From `portASM.S:232-280`, `xPortStartFirstTask`:

```asm
load_x  sp, pxCurrentTCB        # Get current task's TCB
load_x  sp, 0(sp)               # Load task's stack pointer
load_x  x1, 0(sp)               # Load pxCode into ra
# ... load all other registers (including uninitialized ones)
load_x  x7, 4 * portWORD_SIZE(sp)  # Load t2 (uninitialized!)
# ... more register loads
ret                              # Jump to task function (pxCode)
```

**Key**: Uses `ret` not `mret`, so jumps to ra (pxCode), starting task execution.

### Context Restore (After Task Switch)

From `software/freertos/port/portContext.h:137-189`, `portcontextRESTORE_CONTEXT`:

```asm
load_x  t0, 0(sp)               # Load saved PC
csrw mepc, t0                   # Set exception return address
# ... restore all registers
load_x  x7, 4 * portWORD_SIZE(sp)  # Restore t2
# ... more register restores
mret                             # Return from interrupt
```

**Key**: Uses `mret` not `ret`, so jumps to mepc (saved PC), resuming task.

---

## Actual Bug: Not Register Corruption!

### What We Learned

The infinite loop at PC=0x200e ↔ 0x4ca (Session 68) is **NOT caused by**:
- ❌ Register corruption (t2 never gets 0xa5a5a5a5 written)
- ❌ Uninitialized stack (correct RISC-V behavior)
- ❌ Bad task return address (correct GCC RISC-V default)

### Current FreeRTOS Behavior

Running with standard configuration:
```bash
env XLEN=32 TIMEOUT=2 ./tools/test_freertos.sh
```

**Result**: Infinite loop at ~8000 cycles
```
[8104] 0x0000200e: RET -> 0x000004ca (a0=0x800004f0, depth=4294967295)
[8111] 0x0000200e: RET -> 0x000004ca (a0=0x800004f0, depth=4294967295)
[8118] 0x0000200e: RET -> 0x000004ca (a0=0x800004f0, depth=4294967295)
...
```

This is the **original Session 68 bug** that Sessions 69-70 attempted to debug (JAL→compressed investigation), still unresolved.

---

## Key Insights for Future Debugging

### 1. Trust Production Code

FreeRTOS is widely used in production. When something looks wrong, verify thoroughly:
- Check official documentation
- Compare with other ports
- Understand architecture-specific conventions
- Look for precedent in kernel source

### 2. RISC-V Calling Convention

**Caller-saved** registers (t0-t6, a0-a7, ra):
- Caller must save before function call if needed
- Function can overwrite freely
- **No initialization required** when starting function

**Callee-saved** registers (s0-s11, sp):
- Function must preserve
- Typically saved in function prologue, restored in epilogue

### 3. Register Initialization Expectations

From RISC-V ABI perspective:
- Functions **never assume** caller-saved registers have specific values
- Compiler generates code to initialize before use
- Only **function arguments** (a0-a7) need caller setup

---

## Files Modified

### 1. `rtl/core/register_file.v` (lines 55-69)
- Added `DEBUG_REG_WRITE` instrumentation
- Tracks writes to x7 (t2) and corruption pattern (0xa5a5a5a5)

### 2. `tools/test_freertos.sh` (lines 90-93)
- Added support for `DEBUG_REG_WRITE` environment variable
- Enables register write tracking during FreeRTOS simulation

---

## Conclusion

**Session 71 Results**:
- ✅ Verified "Bug #1" (uninitialized registers) is **correct RISC-V ABI behavior**
- ✅ Verified "Bug #2" (task return address = 0) is **correct GCC RISC-V default**
- ✅ Added useful debug instrumentation for future use
- ⚠️ Real bug remains: Infinite loop at 0x200e ↔ 0x4ca (Session 68 issue)

**Lessons Learned**:
- Always verify assumptions when debugging production code
- Understand architecture-specific calling conventions
- Register "corruption" may be expected behavior per ABI
- Debug instrumentation is valuable even when hypothesis is wrong

**Next Session**: Continue investigating the 0x200e ↔ 0x4ca infinite loop (original Session 68 bug, still unresolved)

---

## Statistics

- **Investigation Time**: Session 71 (2025-10-31)
- **Code Files Modified**: 2 (register_file.v, test_freertos.sh)
- **Tests Run**: FreeRTOS simulation with register tracking
- **Bugs Found**: 0 (both suspected bugs are correct behavior)
- **Debug Instrumentation Added**: Register write tracking
- **Status**: ✅ Verification complete, ready for next debugging phase

---

**Status**: ✅ FreeRTOS verified correct - Focus shifts back to Session 68 infinite loop bug
