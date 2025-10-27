/*
 * FreeRTOS Kernel V10.5.1
 * Copyright (C) 2021 Amazon.com, Inc. or its affiliates.  All Rights Reserved.
 *
 * SPDX-License-Identifier: MIT
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR IN CONNECTION WITH THE SOFTWARE.
 *
 * https://www.FreeRTOS.org
 * https://github.com/FreeRTOS
 */

#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/*-----------------------------------------------------------
 * Application specific definitions.
 *
 * These definitions should be adjusted for your particular hardware and
 * application requirements.
 *
 * THESE PARAMETERS ARE DESCRIBED WITHIN THE 'CONFIGURATION' SECTION OF THE
 * FreeRTOS API DOCUMENTATION AVAILABLE ON THE FreeRTOS.org WEB SITE.
 *
 * See http://www.freertos.org/a00110.html
 *----------------------------------------------------------*/

/* ========================================================================
 * RV1 Hardware Configuration
 * ======================================================================== */

/* CPU Clock: 50 MHz (default simulation clock) */
#define configCPU_CLOCK_HZ              50000000UL

/* Tick rate: 1000 Hz (1ms tick period) */
#define configTICK_RATE_HZ              1000

/* CLINT Memory-Mapped Registers (see MEMORY_MAP.md) */
#define configMTIME_BASE_ADDRESS        ( 0x0200BFF8UL )  /* MTIME counter */
#define configMTIMECMP_BASE_ADDRESS     ( 0x02004000UL )  /* MTIMECMP for hart 0 */

/* ISR Stack Size: 2KB (512 words) - used for interrupt context */
#define configISR_STACK_SIZE_WORDS      ( 512 )

/* ========================================================================
 * FreeRTOS Core Configuration
 * ======================================================================== */

/* Preemption and Scheduling */
#define configUSE_PREEMPTION            1
#define configUSE_TIME_SLICING          1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 0

/* Tick and Idle Task */
#define configUSE_TICKLESS_IDLE         0
#define configIDLE_SHOULD_YIELD         1

/* Task Configuration */
#define configMAX_PRIORITIES            ( 5 )
#define configMINIMAL_STACK_SIZE        ( ( unsigned short ) 128 )  /* 128 words = 512 bytes */
#define configMAX_TASK_NAME_LEN         ( 16 )
#define configUSE_16_BIT_TICKS          0  /* Use 32-bit tick count for RV32 */

/* Memory Allocation */
#define configSUPPORT_STATIC_ALLOCATION 1
#define configSUPPORT_DYNAMIC_ALLOCATION 1

/* Total heap size: 256KB (leaves room for data/BSS/stack in 1MB DMEM) */
#define configTOTAL_HEAP_SIZE           ( ( size_t ) ( 256 * 1024 ) )

/* ========================================================================
 * RISC-V Specific Configuration
 * ======================================================================== */

/* Hart ID for single-core system */
#define configHART_ID                   0

/* Machine Mode Operation (no S-mode for now) */
#define configMTIME_BASE_ADDRESS        ( 0x0200BFF8UL )
#define configMTIMECMP_BASE_ADDRESS     ( 0x02004000UL )

/* No task return (tasks should never return) */
#define configTASK_RETURN_ADDRESS       0

/* ========================================================================
 * Hook and Callback Functions
 * ======================================================================== */

#define configUSE_IDLE_HOOK             0
#define configUSE_TICK_HOOK             0
#define configUSE_MALLOC_FAILED_HOOK    1
#define configUSE_DAEMON_TASK_STARTUP_HOOK 0
#define configCHECK_FOR_STACK_OVERFLOW  2  /* Method 2: check canary pattern */

/* ========================================================================
 * Run-Time Statistics and Trace
 * ======================================================================== */

#define configGENERATE_RUN_TIME_STATS   0
#define configUSE_TRACE_FACILITY        1
#define configUSE_STATS_FORMATTING_FUNCTIONS 1

/* ========================================================================
 * Co-routine Configuration (Legacy - Disabled)
 * ======================================================================== */

#define configUSE_CO_ROUTINES           0
#define configMAX_CO_ROUTINE_PRIORITIES ( 2 )

/* ========================================================================
 * Software Timer Configuration
 * ======================================================================== */

#define configUSE_TIMERS                1
#define configTIMER_TASK_PRIORITY       ( configMAX_PRIORITIES - 1 )
#define configTIMER_QUEUE_LENGTH        10
#define configTIMER_TASK_STACK_DEPTH    ( configMINIMAL_STACK_SIZE * 2 )

/* ========================================================================
 * FreeRTOS Optional Features
 * ======================================================================== */

/* Task Notification */
#define configUSE_TASK_NOTIFICATIONS    1
#define configTASK_NOTIFICATION_ARRAY_ENTRIES 3

/* Queue and Semaphore */
#define configUSE_MUTEXES               1
#define configUSE_RECURSIVE_MUTEXES     1
#define configUSE_COUNTING_SEMAPHORES   1
#define configUSE_QUEUE_SETS            1

/* Event Groups and Stream Buffers */
#define configUSE_EVENT_GROUPS          1
#define configUSE_STREAM_BUFFERS        1
#define configUSE_MESSAGE_BUFFERS       1

/* ========================================================================
 * Memory Allocation Scheme
 * ======================================================================== */

/* Use heap_4.c:
 * - Supports malloc/free
 * - Combines adjacent free blocks
 * - Good for general-purpose applications
 */

/* ========================================================================
 * API Function Configuration (Inclusion Control)
 * ======================================================================== */

#define INCLUDE_vTaskPrioritySet        1
#define INCLUDE_uxTaskPriorityGet       1
#define INCLUDE_vTaskDelete             1
#define INCLUDE_vTaskSuspend            1
#define INCLUDE_xResumeFromISR          1
#define INCLUDE_vTaskDelayUntil         1
#define INCLUDE_vTaskDelay              1
#define INCLUDE_xTaskGetSchedulerState  1
#define INCLUDE_xTaskGetCurrentTaskHandle 1
#define INCLUDE_uxTaskGetStackHighWaterMark 1
#define INCLUDE_xTaskGetIdleTaskHandle  1
#define INCLUDE_eTaskGetState           1
#define INCLUDE_xEventGroupSetBitFromISR 1
#define INCLUDE_xTimerPendFunctionCall  1
#define INCLUDE_xTaskAbortDelay         1
#define INCLUDE_xTaskGetHandle          1
#define INCLUDE_xTaskResumeFromISR      1

/* ========================================================================
 * Assertion and Debugging
 * ======================================================================== */

/* Uncomment for debugging (outputs to UART) */
/* #define configASSERT( x ) if( ( x ) == 0 ) { taskDISABLE_INTERRUPTS(); for( ;; ); } */

/* For production, assertions can be disabled or routed to error handler */
#define configASSERT( x ) if( ( x ) == 0 ) vApplicationAssertionFailed()

extern void vApplicationAssertionFailed( void );

/* ========================================================================
 * Interrupt Priority Configuration
 * ======================================================================== */

/* RISC-V doesn't have priority levels in the same way as Cortex-M.
 * These are placeholders for API compatibility */
#define configKERNEL_INTERRUPT_PRIORITY         0
#define configMAX_SYSCALL_INTERRUPT_PRIORITY    0

/* ========================================================================
 * Port-Specific Macros
 * ======================================================================== */

/* Override default port definitions if needed */
/* (These are typically defined in portmacro.h) */

/* ========================================================================
 * UART Configuration for printf/console (Optional)
 * ======================================================================== */

/* UART base address for console output */
#define configUART_BASE_ADDRESS         ( 0x10000000UL )

/* ========================================================================
 * Validation Checks
 * ======================================================================== */

/* Ensure MTIME and MTIMECMP are defined */
#if !defined(configMTIME_BASE_ADDRESS) || !defined(configMTIMECMP_BASE_ADDRESS)
    #error "CLINT timer addresses must be defined for RISC-V port"
#endif

/* Ensure clock and tick rate are reasonable */
#if configCPU_CLOCK_HZ == 0
    #error "configCPU_CLOCK_HZ must be greater than 0"
#endif

#if configTICK_RATE_HZ == 0
    #error "configTICK_RATE_HZ must be greater than 0"
#endif

/* ========================================================================
 * Notes
 * ======================================================================== */

/*
 * RV1 Core Features:
 * - Architecture: RV32IMAFDC (32-bit with all standard extensions)
 * - Privilege Modes: M/S/U (Machine, Supervisor, User)
 * - FPU: Hardware single/double precision (shared 64-bit registers)
 * - Atomics: LR/SC and AMO instructions
 * - MMU: Sv32 with 16-entry TLB
 * - Memory: 64KB IMEM, 1MB DMEM (expanded for FreeRTOS)
 * - Peripherals: CLINT (timer + software IRQ), UART, PLIC (future)
 *
 * Current Configuration:
 * - Running in M-mode (Machine mode)
 * - Using CLINT for tick timer (MTI - Machine Timer Interrupt)
 * - No S-mode/U-mode initially (will add later for isolation)
 * - No MMU usage initially (bare metal)
 * - Using heap_4 memory allocator
 *
 * Memory Layout:
 * - IMEM: 0x00000000 - 0x0000FFFF (64KB, code)
 * - DMEM: 0x80000000 - 0x800FFFFF (1MB, data + heap + stacks)
 * - CLINT: 0x02000000 - 0x0200FFFF (64KB, memory-mapped)
 * - UART: 0x10000000 - 0x10000FFF (4KB, memory-mapped)
 *
 * See docs/MEMORY_MAP.md for full memory map details.
 */

#endif /* FREERTOS_CONFIG_H */
