# Phase 2: FreeRTOS Port - Detailed Execution Plan

**Project**: RV1 RISC-V Processor - FreeRTOS Integration
**Created**: 2025-10-27
**Target**: FreeRTOS v10.5.x LTS on RV32IMAFDC with 1MB unified memory
**Timeline**: ~2 weeks (11 days of work)

---

## Executive Summary

This plan covers the complete FreeRTOS port from memory expansion through demo applications and validation testing. Each step is designed to be independently verifiable with clear success criteria.

**Key Decisions (User-Selected)**:
- ✅ Location: `software/freertos/` (new top-level directory)
- ✅ Version: FreeRTOS v10.5.x LTS
- ✅ Memory: 1MB unified (jump to Phase 3 memory config early)
- ✅ Demos: Blinky, Queue test, Semaphore test, UART echo (all 4)

---

## Phase 1: Infrastructure Setup (Days 1-2)

### Step 1.1: Memory System Expansion
**Goal**: Expand DMEM from 64KB to 1MB, prepare for unified memory architecture

**Files to Modify**:
1. `rtl/config/rv_config.vh`
   - Change `DMEM_SIZE` from `65536` to `1048576` (1MB)
   - Update comments to reflect Phase 2/3 unified memory

2. `rtl/memory/data_memory.v`
   - Verify parameterization works with 1MB (should be automatic)
   - No code changes needed (already parameterized)

3. Update testbenches:
   - `tb/core/tb_core_pipelined.v` - larger memory instantiation
   - `tb/integration/tb_soc.v` - larger memory instantiation

**Validation**:
```bash
make test-quick          # Must pass 14/14 tests
env XLEN=32 ./tools/run_official_tests.sh all  # Must pass 81/81 tests
```

**Success Criteria**:
- ✅ Compile succeeds with no warnings
- ✅ All existing tests pass (zero regressions)
- ✅ Memory size reports 1MB in simulation logs

**Estimated Time**: 2-3 hours

---

### Step 1.2: Directory Structure Creation
**Goal**: Create complete software directory hierarchy

**Directory Structure**:
```
software/
├── freertos/
│   ├── FreeRTOS-Kernel/           (git submodule - Step 1.3)
│   ├── port/                       (RISC-V port customization)
│   │   ├── port.c
│   │   ├── portmacro.h
│   │   └── portASM.S
│   ├── config/
│   │   ├── FreeRTOSConfig.h
│   │   └── linker.ld
│   ├── lib/
│   │   ├── uart.c
│   │   ├── uart.h
│   │   └── startup.S
│   ├── demos/
│   │   ├── blinky.c
│   │   ├── queue_test.c
│   │   ├── semaphore_test.c
│   │   └── uart_echo.c
│   ├── Makefile
│   └── README.md
```

**Commands**:
```bash
cd /home/lei/rv1
mkdir -p software/freertos/{port,config,lib,demos}
touch software/freertos/{Makefile,README.md}
```

**Validation**:
- ✅ Directory structure created
- ✅ All parent directories exist

**Estimated Time**: 5 minutes

---

### Step 1.3: Clone FreeRTOS Kernel
**Goal**: Add FreeRTOS v10.5.x LTS as git submodule

**Commands**:
```bash
cd /home/lei/rv1/software/freertos
git submodule add -b V10.5.1 https://github.com/FreeRTOS/FreeRTOS-Kernel.git
git submodule update --init --recursive
```

**Validation**:
```bash
ls FreeRTOS-Kernel/
# Should see: tasks.c, queue.c, list.c, timers.c, portable/, include/
```

**Success Criteria**:
- ✅ FreeRTOS-Kernel directory exists
- ✅ Contains expected source files
- ✅ Git submodule configured correctly

**Estimated Time**: 10 minutes

---

## Phase 2: Port Layer Implementation (Days 3-4)

### Step 2.1: FreeRTOS Configuration Header
**Goal**: Create `config/FreeRTOSConfig.h` with RV1-specific settings

**File**: `software/freertos/config/FreeRTOSConfig.h`

**Key Configuration Values**:
```c
#define configCPU_CLOCK_HZ              50000000    // 50MHz
#define configTICK_RATE_HZ              1000        // 1ms tick
#define configMAX_PRIORITIES            5
#define configMINIMAL_STACK_SIZE        256         // words
#define configTOTAL_HEAP_SIZE           65536       // 64KB
#define configUSE_PREEMPTION            1
#define configUSE_TIME_SLICING          1
#define configUSE_IDLE_HOOK             0
#define configUSE_TICK_HOOK             0
#define configCHECK_FOR_STACK_OVERFLOW  2           // Method 2
#define configUSE_MALLOC_FAILED_HOOK    1
#define configUSE_MUTEXES               1
#define configUSE_COUNTING_SEMAPHORES   1
#define configUSE_RECURSIVE_MUTEXES     1
#define configQUEUE_REGISTRY_SIZE       10
```

**Memory Management**:
- Use `heap_4.c` (best fit with coalescence)
- Heap region: 64KB from 1MB RAM
- Stack: Each task gets dedicated stack (256 words = 1KB default)

**Validation**:
- ✅ File compiles without errors
- ✅ All required macros defined

**Estimated Time**: 1 hour

---

### Step 2.2: Port Macro Header
**Goal**: Create `port/portmacro.h` with architecture-specific definitions

**File**: `software/freertos/port/portmacro.h`

**Key Definitions**:
```c
#define portSTACK_TYPE              uint32_t
#define portBASE_TYPE               int32_t
#define portMAX_DELAY               0xFFFFFFFFUL
#define portTICK_TYPE_IS_ATOMIC     1

// Critical section (disable/enable interrupts)
#define portDISABLE_INTERRUPTS()    __asm volatile("csrci mstatus, 0x8")
#define portENABLE_INTERRUPTS()     __asm volatile("csrsi mstatus, 0x8")

// Context switch
#define portYIELD()                 __asm volatile("ecall")

// Stack growth direction
#define portSTACK_GROWTH            (-1)  // Stack grows downward
```

**Validation**:
- ✅ Compiles without errors
- ✅ Macros defined correctly

**Estimated Time**: 1 hour

---

### Step 2.3: Port Implementation (port.c)
**Goal**: Core FreeRTOS port functions for context switching and tick

**File**: `software/freertos/port/port.c`

**Functions to Implement**:
1. `pxPortInitialiseStack()` - Setup initial task stack frame
2. `xPortStartScheduler()` - Start the scheduler, jump to first task
3. `vPortEndScheduler()` - Not used (embedded system doesn't exit)
4. `xPortSysTickHandler()` - Timer interrupt handler (calls scheduler)

**Stack Frame Layout** (pushed by `pxPortInitialiseStack`):
```
High Address
+------------------+
| mepc (PC)        |  <- Task entry point
| ra               |  <- Return address (for task exit)
| sp (x2)          |
| gp (x3)          |
| tp (x4)          |
| t0-t2 (x5-x7)    |
| s0/fp (x8)       |
| s1 (x9)          |
| a0-a7 (x10-x17)  |  <- a0 = task parameter
| s2-s11 (x18-x27) |
| t3-t6 (x28-x31)  |
+------------------+
Low Address (SP points here)
```

**Critical Implementation Details**:
- Save/restore ALL 32 integer registers
- Save/restore FP registers if task uses FP (check FS field)
- Set `mstatus.MPIE = 1` (enable interrupts on MRET)
- Set `mstatus.MPP = 3` (return to M-mode)

**Validation**:
- ✅ Compiles without errors
- ✅ Linker resolves all symbols

**Estimated Time**: 4-6 hours

---

### Step 2.4: Assembly Trap Handler (portASM.S)
**Goal**: Low-level context switch and trap handling in assembly

**File**: `software/freertos/port/portASM.S`

**Functions**:
1. `freertos_trap_handler` - Main trap entry point
2. `freertos_context_save` - Save all registers to task stack
3. `freertos_context_restore` - Restore all registers from task stack

**Trap Handler Flow**:
```asm
freertos_trap_handler:
    # 1. Save context (all 32 registers + mepc + mstatus)
    addi sp, sp, -128           # Allocate stack frame (32 regs × 4 bytes)
    sw   ra, 0(sp)
    sw   t0, 4(sp)
    # ... (save all registers) ...
    csrr t0, mepc
    sw   t0, 124(sp)            # Save mepc

    # 2. Check trap cause (timer or ecall)
    csrr t0, mcause
    bge  t0, zero, .handle_exception  # Synchronous exception (ecall)

.handle_interrupt:
    # Timer interrupt - call xPortSysTickHandler()
    call xPortSysTickHandler
    j    .restore_context

.handle_exception:
    # ECALL - yield to scheduler
    call vTaskSwitchContext      # FreeRTOS scheduler
    # Fall through to restore

.restore_context:
    # 3. Restore context from (potentially different) task stack
    lw   t0, 124(sp)
    csrw mepc, t0
    lw   ra, 0(sp)
    # ... (restore all registers) ...
    addi sp, sp, 128
    mret                         # Return to task
```

**Validation**:
- ✅ Assembles without errors
- ✅ Correct register save/restore order
- ✅ Stack frame size correct (128 bytes)

**Estimated Time**: 4-6 hours

---

## Phase 3: Hardware Support Libraries (Day 5)

### Step 3.1: UART Driver Implementation
**Goal**: Create polled UART driver for console I/O

**Files**: `software/freertos/lib/uart.c`, `software/freertos/lib/uart.h`

**UART Register Definitions** (from memory map):
```c
#define UART_BASE     0x10000000
#define UART_THR      (*(volatile uint8_t*)(UART_BASE + 0))  // Transmit
#define UART_RBR      (*(volatile uint8_t*)(UART_BASE + 0))  // Receive
#define UART_IER      (*(volatile uint8_t*)(UART_BASE + 1))  // Interrupt Enable
#define UART_LSR      (*(volatile uint8_t*)(UART_BASE + 5))  // Line Status
#define UART_LCR      (*(volatile uint8_t*)(UART_BASE + 3))  // Line Control
#define UART_FCR      (*(volatile uint8_t*)(UART_BASE + 2))  // FIFO Control

#define LSR_DR        0x01  // Data Ready
#define LSR_THRE      0x20  // Transmit Holding Register Empty
```

**Functions to Implement**:
```c
void uart_init(void);              // Initialize UART (8N1, disable IRQ)
void uart_putc(char c);            // Transmit one character (polled)
char uart_getc(void);              // Receive one character (polled, blocking)
int  uart_getc_nonblock(void);     // Receive (non-blocking, -1 if no data)
void uart_puts(const char* s);     // Transmit string
void uart_printf(const char* fmt, ...);  // Formatted output (minimal)
```

**uart_init() Implementation**:
```c
void uart_init(void) {
    UART_IER = 0x00;       // Disable all interrupts
    UART_LCR = 0x03;       // 8N1 (8 bits, no parity, 1 stop bit)
    UART_FCR = 0x07;       // Enable FIFO, clear RX/TX FIFOs
}
```

**uart_printf() Implementation**:
- Support %d, %x, %s, %c only (minimal printf)
- No floating-point support needed
- Use fixed-size buffer (256 bytes)

**Validation**:
- ✅ Compiles without errors
- ✅ Test in simple standalone program (print "Hello, World!")

**Estimated Time**: 2-3 hours

---

### Step 3.2: CLINT Timer Integration
**Goal**: Configure CLINT for 1ms FreeRTOS tick

**CLINT Register Definitions**:
```c
#define CLINT_BASE       0x02000000
#define CLINT_MSIP       (*(volatile uint32_t*)(CLINT_BASE + 0x0000))
#define CLINT_MTIMECMP   (*(volatile uint64_t*)(CLINT_BASE + 0x4000))
#define CLINT_MTIME      (*(volatile uint64_t*)(CLINT_BASE + 0xBFF8))
```

**Functions to Implement** (in `port/port.c`):
```c
void vPortSetupTimerInterrupt(void) {
    // Called by xPortStartScheduler()
    uint64_t current_time = CLINT_MTIME;
    uint64_t next_tick = current_time + (configCPU_CLOCK_HZ / configTICK_RATE_HZ);
    CLINT_MTIMECMP = next_tick;

    // Enable timer interrupt (mie.MTIE = 1)
    uint32_t mie;
    __asm volatile("csrr %0, mie" : "=r"(mie));
    mie |= 0x80;  // Bit 7 = MTIE
    __asm volatile("csrw mie, %0" :: "r"(mie));

    // Enable global interrupts (mstatus.MIE = 1)
    uint32_t mstatus;
    __asm volatile("csrr %0, mstatus" : "=r"(mstatus));
    mstatus |= 0x8;  // Bit 3 = MIE
    __asm volatile("csrw mstatus, %0" :: "r"(mstatus));
}

void xPortSysTickHandler(void) {
    // Called from trap handler on timer interrupt

    // Clear interrupt by setting next compare value
    uint64_t current_time = CLINT_MTIME;
    uint64_t next_tick = current_time + (configCPU_CLOCK_HZ / configTICK_RATE_HZ);
    CLINT_MTIMECMP = next_tick;

    // Increment FreeRTOS tick count (may trigger context switch)
    if (xTaskIncrementTick() != pdFALSE) {
        // Context switch needed
        vTaskSwitchContext();
    }
}
```

**Tick Calculation**:
- CPU clock: 50 MHz = 50,000,000 Hz
- Tick rate: 1000 Hz (1ms period)
- Cycles per tick: 50,000,000 / 1000 = 50,000 cycles

**Validation**:
- ✅ Compiles without errors
- ✅ Timer interrupt fires every 1ms (verify in testbench)

**Estimated Time**: 2 hours

---

### Step 3.3: Startup Code
**Goal**: Create `lib/startup.S` for boot and initialization

**File**: `software/freertos/lib/startup.S`

**Startup Sequence**:
```asm
.section .text.init
.global _start
_start:
    # 1. Initialize stack pointer
    la   sp, __stack_top

    # 2. Zero .bss section
    la   t0, __bss_start
    la   t1, __bss_end
.zero_bss:
    beq  t0, t1, .bss_done
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    .zero_bss
.bss_done:

    # 3. Setup trap vector
    la   t0, freertos_trap_handler
    csrw mtvec, t0

    # 4. Initialize hardware
    call uart_init

    # 5. Jump to main
    call main

    # 6. If main returns, loop forever
.hang:
    j    .hang
```

**Validation**:
- ✅ Assembles without errors
- ✅ Symbols `__bss_start`, `__bss_end`, `__stack_top` defined in linker script

**Estimated Time**: 1 hour

---

### Step 3.4: Linker Script
**Goal**: Create `config/linker.ld` for 1MB unified memory layout

**File**: `software/freertos/config/linker.ld`

**Memory Map**:
```ld
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 1M
}

SECTIONS {
    .text : {
        *(.text.init)           /* Startup code first */
        *(.text)
        *(.text.*)
        . = ALIGN(4);
    } > RAM

    .rodata : {
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(4);
    } > RAM

    .data : {
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4);
    } > RAM

    .bss : {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    /* Heap (64KB for FreeRTOS) */
    . = ALIGN(8);
    __heap_start = .;
    . += 65536;
    __heap_end = .;

    /* Stack (grows down from end of RAM) */
    . = ORIGIN(RAM) + LENGTH(RAM);
    __stack_top = .;
}

PROVIDE(__stack_pointer = __stack_top);
```

**Memory Layout** (1MB total):
```
0x8000_0000  .text (code)                    ~20KB
0x8000_5000  .rodata (constants)             ~5KB
0x8000_6400  .data (initialized globals)     ~2KB
0x8000_6C00  .bss (zero-initialized)         ~3KB
0x8000_7800  Heap (FreeRTOS heap_4)          64KB
0x8001_7800  Free space                      ~895KB
0x800F_0000  Task stacks (grows down)        ~64KB
0x8010_0000  End of RAM
```

**Validation**:
- ✅ Linker accepts script without errors
- ✅ All sections fit within 1MB
- ✅ Symbols defined correctly

**Estimated Time**: 1 hour

---

## Phase 4: Build System (Day 6)

### Step 4.1: Create Makefile
**Goal**: Complete build system for all demos

**File**: `software/freertos/Makefile`

**Toolchain Setup**:
```makefile
CROSS_COMPILE = riscv64-unknown-elf-
CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump
SIZE = $(CROSS_COMPILE)size

# Compiler flags
ARCH_FLAGS = -march=rv32imafdc -mabi=ilp32d
CFLAGS = $(ARCH_FLAGS) -O2 -g -Wall -Wextra
CFLAGS += -ffreestanding -nostdlib
CFLAGS += -I. -Iconfig -Ilib -Iport
CFLAGS += -IFreeRTOS-Kernel/include
CFLAGS += -IFreeRTOS-Kernel/portable/GCC/RISC-V

# Linker flags
LDFLAGS = $(ARCH_FLAGS) -T config/linker.ld
LDFLAGS += -nostartfiles -Wl,-Map=$@.map
```

**Source Files**:
```makefile
# FreeRTOS kernel sources
FREERTOS_SRCS = \
    FreeRTOS-Kernel/tasks.c \
    FreeRTOS-Kernel/queue.c \
    FreeRTOS-Kernel/list.c \
    FreeRTOS-Kernel/timers.c \
    FreeRTOS-Kernel/portable/MemMang/heap_4.c \
    FreeRTOS-Kernel/portable/GCC/RISC-V/port.c

# Port layer
PORT_SRCS = \
    port/port.c \
    port/portASM.S

# Library sources
LIB_SRCS = \
    lib/startup.S \
    lib/uart.c

# Common sources (all demos use these)
COMMON_SRCS = $(FREERTOS_SRCS) $(PORT_SRCS) $(LIB_SRCS)
```

**Build Targets**:
```makefile
.PHONY: all clean blinky queue semaphore uart-echo

all: blinky queue semaphore uart-echo

blinky: demos/blinky.elf demos/blinky.hex
queue: demos/queue_test.elf demos/queue_test.hex
semaphore: demos/semaphore_test.elf demos/semaphore_test.hex
uart-echo: demos/uart_echo.elf demos/uart_echo.hex

demos/%.elf: demos/%.c $(COMMON_SRCS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	$(SIZE) $@
	$(OBJDUMP) -d $@ > $@.dis

demos/%.hex: demos/%.elf
	$(OBJCOPY) -O verilog $< $@

clean:
	rm -f demos/*.elf demos/*.hex demos/*.map demos/*.dis
```

**Helper Targets**:
```makefile
# Load hex file into simulation
load-%: demos/%.hex
	cp $< ../../sim/freertos_$(notdir $<)
	@echo "Loaded $< to sim/"

# Run simulation (requires testbench update)
sim-%: load-%
	cd ../../ && make sim-freertos-$(notdir $*)
```

**Validation**:
```bash
cd software/freertos
make clean
make blinky  # Should compile and link successfully
```

**Success Criteria**:
- ✅ All demos compile without errors
- ✅ Binary sizes reasonable (~50-100KB per demo)
- ✅ Linker map shows correct memory layout

**Estimated Time**: 2-3 hours

---

## Phase 5: Demo Applications (Days 7-8)

### Step 5.1: Blinky Demo
**Goal**: Simple 2-task demo with periodic UART output

**File**: `software/freertos/demos/blinky.c`

**Implementation**:
```c
#include "FreeRTOS.h"
#include "task.h"
#include "uart.h"

void vTask1(void *pvParameters) {
    (void)pvParameters;

    while (1) {
        uart_puts("Task 1\r\n");
        vTaskDelay(pdMS_TO_TICKS(500));  // 500ms delay
    }
}

void vTask2(void *pvParameters) {
    (void)pvParameters;

    while (1) {
        uart_puts("Task 2\r\n");
        vTaskDelay(pdMS_TO_TICKS(1000));  // 1000ms delay
    }
}

int main(void) {
    uart_puts("FreeRTOS v" tskKERNEL_VERSION_NUMBER "\r\n");
    uart_puts("Blinky Demo Starting...\r\n");

    // Create tasks
    xTaskCreate(vTask1, "Task1", configMINIMAL_STACK_SIZE, NULL, 1, NULL);
    xTaskCreate(vTask2, "Task2", configMINIMAL_STACK_SIZE, NULL, 1, NULL);

    // Start scheduler (never returns)
    vTaskStartScheduler();

    // Should never reach here
    while (1);
    return 0;
}
```

**Expected Output**:
```
FreeRTOS v10.5.1
Blinky Demo Starting...
Task 1
Task 2
Task 1
Task 1
Task 2
Task 1
...
```

**Validation**:
- ✅ Compiles without errors
- ✅ Tasks print in correct pattern (Task 1 prints 2× per Task 2 print)
- ✅ Timing accurate (Task 1 every 500ms, Task 2 every 1000ms)

**Estimated Time**: 1 hour

---

### Step 5.2: Queue Test Demo
**Goal**: Producer-consumer pattern with queue IPC

**File**: `software/freertos/demos/queue_test.c`

**Implementation**:
```c
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "uart.h"

static QueueHandle_t xQueue;

void vProducerTask(void *pvParameters) {
    (void)pvParameters;
    uint32_t counter = 0;

    while (1) {
        // Send counter to queue
        if (xQueueSend(xQueue, &counter, portMAX_DELAY) == pdPASS) {
            uart_printf("Sent: %d\r\n", counter);
            counter++;
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

void vConsumerTask(void *pvParameters) {
    (void)pvParameters;
    uint32_t received;

    while (1) {
        // Receive from queue (blocks if empty)
        if (xQueueReceive(xQueue, &received, portMAX_DELAY) == pdPASS) {
            uart_printf("Received: %d\r\n", received);
        }
    }
}

int main(void) {
    uart_puts("FreeRTOS Queue Test\r\n");

    // Create queue (10 items, each 4 bytes)
    xQueue = xQueueCreate(10, sizeof(uint32_t));
    if (xQueue == NULL) {
        uart_puts("ERROR: Failed to create queue\r\n");
        while (1);
    }

    // Create tasks
    xTaskCreate(vProducerTask, "Producer", configMINIMAL_STACK_SIZE, NULL, 2, NULL);
    xTaskCreate(vConsumerTask, "Consumer", configMINIMAL_STACK_SIZE, NULL, 1, NULL);

    // Start scheduler
    vTaskStartScheduler();

    while (1);
    return 0;
}
```

**Expected Output**:
```
FreeRTOS Queue Test
Sent: 0
Received: 0
Sent: 1
Received: 1
Sent: 2
Received: 2
...
```

**Test Cases**:
1. Sequential delivery (no lost messages)
2. Queue full blocking (producer waits when queue full)
3. Queue empty blocking (consumer waits when queue empty)

**Validation**:
- ✅ No data corruption (sequential numbers)
- ✅ Blocking works correctly
- ✅ Queue manages memory correctly

**Estimated Time**: 1-2 hours

---

### Step 5.3: Semaphore Test Demo
**Goal**: Binary and counting semaphore validation

**File**: `software/freertos/demos/semaphore_test.c`

**Implementation**:
```c
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "uart.h"

static SemaphoreHandle_t xBinarySemaphore;
static SemaphoreHandle_t xCountingSemaphore;

void vBinaryGiver(void *pvParameters) {
    (void)pvParameters;

    while (1) {
        uart_puts("Giver: Giving binary semaphore\r\n");
        xSemaphoreGive(xBinarySemaphore);
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

void vBinaryTaker(void *pvParameters) {
    (void)pvParameters;

    while (1) {
        if (xSemaphoreTake(xBinarySemaphore, portMAX_DELAY) == pdPASS) {
            uart_puts("Taker: Took binary semaphore\r\n");
        }
    }
}

void vCountingTest(void *pvParameters) {
    (void)pvParameters;
    int i;

    uart_puts("Counting: Giving 3 times\r\n");
    for (i = 0; i < 3; i++) {
        xSemaphoreGive(xCountingSemaphore);
    }

    uart_puts("Counting: Taking 3 times\r\n");
    for (i = 0; i < 3; i++) {
        if (xSemaphoreTake(xCountingSemaphore, 0) == pdPASS) {
            uart_printf("Counting: Take %d success\r\n", i);
        }
    }

    // 4th take should fail (timeout)
    uart_puts("Counting: Taking 4th (should fail)\r\n");
    if (xSemaphoreTake(xCountingSemaphore, pdMS_TO_TICKS(100)) == pdFAIL) {
        uart_puts("Counting: Take 4 failed (expected)\r\n");
    }

    // Test complete, suspend
    vTaskSuspend(NULL);
}

int main(void) {
    uart_puts("FreeRTOS Semaphore Test\r\n");

    // Create semaphores
    xBinarySemaphore = xSemaphoreCreateBinary();
    xCountingSemaphore = xSemaphoreCreateCounting(3, 0);  // Max 3, initial 0

    if (xBinarySemaphore == NULL || xCountingSemaphore == NULL) {
        uart_puts("ERROR: Failed to create semaphores\r\n");
        while (1);
    }

    // Create tasks
    xTaskCreate(vBinaryGiver, "BinGive", configMINIMAL_STACK_SIZE, NULL, 2, NULL);
    xTaskCreate(vBinaryTaker, "BinTake", configMINIMAL_STACK_SIZE, NULL, 1, NULL);
    xTaskCreate(vCountingTest, "Counting", configMINIMAL_STACK_SIZE, NULL, 3, NULL);

    // Start scheduler
    vTaskStartScheduler();

    while (1);
    return 0;
}
```

**Expected Output**:
```
FreeRTOS Semaphore Test
Counting: Giving 3 times
Counting: Taking 3 times
Counting: Take 0 success
Counting: Take 1 success
Counting: Take 2 success
Counting: Taking 4th (should fail)
Counting: Take 4 failed (expected)
Giver: Giving binary semaphore
Taker: Took binary semaphore
...
```

**Validation**:
- ✅ Binary semaphore handshake works
- ✅ Counting semaphore respects limits
- ✅ Timeout works correctly

**Estimated Time**: 1-2 hours

---

### Step 5.4: UART Echo Demo
**Goal**: Interrupt-driven UART RX with task notification

**File**: `software/freertos/demos/uart_echo.c`

**Implementation**:
```c
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "uart.h"

static SemaphoreHandle_t xRxSemaphore;

// UART RX interrupt handler (called from trap handler)
void uart_rx_isr(void) {
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;

    // Give semaphore to wake up echo task
    xSemaphoreGiveFromISR(xRxSemaphore, &xHigherPriorityTaskWoken);

    // Request context switch if needed
    portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
}

void vEchoTask(void *pvParameters) {
    (void)pvParameters;
    char c;

    uart_puts("UART Echo Demo - Type characters\r\n");

    while (1) {
        // Wait for RX interrupt
        if (xSemaphoreTake(xRxSemaphore, portMAX_DELAY) == pdPASS) {
            // Read character (should be ready)
            c = uart_getc_nonblock();
            if (c != -1) {
                // Echo back
                uart_putc(c);

                // Handle newline
                if (c == '\r') {
                    uart_putc('\n');
                }
            }
        }
    }
}

int main(void) {
    uart_puts("FreeRTOS UART Echo Test\r\n");

    // Create semaphore
    xRxSemaphore = xSemaphoreCreateBinary();
    if (xRxSemaphore == NULL) {
        uart_puts("ERROR: Failed to create semaphore\r\n");
        while (1);
    }

    // Enable UART RX interrupt
    uart_enable_rx_interrupt();

    // Create echo task
    xTaskCreate(vEchoTask, "Echo", configMINIMAL_STACK_SIZE * 2, NULL, 2, NULL);

    // Start scheduler
    vTaskStartScheduler();

    while (1);
    return 0;
}
```

**UART Driver Additions** (in `lib/uart.c`):
```c
void uart_enable_rx_interrupt(void) {
    UART_IER = 0x01;  // Enable RX data available interrupt
}

// Add to trap handler (portASM.S):
// Check if UART interrupt, call uart_rx_isr()
```

**Expected Behavior**:
- Type "Hello" → Echo "Hello"
- Characters echoed immediately (interrupt-driven)
- Task blocks when no input (power efficient)

**Validation**:
- ✅ Characters echoed correctly
- ✅ Interrupt fires on RX data
- ✅ Task wakes from semaphore

**Estimated Time**: 2-3 hours

---

## Phase 6: Integration & Testing (Days 9-10)

### Step 6.1: Testbench Updates
**Goal**: Modify SoC testbench to support FreeRTOS testing

**File**: `tb/integration/tb_soc.v`

**Changes Needed**:
1. Increase memory size to 1MB
2. Add hex file loading parameter
3. Add UART output monitoring
4. Add timeout for long-running tests (10,000 cycles default)
5. Add test completion detection (magic exit code or string match)

**Example Additions**:
```verilog
// Parameters
parameter MEM_FILE = "../../software/freertos/demos/blinky.hex";
parameter TIMEOUT_CYCLES = 500000;  // 10ms @ 50MHz

// UART monitor
always @(posedge clk) begin
    if (uart_tx_valid) begin
        $write("%c", uart_tx_data);
        $fflush();
    end
end

// Timeout
initial begin
    #(TIMEOUT_CYCLES * 20);  // 20ns clock period
    $display("\nTIMEOUT: Test did not complete");
    $finish;
end
```

**Validation**:
- ✅ Testbench compiles with updated memory
- ✅ Can load FreeRTOS hex files
- ✅ UART output appears in simulation log

**Estimated Time**: 2-3 hours

---

### Step 6.2: Individual Demo Tests
**Goal**: Test each demo in simulation, verify functionality

**Test Script**: `software/freertos/test_demo.sh`

```bash
#!/bin/bash
# Test a FreeRTOS demo

DEMO=$1
if [ -z "$DEMO" ]; then
    echo "Usage: $0 <blinky|queue|semaphore|uart-echo>"
    exit 1
fi

echo "Testing FreeRTOS demo: $DEMO"

# Build demo
make clean
make $DEMO || exit 1

# Copy hex to sim directory
cp demos/${DEMO}.hex ../../sim/freertos_test.hex

# Run simulation
cd ../../
iverilog -g2012 -DMEM_FILE="sim/freertos_test.hex" \
    -DCONFIG_RV32IMAFDC -DENABLE_M_EXT=1 -DENABLE_A_EXT=1 \
    -DENABLE_C_EXT=1 -I rtl/config -I rtl/core -I rtl/memory \
    -I rtl/peripherals -I rtl/interconnect \
    -o sim/test_freertos.vvp \
    rtl/rv_soc.v tb/integration/tb_soc.v

timeout 10s vvp sim/test_freertos.vvp > sim/test_freertos.log 2>&1

# Check results
echo "Simulation output:"
cat sim/test_freertos.log

# Verify expected output
case $DEMO in
    blinky)
        grep -q "Task 1" sim/test_freertos.log && \
        grep -q "Task 2" sim/test_freertos.log && \
        echo "✅ Blinky test PASSED" || echo "❌ Blinky test FAILED"
        ;;
    queue)
        grep -q "Sent: 0" sim/test_freertos.log && \
        grep -q "Received: 0" sim/test_freertos.log && \
        echo "✅ Queue test PASSED" || echo "❌ Queue test FAILED"
        ;;
    semaphore)
        grep -q "Counting: Take 0 success" sim/test_freertos.log && \
        grep -q "Take 4 failed (expected)" sim/test_freertos.log && \
        echo "✅ Semaphore test PASSED" || echo "❌ Semaphore test FAILED"
        ;;
    uart-echo)
        # Inject test input via testbench
        grep -q "UART Echo Demo" sim/test_freertos.log && \
        echo "✅ UART Echo test PASSED" || echo "❌ UART Echo test FAILED"
        ;;
esac
```

**Run Tests**:
```bash
cd software/freertos
./test_demo.sh blinky
./test_demo.sh queue
./test_demo.sh semaphore
./test_demo.sh uart-echo
```

**Success Criteria** (per demo):
- ✅ Compiles without errors
- ✅ Runs in simulation without crashes
- ✅ Produces expected output
- ✅ Completes within timeout

**Estimated Time**: 4-6 hours (includes debugging)

---

### Step 6.3: Regression Testing
**Goal**: Ensure FreeRTOS changes don't break existing tests

**Tests to Run**:
```bash
# Quick regression (14 tests)
make test-quick

# Official compliance (81 tests)
env XLEN=32 ./tools/run_official_tests.sh all

# Interrupt tests (6 tests)
./tools/run_test_by_name.sh test_interrupt_delegation_mti
./tools/run_test_by_name.sh test_interrupt_delegation_msi
./tools/run_test_by_name.sh test_interrupt_msi_priority
./tools/run_test_by_name.sh test_interrupt_mie_masking
./tools/run_test_by_name.sh test_interrupt_sie_masking
./tools/run_test_by_name.sh test_interrupt_nested_mmode
```

**Success Criteria**:
- ✅ All 14 quick tests pass
- ✅ All 81 official tests pass
- ✅ All 6 interrupt tests pass
- ✅ Zero regressions introduced

**Estimated Time**: 2 hours

---

### Step 6.4: Extended Stability Test
**Goal**: Run Blinky for extended period to catch corner cases

**Test Configuration**:
- Duration: 10,000 ticks = 10 seconds simulated time
- Monitoring: Stack canaries, heap integrity, task starvation
- Checks: No crashes, no corruption, all tasks get CPU time

**Modifications to Blinky**:
```c
// Add stack canaries
#define STACK_CANARY 0xDEADBEEF

void vTask1(void *pvParameters) {
    uint32_t canary = STACK_CANARY;
    uint32_t count = 0;

    while (1) {
        // Check canary
        if (canary != STACK_CANARY) {
            uart_puts("ERROR: Stack overflow in Task1\r\n");
            while (1);
        }

        uart_printf("Task 1 (count=%d)\r\n", count++);
        vTaskDelay(pdMS_TO_TICKS(500));

        // Exit after 20 iterations (10 seconds)
        if (count >= 20) {
            uart_puts("Task 1: Test complete\r\n");
            vTaskSuspend(NULL);
        }
    }
}
```

**Success Criteria**:
- ✅ Runs for 10,000 ticks without crash
- ✅ No stack overflow detected
- ✅ No heap corruption detected
- ✅ All tasks get scheduled (no starvation)
- ✅ Timing remains accurate throughout

**Estimated Time**: 2-3 hours

---

## Phase 7: Documentation (Day 11)

### Step 7.1: FreeRTOS README
**Goal**: Create comprehensive README for software directory

**File**: `software/freertos/README.md`

**Contents**:
1. Overview (what is FreeRTOS, why v10.5.x)
2. Quick start guide
3. Build instructions
4. Demo descriptions
5. Memory layout diagram
6. Configuration notes
7. Troubleshooting tips
8. Performance metrics

**Estimated Time**: 2 hours

---

### Step 7.2: Session Summary Documentation
**Goal**: Document implementation details and results

**File**: `docs/SESSION_PHASE2_FREERTOS.md`

**Contents**:
1. Implementation overview
2. Architecture decisions (why 1MB, why heap_4, etc.)
3. Challenges encountered & solutions
4. Performance metrics:
   - Context switch time (cycles)
   - Interrupt latency (cycles)
   - Binary sizes (bytes per demo)
   - RAM usage (heap + stacks)
5. Test results summary (all demos + regressions)
6. Lessons learned

**Estimated Time**: 2 hours

---

### Step 7.3: Update Main Documentation
**Goal**: Update CLAUDE.md with Phase 2 completion

**File**: `CLAUDE.md`

**Changes**:
1. Mark Phase 2 as **COMPLETE** ✅
2. Update "Current Status" section
3. Add FreeRTOS statistics
4. Update "Next Step" to Phase 3 (RV64 upgrade)

**Estimated Time**: 30 minutes

---

## Final Validation Checklist

Before marking Phase 2 complete, verify ALL criteria:

### Build System
- [ ] All 4 demos compile without errors
- [ ] Binary sizes reasonable (< 100KB per demo)
- [ ] Linker map shows correct layout
- [ ] Makefile targets work (all, clean, individual demos)

### Functionality
- [ ] Blinky: Tasks print in correct pattern
- [ ] Queue: Producer-consumer works, no data loss
- [ ] Semaphore: Binary & counting work correctly
- [ ] UART Echo: Interrupt-driven RX works

### Timing
- [ ] FreeRTOS tick = 1ms (verified via timestamps)
- [ ] Task delays accurate (±1ms)
- [ ] Context switch time < 100 cycles

### Stability
- [ ] Runs for 10,000 ticks without crash
- [ ] No stack overflow (canaries intact)
- [ ] No heap corruption (integrity checks pass)
- [ ] No task starvation (all tasks scheduled)

### Regression
- [ ] Quick tests: 14/14 passing ✅
- [ ] Official compliance: 81/81 passing ✅
- [ ] Interrupt tests: 6/6 passing ✅
- [ ] Zero regressions introduced

### Documentation
- [ ] FreeRTOS README complete
- [ ] Session summary written
- [ ] CLAUDE.md updated
- [ ] All code commented

---

## Success Metrics

**Phase 2 Complete When**:
- ✅ All 4 demos running successfully
- ✅ FreeRTOS v10.5.x fully ported to RV32IMAFDC
- ✅ Zero regressions in existing tests
- ✅ Extended stability test passes (10,000 ticks)
- ✅ Documentation complete
- ✅ Ready for Phase 3 (RV64 upgrade)

**Performance Targets**:
- Context switch: < 100 cycles (2μs @ 50MHz)
- Interrupt latency: < 50 cycles (1μs @ 50MHz)
- RAM usage: < 100KB (heap + stacks + kernel)
- Binary size: < 100KB per demo

---

## Risk Mitigation Summary

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Stack overflow crashes | Medium | High | Stack canaries, configCHECK_FOR_STACK_OVERFLOW=2 |
| Context switch bugs | High | Critical | Extensive register save/restore testing, single-step debug |
| Timing inaccuracies | Medium | Medium | Verify CLINT calculations, add debug timestamps |
| Memory layout issues | Low | High | Linker map analysis, explicit section placement |
| Interrupt priority conflicts | Low | Medium | Document priority levels, clear configuration |

---

## Next Steps After Phase 2

Once all validation passes:

1. **Git Commit**: Create comprehensive commit for Phase 2
   ```bash
   git add software/ rtl/config/ rtl/memory/ docs/
   git commit -m "Phase 2: FreeRTOS v10.5.x port complete

   - Expanded DMEM to 1MB
   - Ported FreeRTOS kernel with RISC-V port layer
   - Implemented 4 demo applications (Blinky, Queue, Semaphore, UART Echo)
   - All demos passing, zero regressions
   - Extended stability test (10,000 ticks) passing

   Phase 2 COMPLETE ✅ - Ready for Phase 3 (RV64 upgrade)"
   ```

2. **Phase 3 Planning**: Review OS Integration Plan for RV64 upgrade
   - Upgrade XLEN 32→64
   - Expand MMU Sv32→Sv39
   - Run RV64 compliance tests (87 tests)
   - Verify FreeRTOS still works on RV64

3. **Optional**: Explore FreeRTOS advanced features
   - Mutexes
   - Event groups
   - Stream buffers
   - Software timers

---

**END OF EXECUTION PLAN**

This plan provides a complete, step-by-step roadmap for Phase 2. Each step has clear goals, validation criteria, and time estimates. Follow this plan sequentially, completing each validation before moving to the next step.

**Ready to start with Step 1.1: Memory System Expansion!** 🚀
