# Session 64: Stack Initialization Investigation - Session 63 Corrected

**Date**: 2025-10-29
**Status**: ✅ **INVESTIGATION COMPLETE** - Stack initialization is CORRECT, bug is elsewhere
**Branch**: main (a6c8919)

---

## Session Goal

Investigate Session 63's conclusion that FreeRTOS task stacks are uninitialized. Verify whether `pxPortInitialiseStack()` is working correctly.

## TL;DR - Session 63 Was Wrong!

**Key Findings:**
1. ✅ **`pxPortInitialiseStack()` IS working correctly** - Confirmed with memory write watchpoints
2. ✅ **Task stacks ARE properly initialized** - ra=0 is the CORRECT initial value (not corruption!)
3. ✅ **Stack initialization sequence verified** - memset(0xa5) then pxPortInitialiseStack() writes 0x0
4. ❌ **Session 63's diagnosis was INCORRECT** - "Uninitialized stack" conclusion was based on misunderstanding

**The real bug is NOT stack initialization!** Investigation continues in next session.

---

## Investigation Process

### Step 1: Verify `pxPortInitialiseStack()` Code

**Location**: `software/freertos/FreeRTOS-Kernel/portable/GCC/RISC-V/portASM.S:198-229`

**Function signature:**
```c
StackType_t *pxPortInitialiseStack(StackType_t *pxTopOfStack,
                                   TaskFunction_t pxCode,
                                   void *pvParameters);
```

**Stack layout created** (RV32, bottom to top):
```
sp+0:   pxCode (task function pointer, e.g., 0x1b40 for vTask1)
sp+4:   xTaskReturnAddress (return address if task exits - always 0)
sp+8:   [chip-specific registers - FPU disabled, so 0 words]
sp+12:  x5 (t0) = 0
sp+16:  x6 (t1) = 0
...
sp+28:  x10 (a0) = pvParameters
sp+32:  x11 (a1) = 0
...
sp+116: xCriticalNesting = 0
sp+120: mstatus (with MPIE and MPP bits set)
```

**Key observation:** sp+4 (xTaskReturnAddress) is **SUPPOSED to be 0**! This is standard FreeRTOS behavior.

**From `port.c:54-58`:**
```c
#ifdef configTASK_RETURN_ADDRESS
    #define portTASK_RETURN_ADDRESS    configTASK_RETURN_ADDRESS
#else
    #define portTASK_RETURN_ADDRESS    0
#endif
```

**From `FreeRTOSConfig.h:99`:**
```c
#define configTASK_RETURN_ADDRESS       0
```

### Step 2: Check Memory Layout

**Task stacks from ELF symbols:**
```
ucHeap:            0x800004e0 - 0x800404e0 (256KB dynamic heap)
uxIdleTaskStack:   0x800404e0 - 0x800406e0 (512 bytes, static BSS)
uxTimerTaskStack:  0x800406e0 - 0x80040ae0 (1024 bytes, static BSS)
```

**Session 63 findings:**
- Task A sp=0x80040a90 → Inside `uxTimerTaskStack` (Timer task, static)
- Task B sp=0x80000864 → Inside `ucHeap` (vTask1 or vTask2, dynamic)

**Conclusion:** Task B's stack at 0x80000864 is a valid heap allocation.

### Step 3: Add Memory Write Watchpoint

**Added to `tb/integration/tb_freertos.v:251-261`:**
```verilog
// Memory write watchpoint - Track writes to Task B's stack (sp=0x80000864)
// Watch ra location: sp+4 = 0x80000868
always @(posedge clk) begin
  if (reset_n && DUT.core.exmem_mem_write && DUT.core.exmem_valid) begin
    // Check if writing to address range 0x80000860-0x80000880 (Task B stack)
    if (DUT.core.exmem_alu_result >= 32'h80000860 && DUT.core.exmem_alu_result <= 32'h80000880) begin
      $display("[STACK-WRITE] Cycle %0d: PC=0x%08h writes 0x%08h to addr=0x%08h",
               cycle_count, DUT.core.exmem_pc, DUT.core.exmem_mem_write_data, DUT.core.exmem_alu_result);
    end
  end
end
```

### Step 4: Run Test and Capture All Writes

**Command:**
```bash
env XLEN=32 TIMEOUT=10 timeout 70s ./tools/test_freertos.sh 2>&1 | grep "STACK-WRITE.*0x80000868"
```

**Results:**
```
[STACK-WRITE] Cycle 13865: PC=0x00002004 writes 0x000000a5 to addr=0x80000868
[STACK-WRITE] Cycle 13865: PC=0x00002004 writes 0x000000a5 to addr=0x80000868
[STACK-WRITE] Cycle 14945: PC=0x00000100 writes 0x00000000 to addr=0x80000868
[STACK-WRITE] Cycle 14947: PC=0x00000100 writes 0x00000000 to addr=0x80000868
```

**Analysis:**

1. **Cycle 13865**: PC=0x2004 writes **0xa5**
   - Code: `memset()` at address 0x2004 (loop: `sb a1, 0(t1)`)
   - Called by: `prvInitialiseNewTask.constprop.0` at 0x4c6 (line: `li a1, 165`)
   - Purpose: Debug fill pattern for heap allocations (standard FreeRTOS feature)

2. **Cycle 14945**: PC=0x100 writes **0x00000000**
   - Code: `pxPortInitialiseStack()` at address 0x100 (line: `sw t0, 0(a0)`)
   - Purpose: Write `xTaskReturnAddress` (loaded from 0x800002f8 = symbol `xTaskReturnAddress`)
   - Value: 0x00000000 (correct, matches `configTASK_RETURN_ADDRESS`)

3. **After cycle 14947**: No further writes to 0x80000868 - value remains 0x00000000 ✅

**Disassembly verification:**
```assembly
000000d2 <pxPortInitialiseStack>:
  d2:   csrr  t0, mstatus
  ...
  f8:   auipc t0, 0x80000         # Load address of xTaskReturnAddress
  fc:   lw    t0, 512(t0)         # Load value from 0x800002f8
  100:  sw    t0, 0(a0)           # ← THIS WRITE at cycle 14945!
```

### Step 5: Verify Stack Initialization Sequence

**Full sequence for Task B stack:**
1. **xTaskCreate()** calls **pvPortMalloc()** → allocates heap at 0x80000xxx
2. **prvInitialiseNewTask()** calls **memset(stack, 0xa5, size)** → fills with debug pattern
3. **prvInitialiseNewTask()** calls **pxPortInitialiseStack()** → writes proper initial context
4. **pxPortInitialiseStack()** writes:
   - sp+0: Task function pointer
   - sp+4: **xTaskReturnAddress = 0** ← CORRECT VALUE!
   - sp+8-120: Zeroed registers, mstatus

**Conclusion:** Stack initialization is CORRECT! The value ra=0 is EXPECTED, not corruption!

---

## Why Session 63 Got It Wrong

**Session 63's incorrect reasoning:**
> "Task B's stack contains zeros or 0xa5a5a5a5 (uninitialized memory)"

**Reality:**
- The 0xa5 pattern is from `memset()` in `prvInitialiseNewTask()` (FreeRTOS debug feature)
- The 0x00000000 at sp+4 is from `pxPortInitialiseStack()` writing `xTaskReturnAddress`
- Both are **intentional and correct**!

**Session 63 saw:**
```
memory[0x80000868] = 0x00000000  (ra location)
```

**Session 63 concluded:** "Stack uninitialized! ra should have a valid return address!"

**Reality:** ra=0 is the CORRECT initial value for a new task. Tasks are not supposed to return - if they do, returning to address 0 will trigger a fault.

---

## What This Means

**CPU Hardware Status:** ✅ All still validated (no change from Session 63)
- Pipeline correct ✅
- Register file correct ✅
- CSRs correct ✅
- Trap handling correct ✅
- MRET correct (Session 62) ✅

**Stack Initialization Status:** ✅ **VERIFIED WORKING CORRECTLY**
- `pxPortInitialiseStack()` called and executes properly ✅
- Writes correct initial values to stack ✅
- Stack not corrupted after initialization ✅

**The Real Bug Is Elsewhere!**

Possible remaining causes:
1. **CPU JAL/JALR bug** - Instructions not writing return addresses to rd correctly
2. **Register file forwarding bug** - ra writes being lost in pipeline
3. **Trap handler bug** - Context save/restore corrupting ra during switches
4. **Different root cause** - The crash mechanism is different than diagnosed

---

## Next Steps (Session 65)

1. **Test JAL instruction** - Verify JAL at PC=0x1b46 writes 0x1b4a to ra
2. **Test register file** - Check if writes to x1 (ra) are being lost
3. **Test trap handler** - Verify context save/restore preserves ra correctly
4. **Re-analyze crash** - Session 63 trace may have misidentified the failure point

---

## Files Modified

- `tb/integration/tb_freertos.v` (lines 251-261) - Added stack write watchpoint
- `docs/SESSION_63_FREERTOS_CONTEXT_SWITCH_BUG.md` - Added correction notice

---

## Lessons Learned

1. **Never assume without verification** - Session 63's conclusion looked plausible but was wrong
2. **Memory watchpoints are essential** - Direct observation beats inference every time
3. **Understand the expected behavior** - ra=0 for new tasks is standard FreeRTOS design
4. **Debug patterns can mislead** - 0xa5 fill made stack look "uninitialized" but wasn't

---

## References

- FreeRTOS port code: `software/freertos/FreeRTOS-Kernel/portable/GCC/RISC-V/portASM.S`
- Stack initialization: `pxPortInitialiseStack()` at line 198
- Task creation: FreeRTOS `prvInitialiseNewTask()` in tasks.c
- Session 63 (CORRECTED): `docs/SESSION_63_FREERTOS_CONTEXT_SWITCH_BUG.md`
