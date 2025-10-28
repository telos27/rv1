# Session 47: FreeRTOS Enhanced Testing & Optimization

**Date**: 2025-10-28
**Status**: 🔄 In Progress
**Phase**: Phase 2 Optimization - Enhanced FreeRTOS Validation

---

## Executive Summary

After successfully resolving the MULHU bug in Session 46 and getting FreeRTOS to boot and start the scheduler, Session 47 focuses on **comprehensive FreeRTOS validation** through enhanced testing before proceeding to Phase 3 (RV64 upgrade).

**Goals**:
1. Create enhanced FreeRTOS demos that thoroughly exercise the scheduler
2. Test synchronization primitives (queues, semaphores, mutexes)
3. Validate task priorities and preemption
4. Debug printf() duplication issue (optional)
5. Build confidence in RV32 implementation before RV64 work

---

## Background: Why Enhanced Testing?

### Current Status (Post-Session 46)
- ✅ FreeRTOS boots successfully
- ✅ Scheduler starts
- ✅ Tasks are created
- ⚠️ **Limited visibility**: Current demo uses long delays (500ms, 1000ms), so tasks don't actually run within simulation window (5-10s)

### What We Need to Validate
1. **Task Switching**: Does the scheduler correctly save/restore task context?
2. **Priority Preemption**: Do high-priority tasks preempt lower-priority ones?
3. **Queue IPC**: Can tasks communicate via queues without data corruption?
4. **Synchronization**: Do semaphores and mutexes work correctly?
5. **Timer Interrupts**: Does CLINT correctly trigger context switches?
6. **Memory Management**: No stack overflows or heap corruption?

### The Problem with Current Demo
```c
// Current: tasks/blinky/main_blinky.c
void vTask1(void *pvParameters) {
    while (1) {
        puts("[Task1] Tick");
        vTaskDelay(pdMS_TO_TICKS(500));  // ← 500ms delay = 25M cycles!
    }
}
```

**Issue**: At 50MHz, 500ms = 25,000,000 cycles. Our simulation timeout is 500,000 cycles (10ms). Tasks never actually get to print during simulation!

---

## Test Suite Design

### Test 1: Enhanced Multitasking Demo
**File**: `software/freertos/demos/enhanced/main_enhanced.c`
**Goal**: Immediate output, visible task switching

```c
// Multiple tasks with different priorities
void vHighPriorityTask(void *pvParameters) {
    for (int i = 0; i < 10; i++) {
        puts("[HIGH] Running");
        vTaskDelay(1);  // ← 1ms = 50k cycles (visible in sim!)
    }
}

void vMediumPriorityTask(void *pvParameters) {
    for (int i = 0; i < 10; i++) {
        puts("[MED] Running");
        vTaskDelay(2);
    }
}

void vLowPriorityTask(void *pvParameters) {
    while (1) {
        puts("[LOW] Running");
        vTaskDelay(5);
    }
}
```

**Expected Output**:
```
[HIGH] Running
[HIGH] Running
[MED] Running
[HIGH] Running
[LOW] Running
...
```

**Validates**:
- Task switching works
- Priority-based scheduling
- Timer interrupts trigger context switches
- Context save/restore preserves state

---

### Test 2: Queue Communication
**File**: `software/freertos/demos/queue/main_queue.c`
**Goal**: Producer-consumer IPC

```c
QueueHandle_t xQueue;

void vProducer(void *pvParameters) {
    uint32_t counter = 0;
    for (int i = 0; i < 5; i++) {
        xQueueSend(xQueue, &counter, 100);
        puts("[PROD] Sent");
        counter++;
        vTaskDelay(1);
    }
}

void vConsumer(void *pvParameters) {
    uint32_t received;
    for (int i = 0; i < 5; i++) {
        if (xQueueReceive(xQueue, &received, 100) == pdTRUE) {
            puts("[CONS] Received");
            // Note: Can't use printf() due to duplication bug
        }
        vTaskDelay(1);
    }
}
```

**Validates**:
- Queue send/receive works
- FIFO ordering preserved
- Blocking/unblocking on empty/full queues
- No data corruption in queue buffer

---

### Test 3: Synchronization Primitives
**File**: `software/freertos/demos/sync/main_sync.c`
**Goal**: Semaphores and mutexes

```c
SemaphoreHandle_t xBinarySem;
SemaphoreHandle_t xMutex;
uint32_t shared_counter = 0;

void vSignalTask(void *pvParameters) {
    for (int i = 0; i < 5; i++) {
        puts("[SIGNAL] Giving semaphore");
        xSemaphoreGive(xBinarySem);
        vTaskDelay(2);
    }
}

void vWaitTask(void *pvParameters) {
    while (1) {
        xSemaphoreTake(xBinarySem, portMAX_DELAY);
        puts("[WAIT] Took semaphore");
    }
}

void vMutexTask(void *pvParameters) {
    for (int i = 0; i < 5; i++) {
        xSemaphoreTake(xMutex, portMAX_DELAY);
        shared_counter++;  // Protected critical section
        xSemaphoreGive(xMutex);
        vTaskDelay(1);
    }
}
```

**Validates**:
- Binary semaphores (task signaling)
- Mutexes (critical section protection)
- Blocking on unavailable semaphore
- No race conditions on shared data

---

### Test 4: Software Timers
**File**: `software/freertos/demos/timers/main_timers.c`
**Goal**: FreeRTOS timer API

```c
void vTimerCallback(TimerHandle_t xTimer) {
    puts("[TIMER] Callback executed");
}

void vTimerTest(void *pvParameters) {
    TimerHandle_t xTimer = xTimerCreate("Timer", pdMS_TO_TICKS(10),
                                         pdTRUE, 0, vTimerCallback);
    xTimerStart(xTimer, 0);
    vTaskDelay(100);  // Let timer fire multiple times
}
```

**Validates**:
- Timer daemon task runs
- Callbacks execute at correct intervals
- One-shot vs auto-reload timers

---

### Test 5: Stress Test
**File**: `software/freertos/demos/stress/main_stress.c`
**Goal**: Extended operation, many tasks

```c
#define NUM_TASKS 8

void vStressTask(void *pvParameters) {
    uint32_t task_id = (uint32_t)pvParameters;
    for (int i = 0; i < 20; i++) {
        // Rapid context switching
        vTaskDelay(1);
    }
}

void vStressMain(void) {
    for (int i = 0; i < NUM_TASKS; i++) {
        xTaskCreate(vStressTask, "Stress", 256, (void*)i, 1, NULL);
    }
    vTaskStartScheduler();
}
```

**Validates**:
- Many tasks don't cause stack corruption
- Heap allocation/deallocation robust
- No scheduler hangs under load
- Extended runtime stability

---

## Known Issues to Debug

### Issue 1: printf() Duplication (Session 43)

**Symptom**:
```c
printf("Hello");  // Output: "HHeelllloo"
```

**Workaround**:
```c
puts("Hello");    // Output: "Hello" (correct)
```

**Root Cause Hypotheses**:
1. **UART TX FIFO issue**: Double-write to THR?
2. **picolibc syscalls**: `_write()` called twice?
3. **FreeRTOS context switch**: Interrupt during printf()?

**Debug Plan** (Optional for Session 47):
1. Add debug traces to `software/freertos/lib/syscalls.c:_write()`
2. Check if `_write()` is called once or twice per character
3. Add UART driver traces to see if THR is written once or twice
4. Test with interrupts disabled during printf()

**Priority**: Low (workaround exists with puts())

---

## Implementation Plan

### Step 1: Create Enhanced Demo Structure
```
software/freertos/demos/
├── blinky/           # Current demo (keep for baseline)
├── enhanced/         # New: Priority-based multitasking
├── queue/            # New: Queue IPC test
├── sync/             # New: Semaphore/mutex test
├── timers/           # New: Software timer test
└── stress/           # New: Stress test
```

### Step 2: Makefile Updates
Add build targets for each demo:
```makefile
# Build specific demo
DEMO ?= blinky  # Default to blinky

all: build/freertos-$(DEMO).hex

build/freertos-$(DEMO).elf: demos/$(DEMO)/main_$(DEMO).c ...
	$(CC) $(CFLAGS) $^ -o $@
```

### Step 3: Test Execution
```bash
# Test enhanced demo
env XLEN=32 TIMEOUT=10 make test-freertos DEMO=enhanced

# Test queue demo
env XLEN=32 TIMEOUT=10 make test-freertos DEMO=queue

# Stress test (longer timeout)
env XLEN=32 TIMEOUT=30 make test-freertos DEMO=stress
```

### Step 4: Validation Criteria
For each demo, verify:
- ✅ Boot messages appear
- ✅ Expected output sequence matches
- ✅ No crashes or hangs
- ✅ All tasks complete successfully
- ✅ Final "TEST PASSED" message appears

---

## Success Criteria

**Phase 2 Complete When**:
1. ✅ All 5 enhanced demos build successfully
2. ✅ All demos produce expected output
3. ✅ No scheduler crashes or data corruption observed
4. ✅ Stress test runs for extended period without issues
5. ✅ Documentation updated (CLAUDE.md, OS_INTEGRATION_PLAN.md)

**Optional Bonus**:
- 🎁 printf() duplication bug fixed (if time permits)
- 🎁 UART interrupt-driven I/O (Phase 1.4)

---

## Timeline

**Session 47 Goals** (2025-10-28):
- ✅ Update documentation (this file, CLAUDE.md, OS_INTEGRATION_PLAN.md)
- 📋 Create enhanced multitasking demo
- 📋 Create queue communication demo
- 📋 Test and validate demos
- 📋 Optional: Debug printf() issue

**Next Steps** (Future Sessions):
- Session 48: Complete remaining demos (sync, timers, stress)
- Session 49: Optional printf() debugging or UART interrupts
- Session 50+: Begin Phase 3 (RV64 upgrade)

---

## Files Modified/Created

### Documentation
- ✅ `CLAUDE.md` - Updated current status to Session 47, Phase 2 optimization
- ✅ `docs/OS_INTEGRATION_PLAN.md` - Added Phase 2 enhanced testing section
- ✅ `docs/SESSION_47_FREERTOS_ENHANCED_TESTING.md` - This file

### Code (To Be Created)
- 📋 `software/freertos/demos/enhanced/main_enhanced.c`
- 📋 `software/freertos/demos/queue/main_queue.c`
- 📋 `software/freertos/demos/sync/main_sync.c`
- 📋 `software/freertos/demos/timers/main_timers.c`
- 📋 `software/freertos/demos/stress/main_stress.c`
- 📋 `software/freertos/Makefile` - Updates for multi-demo build

---

## References

- **FreeRTOS API**: https://www.freertos.org/a00106.html
- **Session 46**: MULHU bug fix, FreeRTOS boot success
- **Session 43**: Printf duplication issue identified
- **OS Integration Plan**: `docs/OS_INTEGRATION_PLAN.md`
- **Memory Map**: `docs/MEMORY_MAP.md`

---

## Session 47 Progress Update

### What Was Accomplished ✅

1. **Documentation Complete**
   - ✅ Updated `CLAUDE.md` with Phase 2 optimization plan
   - ✅ Updated `docs/OS_INTEGRATION_PLAN.md` with enhanced testing section
   - ✅ Created `docs/SESSION_47_FREERTOS_ENHANCED_TESTING.md` (this file)
   - ✅ Updated `docs/KNOWN_ISSUES.md` with printf() status

2. **Demo Implementation Complete**
   - ✅ Created `software/freertos/demos/enhanced/main_enhanced.c` (priority-based multitasking, 278 lines)
   - ✅ Created `software/freertos/demos/queue/main_queue.c` (producer-consumer, 310 lines)
   - ✅ Created `software/freertos/demos/sync/main_sync.c` (semaphores/mutexes, 410 lines)
   - ✅ Updated `software/freertos/Makefile` for multi-demo support

3. **Build System Complete**
   - ✅ Makefile now supports `make DEMO=blinky|enhanced|queue|sync`
   - ✅ All demos compile successfully
   - ✅ Enhanced demo: 10KB code, 796KB data (fits in memory)

### Issue Discovered 🐛

**FreeRTOS Scheduler Not Running Tasks**

**Symptom**:
- FreeRTOS boots successfully ✅
- Tasks are created successfully ✅
- Scheduler starts ✅
- **BUT: Tasks never execute** ❌

**Observed Behavior**:
```
FreeRTOS Enhanced Multitasking Demo
...
All tasks created successfully!
Starting FreeRTOS scheduler...
<nothing happens - simulation runs but no task output>
```

**Root Cause Hypotheses**:
1. **Timer interrupts not firing**: CLINT might not be generating MTIMECMP interrupts
2. **Interrupts not enabled**: `mstatus.MIE` or `mie.MTIE` might not be set by FreeRTOS port
3. **Tick configuration wrong**: MTIMECMP value might be incorrect (config says 1ms tick @ 50MHz = 50,000 cycles)
4. **Port implementation issue**: `vPortSetupTimerInterrupt()` or `xPortStartScheduler()` might have bugs

**Evidence**:
- Simulation runs for 500,000+ cycles (10ms) but no task output
- Same issue affects both original blinky demo and new enhanced demo
- Boot messages appear correctly (UART works)
- Scheduler initialization completes (no errors)

**Next Steps for Session 48**:
1. Debug blinky demo first (simpler, easier to trace)
2. Add debug tracing to:
   - CLINT interrupt generation
   - Interrupt enable bits (mstatus.MIE, mie.MTIE)
   - MTIMECMP writes from FreeRTOS
   - Trap handler entry (is timer interrupt being taken?)
3. Check FreeRTOS port code:
   - `port/port.c:vPortSetupTimerInterrupt()`
   - `port/portASM.S:freertos_trap_handler`
   - Verify MTIMECMP is being written correctly
4. Verify CLINT is wired correctly in SoC

### Files Created/Modified

**New Files**:
- `software/freertos/demos/enhanced/main_enhanced.c` (278 lines)
- `software/freertos/demos/queue/main_queue.c` (310 lines)
- `software/freertos/demos/sync/main_sync.c` (410 lines)

**Modified Files**:
- `software/freertos/Makefile` - Multi-demo support
- `CLAUDE.md` - Session 47 status
- `docs/OS_INTEGRATION_PLAN.md` - Enhanced testing section
- `docs/KNOWN_ISSUES.md` - Updated printf() status
- `docs/SESSION_47_FREERTOS_ENHANCED_TESTING.md` - This file

**Build Outputs**:
- `software/freertos/build/freertos-blinky.hex` (8.8KB)
- `software/freertos/build/freertos-enhanced.hex` (10KB)

---

## Conclusion

Session 47 successfully created comprehensive FreeRTOS test infrastructure with three new demos testing multitasking, queues, and synchronization primitives. However, testing revealed that **FreeRTOS scheduler does not actually run tasks** after starting.

This is a critical issue that blocks Phase 2 validation. Session 48 will focus on debugging the scheduler/timer interrupt issue, starting with the simpler blinky demo.

**Status**: 🔄 Implementation complete, debugging needed for Session 48

**Key Achievement**: Created robust test framework for when scheduler is working!

**Blocker**: Timer interrupts or scheduler initialization issue preventing task execution
