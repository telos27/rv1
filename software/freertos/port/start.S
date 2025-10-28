/*
 * RISC-V Startup Code for FreeRTOS on RV1 Core
 *
 * This file provides:
 * - Reset handler (entry point)
 * - Stack initialization
 * - BSS zero-initialization
 * - Data section copy from ROM to RAM
 * - Jump to main()
 *
 * Created: 2025-10-27
 * Target: RV32IMAFDC
 */

#include "freertos_risc_v_chip_specific_extensions.h"

    .section .text.init
    .global _start
    .type _start, @function

_start:
    /* Disable interrupts during initialization */
    csrci mstatus, 0x8  /* Clear MIE bit */

    /* ====================================================================
     * Initialize Stack Pointer
     * ==================================================================== */

    /* Load stack top address (defined in linker script) */
    .option push
    .option norelax
    la sp, __stack_top
    .option pop

    /* Ensure stack is 16-byte aligned (RISC-V ABI requirement) */
    andi sp, sp, -16

    /* ====================================================================
     * Initialize Global Pointer (GP)
     * ==================================================================== */

    /* GP provides base for ±2KB small data access optimization */
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    /* ====================================================================
     * Initialize FPU (Enable FS field in MSTATUS)
     * ==================================================================== */

    /* RV32IMAFDC has hardware FPU - enable it */
    /* MSTATUS.FS = 01 (Initial) - enables FPU, marks registers clean */
    li t0, 0x00002000   /* FS = 01 (bits 13-14) */
    csrs mstatus, t0

    /* Initialize FCSR (FP Control/Status Register) to zero */
    /* - Rounding mode = RNE (Round to Nearest, ties to Even) */
    /* - Exception flags = 0 (no exceptions) */
    fscsr zero

    /* ====================================================================
     * Zero-Initialize BSS Section
     * ==================================================================== */

    /* BSS contains uninitialized global/static variables */
    /* C standard requires these to be zero-initialized */

    la t0, __bss_start  /* Load BSS start address */
    la t1, __bss_end    /* Load BSS end address */

bss_zero_loop:
    bge t0, t1, bss_zero_done  /* Exit if t0 >= t1 */
    sw zero, 0(t0)             /* Write zero to [t0] */
    addi t0, t0, 4             /* Increment t0 by 4 bytes */
    j bss_zero_loop

bss_zero_done:

    /* ====================================================================
     * Copy Read-Only Data Section from ROM (IMEM) to RAM (DMEM)
     * ==================================================================== */

    /* String constants and read-only data are stored in IMEM */
    /* They need to be copied to DMEM so load instructions can access them */
    /* (Harvard architecture: loads only access DMEM, not IMEM) */

    la t0, __rodata_load_start  /* Source: LMA (load address in IMEM) */
    la t1, __rodata_start       /* Destination: VMA (virtual address in DMEM) */
    la t2, __rodata_end         /* End address */

rodata_copy_loop:
    bge t1, t2, rodata_copy_done  /* Exit if t1 >= t2 */
    lw t3, 0(t0)                  /* Load word from source */
    sw t3, 0(t1)                  /* Store word to destination */
    addi t0, t0, 4                /* Increment source */
    addi t1, t1, 4                /* Increment destination */
    j rodata_copy_loop

rodata_copy_done:

    /* ====================================================================
     * Copy Data Section from ROM (IMEM) to RAM (DMEM)
     * ==================================================================== */

    /* Initialized global variables are stored in IMEM (read-only) */
    /* They need to be copied to DMEM (read-write) at startup */

    la t0, __data_load_start  /* Source: LMA (load address in IMEM) */
    la t1, __data_start       /* Destination: VMA (virtual address in DMEM) */
    la t2, __data_end         /* End address */

data_copy_loop:
    bge t1, t2, data_copy_done  /* Exit if t1 >= t2 */
    lw t3, 0(t0)                /* Load word from source */
    sw t3, 0(t1)                /* Store word to destination */
    addi t0, t0, 4              /* Increment source */
    addi t1, t1, 4              /* Increment destination */
    j data_copy_loop

data_copy_done:

    /* ====================================================================
     * Initialize Trap Vector (for interrupts and exceptions)
     * ==================================================================== */

    /* Set MTVEC to point to FreeRTOS interrupt handler */
    /* FreeRTOS provides: freertos_risc_v_trap_handler (in portASM.S) */
    la t0, freertos_risc_v_trap_handler
    csrw mtvec, t0

    /* MTVEC mode = 0 (Direct mode: all traps to same handler) */
    /* Note: FreeRTOS port expects Direct mode, not Vectored mode */

    /* ====================================================================
     * Enable Timer and Software Interrupts (for FreeRTOS tick)
     * ==================================================================== */

    /* Enable Machine Timer Interrupt (MTI) in MIE */
    li t0, 0x80         /* MTI = bit 7 */
    csrs mie, t0

    /* Enable Machine Software Interrupt (MSI) in MIE (for task yield) */
    li t0, 0x08         /* MSI = bit 3 */
    csrs mie, t0

    /* Note: MSTATUS.MIE (global interrupt enable) will be set by FreeRTOS
     * when the scheduler starts */

    /* ====================================================================
     * Call Constructors (C++ support, if any)
     * ==================================================================== */

    /* Call global constructors from .init_array section */
    la t0, __init_array_start
    la t1, __init_array_end

init_array_loop:
    bge t0, t1, init_array_done
    lw t2, 0(t0)       /* Load function pointer */
    jalr ra, t2, 0     /* Call constructor */
    addi t0, t0, 4     /* Next entry */
    j init_array_loop

init_array_done:

    /* ====================================================================
     * Jump to Main
     * ==================================================================== */

    /* Call main() - FreeRTOS application entry point */
    /* main() will initialize FreeRTOS and start scheduler */
    call main

    /* If main() returns (should never happen), halt */
halt:
    wfi                /* Wait for interrupt */
    j halt

    .size _start, . - _start

/* ========================================================================
 * Weak Trap Handler (used if FreeRTOS handler not linked)
 * ======================================================================== */

    .section .text
    .weak freertos_risc_v_trap_handler
    .type freertos_risc_v_trap_handler, @function

freertos_risc_v_trap_handler:
    /* Default trap handler - just halt */
    /* Should be overridden by FreeRTOS portASM.S */
trap_halt:
    wfi
    j trap_halt

    .size freertos_risc_v_trap_handler, . - freertos_risc_v_trap_handler

/* ========================================================================
 * Weak Hook Functions (can be overridden by application)
 * ======================================================================== */

    .weak vApplicationMallocFailedHook
    .weak vApplicationStackOverflowHook
    .weak vApplicationIdleHook
    .weak vApplicationTickHook
    .weak vApplicationAssertionFailed

/* Default implementations (do nothing) */
vApplicationMallocFailedHook:
vApplicationStackOverflowHook:
vApplicationIdleHook:
vApplicationTickHook:
    ret

/* Assertion failed - halt with WFI loop */
vApplicationAssertionFailed:
assert_halt:
    wfi
    j assert_halt

/* ========================================================================
 * Notes
 * ======================================================================== */

/*
 * Boot Flow:
 * 1. CPU starts at 0x00000000 (IMEM base)
 * 2. _start executes (this file)
 * 3. Initialize SP, GP, FPU
 * 4. Zero BSS
 * 5. Copy .rodata from IMEM to DMEM (string constants)
 * 6. Copy .data from IMEM to DMEM (initialized variables)
 * 7. Set trap vector to FreeRTOS handler
 * 8. Enable timer/software interrupts
 * 9. Call global constructors (C++)
 * 10. Call main()
 * 11. main() calls vTaskStartScheduler()
 * 12. FreeRTOS scheduler takes over
 * 13. Tasks run, timer interrupts for context switching
 *
 * Memory Architecture (Harvard):
 * - IMEM (0x0-0xFFFF): Code + ROM data (instruction fetch only)
 * - DMEM (0x8000_0000+): Data, BSS, Heap, Stack (load/store only)
 * - .rodata and .data copied from IMEM to DMEM at boot
 * - Load instructions can only access DMEM, not IMEM
 *
 * Interrupt Handling:
 * - MTVEC points to freertos_risc_v_trap_handler (portASM.S)
 * - Timer interrupts (MTI) trigger context switches
 * - Software interrupts (MSI) can be used for manual task yield
 * - All interrupt handling done in M-mode (no delegation yet)
 *
 * Stack Usage:
 * - __stack_top: Used by main() before scheduler starts
 * - After scheduler starts: Each task has its own stack (from heap)
 * - ISR stack: Reuses __stack_top (configISR_STACK_SIZE_WORDS)
 *
 * FPU Context:
 * - MSTATUS.FS initialized to 01 (Initial/Clean)
 * - FPU enabled globally
 * - Each task's FPU state saved/restored on context switch
 * - See freertos_risc_v_chip_specific_extensions.h for details
 */
