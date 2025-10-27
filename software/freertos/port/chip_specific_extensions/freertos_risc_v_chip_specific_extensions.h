/*
 * FreeRTOS Kernel V10.5.1 - RV1 Custom Port
 * Copyright (C) 2021 Amazon.com, Inc. or its affiliates.  All Rights Reserved.
 *
 * SPDX-License-Identifier: MIT
 *
 * Chip-Specific Extensions for RV1 RISC-V Core
 * Target: RV32IMAFDC (32-bit with FPU, Atomics, Compressed)
 */

#ifndef __FREERTOS_RISC_V_EXTENSIONS_H__
#define __FREERTOS_RISC_V_EXTENSIONS_H__

/* ========================================================================
 * Hardware Features
 * ======================================================================== */

/* This core has CLINT for timer interrupts */
#define portasmHAS_SIFIVE_CLINT 1

/* CLINT includes MTIME counter */
#define portasmHAS_MTIME 1

/* ========================================================================
 * FPU Context Size
 * ======================================================================== */

/*
 * RV32IMAFDC includes hardware floating-point (F and D extensions).
 * We need to save/restore:
 * - 32 FP registers (f0-f31): Each is 64 bits (FLEN=64 for D extension)
 * - 1 FCSR register: 32 bits (rounding mode + exception flags)
 *
 * Total FPU context:
 * - 32 registers × 8 bytes = 256 bytes
 * - 1 FCSR × 4 bytes (rounded to 8 for alignment) = 8 bytes
 * - Total = 264 bytes = 66 words
 *
 * IMPORTANT: Must be even number on 32-bit cores for stack alignment
 */
#define portasmADDITIONAL_CONTEXT_SIZE 66  /* 66 words = 264 bytes for FPU state */

/* ========================================================================
 * FPU Context Save/Restore Macros
 * ======================================================================== */

/*
 * Save FPU context to stack
 *
 * On entry: sp points to the top of the additional context area
 *           (32 integer registers already saved)
 *
 * Stack layout after save:
 *   sp+0:   f0  (64-bit)
 *   sp+8:   f1  (64-bit)
 *   ...
 *   sp+248: f31 (64-bit)
 *   sp+256: fcsr (32-bit, padded to 64-bit)
 */
.macro portasmSAVE_ADDITIONAL_REGISTERS
	/* Save all 32 floating-point registers (f0-f31) */
	/* Each FP register is 64 bits (FLEN=64 for RV32D) */
	fsd     f0,  0*8(sp)
	fsd     f1,  1*8(sp)
	fsd     f2,  2*8(sp)
	fsd     f3,  3*8(sp)
	fsd     f4,  4*8(sp)
	fsd     f5,  5*8(sp)
	fsd     f6,  6*8(sp)
	fsd     f7,  7*8(sp)
	fsd     f8,  8*8(sp)
	fsd     f9,  9*8(sp)
	fsd     f10, 10*8(sp)
	fsd     f11, 11*8(sp)
	fsd     f12, 12*8(sp)
	fsd     f13, 13*8(sp)
	fsd     f14, 14*8(sp)
	fsd     f15, 15*8(sp)
	fsd     f16, 16*8(sp)
	fsd     f17, 17*8(sp)
	fsd     f18, 18*8(sp)
	fsd     f19, 19*8(sp)
	fsd     f20, 20*8(sp)
	fsd     f21, 21*8(sp)
	fsd     f22, 22*8(sp)
	fsd     f23, 23*8(sp)
	fsd     f24, 24*8(sp)
	fsd     f25, 25*8(sp)
	fsd     f26, 26*8(sp)
	fsd     f27, 27*8(sp)
	fsd     f28, 28*8(sp)
	fsd     f29, 29*8(sp)
	fsd     f30, 30*8(sp)
	fsd     f31, 31*8(sp)

	/* Save FCSR (FP Control/Status Register) at offset 256 */
	csrr    t0, fcsr
	sw      t0, 256(sp)
	.endm

/*
 * Restore FPU context from stack
 *
 * On entry: sp points to the top of the additional context area
 *
 * Restores all FP registers and FCSR from stack
 */
.macro portasmRESTORE_ADDITIONAL_REGISTERS
	/* Restore FCSR first (at offset 256) */
	lw      t0, 256(sp)
	csrw    fcsr, t0

	/* Restore all 32 floating-point registers (f0-f31) */
	fld     f0,  0*8(sp)
	fld     f1,  1*8(sp)
	fld     f2,  2*8(sp)
	fld     f3,  3*8(sp)
	fld     f4,  4*8(sp)
	fld     f5,  5*8(sp)
	fld     f6,  6*8(sp)
	fld     f7,  7*8(sp)
	fld     f8,  8*8(sp)
	fld     f9,  9*8(sp)
	fld     f10, 10*8(sp)
	fld     f11, 11*8(sp)
	fld     f12, 12*8(sp)
	fld     f13, 13*8(sp)
	fld     f14, 14*8(sp)
	fld     f15, 15*8(sp)
	fld     f16, 16*8(sp)
	fld     f17, 17*8(sp)
	fld     f18, 18*8(sp)
	fld     f19, 19*8(sp)
	fld     f20, 20*8(sp)
	fld     f21, 21*8(sp)
	fld     f22, 22*8(sp)
	fld     f23, 23*8(sp)
	fld     f24, 24*8(sp)
	fld     f25, 25*8(sp)
	fld     f26, 26*8(sp)
	fld     f27, 27*8(sp)
	fld     f28, 28*8(sp)
	fld     f29, 29*8(sp)
	fld     f30, 30*8(sp)
	fld     f31, 31*8(sp)
	.endm

/* ========================================================================
 * Notes
 * ======================================================================== */

/*
 * Why save all 32 FP registers?
 * - RISC-V calling convention (ABI) divides FP registers into:
 *   - Caller-saved: f0-f7, f10-f17, f28-f31 (temporaries, args, return)
 *   - Callee-saved: f8-f9, f18-f27 (saved registers)
 * - FreeRTOS task switches are like function calls where the entire
 *   task context must be preserved
 * - We save ALL registers (both caller and callee-saved) because:
 *   1. Task may be preempted at any point (not just at call boundary)
 *   2. Ensures complete isolation between tasks
 *   3. Simpler and more robust than selective save
 *
 * FPU State Management:
 * - MSTATUS.FS (bits 13-14) tracks FPU state:
 *   - 00: Off (FPU disabled, instructions trap)
 *   - 01: Initial (FPU enabled, registers clean)
 *   - 10: Clean (FPU used, but context saved)
 *   - 11: Dirty (FPU used, context not saved)
 * - Our approach: Always save/restore FPU context on task switch
 *   - Simpler than tracking dirty state
 *   - Small overhead (264 bytes per task)
 *   - Ensures FPU always available to tasks
 *
 * Performance Optimization (Future):
 * - Could implement lazy FPU context switching:
 *   - Only save FPU if MSTATUS.FS == Dirty
 *   - Trap on first FPU use if FS == Off
 *   - Save previous task's FPU context in trap handler
 * - Saves ~264 bytes save/restore on context switch if FPU not used
 * - But adds complexity and trap overhead
 * - Current approach prioritizes simplicity and correctness
 */

#endif /* __FREERTOS_RISC_V_EXTENSIONS_H__ */
