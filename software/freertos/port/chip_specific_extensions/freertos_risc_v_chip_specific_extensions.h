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
 *
 * WORKAROUND (2025-10-29): FP context save disabled due to instruction decode issue.
 * See: docs/CRITICAL_FPU_INSTRUCTION_DECODE_ISSUE.md
 * This prevents FreeRTOS from using FPU in interrupt context.
 */
#define portasmADDITIONAL_CONTEXT_SIZE 0  /* DISABLED: Was 66 words = 264 bytes for FPU state */

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
	/* FPU context save DISABLED - workaround for instruction decode issue */
	/* See: docs/CRITICAL_FPU_INSTRUCTION_DECODE_ISSUE.md */
	.endm

/*
 * Restore FPU context from stack
 *
 * On entry: sp points to the top of the additional context area
 *
 * Restores all FP registers and FCSR from stack
 */
.macro portasmRESTORE_ADDITIONAL_REGISTERS
	/* FPU context restore DISABLED - workaround for instruction decode issue */
	/* See: docs/CRITICAL_FPU_INSTRUCTION_DECODE_ISSUE.md */
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
