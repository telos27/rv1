.section .text
.globl _start

_start:
    # Enable FPU by setting MSTATUS.FS = 11 (Dirty)
    li      t0, 0x6000          # FS[14:13] = 11
    csrrs   zero, mstatus, t0

    # Set up stack pointer
    la      sp, test_stack + 4096

    # Store a double-precision value on stack
    li      t0, 0x12345678
    li      t1, 0x9ABCDEF0
    addi    sp, sp, -16         # Make space for double
    sw      t0, 0(sp)           # Store low word
    sw      t1, 4(sp)           # Store high word

    # Test C.FLDSP instruction (compressed FLD from stack)
    # C.FLDSP fa5, 8(sp)
    # Format: 001 uimm[5] rd uimm[4:3|8:6] 10
    # uimm = 8 = 0000_1000 → uimm[5]=0, uimm[4:3]=01, uimm[8:6]=000
    # rd = fa5 = 15 = 01111
    # = 001_0_01111_00001_10 = 0x2786
    sw      t0, 8(sp)
    sw      t1, 12(sp)

    # Use .2byte to force compressed instruction
    .2byte  0x2786              # C.FLDSP fa5, 8(sp)

    # If we get here, instruction succeeded
    li      a0, 42              # Success value
    j       test_pass

test_pass:
    li      a0, 0
    j       done

test_fail:
    li      a0, 1
    j       done

done:
    # Success - write to test result register
    li      t0, 0x02003000      # UART base
    li      t1, 0x50            # 'P' for pass
    beqz    a0, 1f
    li      t1, 0x46            # 'F' for fail
1:
    sw      t1, 0(t0)

    # Infinite loop
2:  j       2b

# Trap handler for illegal instruction
.align 4
trap_handler:
    # If we trapped, test failed
    li      a0, 1
    # Return from trap (skip faulting instruction)
    csrr    t0, mepc
    addi    t0, t0, 2           # Skip 2-byte compressed instruction
    csrw    mepc, t0
    mret

.section .data
.align 12
test_stack:
    .space 4096

.section .rodata
mtvec_val:
    .word trap_handler
