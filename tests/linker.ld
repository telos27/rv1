/* RISC-V Linker Script for RV1 Processor */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    /* Instruction Memory: 4KB starting at 0x0000_0000 */
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K

    /* Data Memory: 12KB starting at 0x0000_1000 (increased for VM tests with page tables) */
    DMEM (rw)  : ORIGIN = 0x00001000, LENGTH = 12K
}

SECTIONS {
    /* Code section in instruction memory */
    .text : {
        *(.text.init)       /* Entry point first */
        *(.text)
        *(.text.*)
        . = ALIGN(4);
    } > IMEM

    /* Read-only data */
    .rodata : {
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(4);
    } > DMEM

    /* Initialized data */
    .data : {
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4);
    } > DMEM

    /* Uninitialized data */
    .bss : {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > DMEM

    /* Stack grows down from end of DMEM */
    . = ORIGIN(DMEM) + LENGTH(DMEM);
    __stack_top = .;

    /* Discard sections we don't need */
    /DISCARD/ : {
        *(.comment)
        *(.eh_frame)
        *(.note*)
    }
}

/* Define stack pointer initial value */
PROVIDE(__stack_pointer = __stack_top);

/* Entry point symbol */
PROVIDE(_start = 0x00000000);
