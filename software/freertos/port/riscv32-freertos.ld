/*
 * RISC-V Linker Script for FreeRTOS on RV1 Core
 *
 * Memory Layout:
 * - IMEM: 0x00000000 - 0x0000FFFF (64KB) - Program code
 * - DMEM: 0x80000000 - 0x800FFFFF (1MB)  - Data, BSS, Heap, Stack
 *
 * Created: 2025-10-27
 * Target: RV32IMAFDC
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

/* ========================================================================
 * Memory Regions
 * ======================================================================== */

MEMORY
{
    /* Instruction Memory (Harvard architecture) */
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K

    /* Data Memory (Harvard architecture) */
    DMEM (rwx) : ORIGIN = 0x80000000, LENGTH = 1M
}

/* Stack size for main/idle task before scheduler starts */
__stack_size = DEFINED(__stack_size) ? __stack_size : 4K;

/* Heap start/end will be defined after BSS */
/* FreeRTOS configTOTAL_HEAP_SIZE = 512K */

/* ========================================================================
 * Sections
 * ======================================================================== */

SECTIONS
{
    /* ====================================================================
     * Code Section (in IMEM)
     * ==================================================================== */

    .text : ALIGN(4)
    {
        __text_start = .;

        /* Interrupt vector table must be at 0x00000000 */
        KEEP(*(.text.init))
        KEEP(*(.text.vector))

        /* Startup code */
        *(.text.startup)
        *(.text.start)

        /* Regular code */
        *(.text)
        *(.text.*)

        /* Read-only data in code section */
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)

        /* C++ support (if needed) */
        *(.eh_frame)
        *(.gcc_except_table)

        . = ALIGN(4);
        __text_end = .;
    } > IMEM

    /* ====================================================================
     * Constructor/Destructor Tables (in IMEM)
     * ==================================================================== */

    .init_array : ALIGN(4)
    {
        __init_array_start = .;
        KEEP(*(.init_array))
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
        __init_array_end = .;
    } > IMEM

    .fini_array : ALIGN(4)
    {
        __fini_array_start = .;
        KEEP(*(.fini_array))
        KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*)))
        __fini_array_end = .;
    } > IMEM

    /* ====================================================================
     * Data Section (in DMEM, loaded from IMEM)
     * ==================================================================== */

    .data : ALIGN(8)
    {
        __data_start = .;
        __global_pointer$ = . + 0x800;  /* GP register base for ±2KB access */

        /* Small data (within ±2KB of GP) */
        *(.sdata)
        *(.sdata.*)

        /* Regular data */
        *(.data)
        *(.data.*)

        . = ALIGN(8);
        __data_end = .;
    } > DMEM AT > IMEM

    /* Store load address of .data in IMEM for startup code to copy */
    __data_load_start = LOADADDR(.data);

    /* ====================================================================
     * BSS Section (uninitialized data in DMEM)
     * ==================================================================== */

    .bss : ALIGN(8)
    {
        __bss_start = .;

        /* Small BSS */
        *(.sbss)
        *(.sbss.*)

        /* Regular BSS */
        *(.bss)
        *(.bss.*)
        *(COMMON)

        . = ALIGN(8);
        __bss_end = .;
    } > DMEM

    /* ====================================================================
     * Heap Section (for FreeRTOS dynamic allocation)
     * ==================================================================== */

    .heap : ALIGN(8)
    {
        __heap_start = .;
        . = . + 512K;  /* 512KB heap (configTOTAL_HEAP_SIZE) */
        __heap_end = .;
    } > DMEM

    /* ====================================================================
     * Stack Section (grows downward from end of DMEM)
     * ==================================================================== */

    .stack : ALIGN(16)
    {
        __stack_bottom = .;
        . = . + __stack_size;
        __stack_top = .;
    } > DMEM

    /* FreeRTOS ISR stack (used by portASM.S) */
    __freertos_irq_stack_top = __stack_top;

    /* ====================================================================
     * Debug Sections (not loaded to target)
     * ==================================================================== */

    /* DWARF debug sections */
    .debug_info     0 : { *(.debug_info) }
    .debug_abbrev   0 : { *(.debug_abbrev) }
    .debug_line     0 : { *(.debug_line) }
    .debug_frame    0 : { *(.debug_frame) }
    .debug_str      0 : { *(.debug_str) }
    .debug_loc      0 : { *(.debug_loc) }
    .debug_ranges   0 : { *(.debug_ranges) }

    /* Discard unnecessary sections */
    /DISCARD/ :
    {
        *(.note.GNU-stack)
        *(.gnu_debuglink)
        *(.gnu.lto_*)
    }
}

/* ========================================================================
 * Symbol Exports (for startup code and FreeRTOS)
 * ======================================================================== */

/* Text (code) region */
PROVIDE(__text_start = ORIGIN(IMEM));
PROVIDE(__text_size = __text_end - __text_start);

/* Data region (initialized data) */
PROVIDE(__data_size = __data_end - __data_start);

/* BSS region (zero-initialized data) */
PROVIDE(__bss_size = __bss_end - __bss_start);

/* Heap region (for malloc/FreeRTOS heap_4) */
PROVIDE(__heap_size = __heap_end - __heap_start);

/* Stack region */
PROVIDE(__stack_size_actual = __stack_top - __stack_bottom);

/* Memory map boundaries (for validation) */
PROVIDE(__imem_start = ORIGIN(IMEM));
PROVIDE(__imem_end = ORIGIN(IMEM) + LENGTH(IMEM));
PROVIDE(__dmem_start = ORIGIN(DMEM));
PROVIDE(__dmem_end = ORIGIN(DMEM) + LENGTH(DMEM));

/* End of DMEM used (for overflow detection) */
PROVIDE(__dmem_used_end = __stack_top);

/* ========================================================================
 * Validation Checks
 * ======================================================================== */

/* Ensure we don't overflow IMEM */
ASSERT(__text_end <= (__imem_start + LENGTH(IMEM)), "ERROR: Code section overflows IMEM")

/* Ensure we don't overflow DMEM */
ASSERT(__dmem_used_end <= (__dmem_start + LENGTH(DMEM)), "ERROR: Data+BSS+Heap+Stack overflows DMEM")

/* Ensure stack is properly aligned (16-byte for RISC-V) */
ASSERT((__stack_top & 0xF) == 0, "ERROR: Stack top is not 16-byte aligned")

/* Ensure heap is properly aligned (8-byte minimum) */
ASSERT((__heap_start & 0x7) == 0, "ERROR: Heap start is not 8-byte aligned")

/* Sanity check: GP base should be in DMEM */
ASSERT(__global_pointer$ >= __dmem_start && __global_pointer$ < __dmem_end, "ERROR: Global pointer outside DMEM")

/* ========================================================================
 * Memory Usage Summary
 * ======================================================================== */

/*
 * Expected Layout in DMEM (0x80000000 - 0x800FFFFF = 1MB):
 *
 * 0x80000000: .data start (initialized data copied from IMEM)
 * 0x8000XXXX: .data end
 * 0x8000XXXX: .bss start (zero-initialized)
 * 0x800XXXXX: .bss end
 * 0x800XXXXX: .heap start (512KB reserved)
 * 0x800XXXXX: .heap end (= heap_start + 512K)
 * 0x800XXXXX: .stack bottom (4KB reserved)
 * 0x800XXXXX: .stack top (grows downward, = __freertos_irq_stack_top)
 * 0x800FFFFF: End of DMEM
 *
 * Notes:
 * - .data and .bss are small (typically <64KB for FreeRTOS)
 * - Heap is 512KB (half of DMEM) - used by FreeRTOS tasks
 * - Stack is 4KB - used before scheduler starts (main/idle task)
 * - After scheduler starts, each task has its own stack (allocated from heap)
 * - ISR stack is shared with initial stack (__freertos_irq_stack_top)
 */
