# Session 48: FreeRTOS Scheduler Debug Plan

**Date**: TBD (Next session after 2025-10-28)
**Issue**: FreeRTOS scheduler starts but tasks never execute
**Goal**: Debug and fix the scheduler/timer interrupt issue

---

## Problem Statement

After successfully implementing enhanced FreeRTOS demos in Session 47, testing revealed that **tasks do not execute after the scheduler starts**. This affects all demos (blinky, enhanced, queue, sync).

**What Works**:
- ✅ FreeRTOS boots
- ✅ Tasks are created
- ✅ Scheduler starts (`vTaskStartScheduler()` returns control)
- ✅ UART output works

**What Doesn't Work**:
- ❌ Tasks never execute (no task output ever appears)
- ❌ Context switches don't happen
- ❌ Simulation runs indefinitely with no progress

---

## Debugging Strategy

### Phase 1: Understand the Expected Flow

**Normal FreeRTOS Operation**:
1. Application calls `vTaskStartScheduler()`
2. Scheduler sets up timer interrupt (CLINT MTIMECMP)
3. Enables interrupts (`mstatus.MIE = 1`, `mie.MTIE = 1`)
4. Jumps to first task
5. Task runs until `vTaskDelay()` or timer interrupt
6. Timer interrupt fires → trap handler → context switch → next task

**Where Are We Getting Stuck?**
- Need to determine: Are we stuck in step 3, 4, or 5?

### Phase 2: Add Debug Instrumentation

#### 2.1: CLINT Debug Tracing

Add to `rtl/peripherals/clint.v`:

```verilog
`ifdef DEBUG_CLINT
  always @(posedge clk) begin
    // Trace MTIMECMP writes
    if (req_valid && req_ready && req_we && (req_addr[15:0] == 16'h4000)) begin
      $display("[CLINT] Cycle %0d: MTIMECMP write = 0x%016h", cycle_count, req_wdata);
    end

    // Trace MTIME reads
    if (req_valid && req_ready && !req_we && (req_addr[15:0] == 16'hBFF8)) begin
      $display("[CLINT] Cycle %0d: MTIME read = 0x%016h", cycle_count, mtime);
    end

    // Trace interrupt assertion
    if (mti_o && !prev_mti) begin
      $display("[CLINT] Cycle %0d: Timer interrupt ASSERTED (mtime=%0d >= mtimecmp=%0d)",
               cycle_count, mtime, mtimecmp);
    end
  end
`endif
```

#### 2.2: Core Interrupt Debug Tracing

Add to `rtl/core/rv32i_core_pipelined.v`:

```verilog
`ifdef DEBUG_INTERRUPT
  always @(posedge clk) begin
    // Trace interrupt enable bits
    if (mstatus_mie_prev != mstatus[3]) begin
      $display("[CORE] Cycle %0d: mstatus.MIE changed: %b -> %b",
               cycle_count, mstatus_mie_prev, mstatus[3]);
    end

    // Trace pending interrupts
    if (mip[7]) begin  // Timer interrupt pending
      $display("[CORE] Cycle %0d: Timer interrupt PENDING (mip[7]=1, mie[7]=%b, mstatus.MIE=%b)",
               cycle_count, mie[7], mstatus[3]);
    end

    // Trace trap entry
    if (trap_taken) begin
      $display("[CORE] Cycle %0d: TRAP TAKEN! PC=0x%08h, mcause=0x%08h",
               cycle_count, pc, mcause_next);
    end
  end
`endif
```

#### 2.3: FreeRTOS Port Debug Prints

Add to `software/freertos/port/port.c`:

```c
void vPortSetupTimerInterrupt(void) {
    uart_puts("[PORT] Setting up timer interrupt\r\n");

    // Read current MTIME
    uint64_t mtime = *(volatile uint64_t*)configMTIME_BASE_ADDRESS;
    uart_puts("[PORT] Current MTIME: ");
    uart_puthex(mtime);
    uart_puts("\r\n");

    // Set MTIMECMP for first tick
    uint64_t mtimecmp = mtime + (configCPU_CLOCK_HZ / configTICK_RATE_HZ);
    *(volatile uint64_t*)configMTIMECMP_BASE_ADDRESS = mtimecmp;
    uart_puts("[PORT] MTIMECMP set to: ");
    uart_puthex(mtimecmp);
    uart_puts("\r\n");

    // Enable timer interrupt in mie
    __asm__ volatile("csrsi mie, 0x80");  // mie.MTIE = 1
    uart_puts("[PORT] Timer interrupt enabled in mie\r\n");

    // Enable global interrupts in mstatus
    __asm__ volatile("csrsi mstatus, 0x8");  // mstatus.MIE = 1
    uart_puts("[PORT] Global interrupts enabled in mstatus\r\n");
}
```

### Phase 3: Systematic Testing

#### Test 1: Verify CLINT Wiring

**Command**:
```bash
env XLEN=32 DEBUG_CLINT=1 TIMEOUT=5 ./tools/test_freertos.sh
```

**Expected Output**:
```
[CLINT] Cycle XXX: MTIMECMP write = 0x000000000000C350  (50,000 cycles for 1ms tick)
[CLINT] Cycle YYY: Timer interrupt ASSERTED (mtime >= mtimecmp)
```

**If No Output**: CLINT not being written to → FreeRTOS port bug

#### Test 2: Verify Interrupt Enables

**Command**:
```bash
env XLEN=32 DEBUG_INTERRUPT=1 TIMEOUT=5 ./tools/test_freertos.sh
```

**Expected Output**:
```
[CORE] mstatus.MIE changed: 0 -> 1
[CORE] Timer interrupt PENDING (mip[7]=1, mie[7]=1, mstatus.MIE=1)
[CORE] TRAP TAKEN! mcause=0x80000007 (timer interrupt)
```

**If No MIE=1**: FreeRTOS not enabling interrupts
**If No TRAP**: Interrupt delivery broken in core

#### Test 3: Verify Trap Handler

Check `software/freertos/port/portASM.S:freertos_trap_handler`:
- Does it save context correctly?
- Does it call `vTaskSwitchContext()`?
- Does it restore context and `mret`?

### Phase 4: Common Issues Checklist

- [ ] **CLINT base addresses correct?**
  - Config: `MTIME=0x0200BFF8`, `MTIMECMP=0x02004000`
  - Match memory map in `docs/MEMORY_MAP.md`?

- [ ] **CLINT connected to core?**
  - Check `rtl/rv_soc.v`: Is CLINT `mti_o` wired to core's `external_interrupts[7]`?

- [ ] **mtvec set correctly?**
  - Should point to `freertos_trap_handler` address
  - Check FreeRTOS port startup code

- [ ] **Tick calculation correct?**
  - 50 MHz / 1000 Hz = 50,000 cycles per tick
  - Is this what MTIMECMP is set to?

- [ ] **MTIME incrementing?**
  - Check CLINT: `mtime <= mtime + 1` each cycle

---

## Quick Debug Commands

```bash
# Build blinky with debug output
cd software/freertos && make clean && make DEMO=blinky

# Test with CLINT debug
env XLEN=32 DEBUG_CLINT=1 TIMEOUT=10 ./tools/test_freertos.sh 2>&1 | grep CLINT

# Test with interrupt debug
env XLEN=32 DEBUG_INTERRUPT=1 TIMEOUT=10 ./tools/test_freertos.sh 2>&1 | grep -E "(INTERRUPT|TRAP|MIE)"

# Extract UART output
env XLEN=32 TIMEOUT=10 ./tools/test_freertos.sh 2>&1 | grep "UART-CHAR" | sed "s/.*0x.. '\(.\)'/\1/;s/.*<LF>/\n/"

# Check for FreeRTOS port debug messages
env XLEN=32 TIMEOUT=10 ./tools/test_freertos.sh 2>&1 | grep -i port
```

---

## Expected Outcomes

### Success Case
1. CLINT shows MTIMECMP write with correct value (50,000 cycles)
2. Core shows `mstatus.MIE` and `mie.MTIE` set to 1
3. After 50,000 cycles, timer interrupt fires
4. Trap handler is entered (mcause = 0x80000007)
5. Task context switch happens
6. Task output appears: `[HIGH] Running` or `[Task1] Tick`

### Failure Cases

**Case A: No MTIMECMP Write**
- **Problem**: FreeRTOS port not setting up timer
- **Fix**: Check `vPortSetupTimerInterrupt()` implementation

**Case B: MTIMECMP Written But No Interrupt**
- **Problem**: CLINT not generating interrupt or not wired to core
- **Fix**: Check CLINT logic and SoC wiring

**Case C: Interrupt Pending But No Trap**
- **Problem**: Interrupts not enabled or trap delivery broken
- **Fix**: Check `mstatus.MIE`, `mie.MTIE`, core interrupt logic

**Case D: Trap Taken But No Task Switch**
- **Problem**: Trap handler broken
- **Fix**: Check `portASM.S:freertos_trap_handler`

---

## Tools and References

**Key Files to Check**:
- `software/freertos/port/port.c` - Timer setup
- `software/freertos/port/portASM.S` - Trap handler
- `software/freertos/config/FreeRTOSConfig.h` - Configuration
- `rtl/peripherals/clint.v` - Timer peripheral
- `rtl/rv_soc.v` - SoC interrupt wiring
- `rtl/core/rv32i_core_pipelined.v` - Interrupt delivery

**Useful Grep Patterns**:
```bash
# Find MTIMECMP writes in code
grep -r "MTIMECMP" software/freertos/

# Find interrupt enable code
grep -r "mstatus\|mie" software/freertos/port/

# Check CLINT wiring in SoC
grep -A 10 "clint.*instantiate" rtl/rv_soc.v
```

---

## Success Criteria

Session 48 is complete when:
1. ✅ Root cause identified (which of the 4 hypotheses is correct)
2. ✅ Fix implemented
3. ✅ Blinky demo shows task output: `[Task1] Tick` and `[Task2] Tick`
4. ✅ Tasks alternate correctly based on delays
5. ✅ Enhanced demo runs and shows priority-based scheduling

---

## Contingency Plan

If debugging takes longer than expected:
- Focus on blinky only (simplest demo)
- Consider minimal test: Single task that just prints and delays
- May need to dive into FreeRTOS port internals
- Could compare with known-working RISC-V FreeRTOS port

**Estimated Time**: 2-4 hours depending on issue complexity

---

**Next Session**: Start with Phase 1 and Phase 2.1 (CLINT debug tracing)
