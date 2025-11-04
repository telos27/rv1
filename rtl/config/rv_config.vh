// rv_config.vh - RISC-V Core Configuration Parameters
// Central configuration file for parameterizing core variants
// Author: RV1 Project
// Date: 2025-10-10
// Updated: 2025-10-23 - Added C extension configuration note

`ifndef RV_CONFIG_VH
`define RV_CONFIG_VH

// ============================================================================
// IMPORTANT: C Extension Configuration Requirement
// ============================================================================
//
// When running tests with COMPRESSED INSTRUCTIONS, you MUST use a
// configuration that has ENABLE_C_EXT=1:
//
//   ✅ CORRECT:   -DCONFIG_RV32IMC, -DCONFIG_RV32IMAFC, -DCONFIG_RV32IMAFDC
//   ❌ INCORRECT: -DCONFIG_RV32I, -DCONFIG_RV32IM, -DCONFIG_RV32IMA
//
// WHY: The exception unit checks PC alignment based on ENABLE_C_EXT.
//      Without C extension enabled, 2-byte aligned PCs (0x02, 0x06, etc.)
//      trigger "instruction address misaligned" exceptions, causing infinite
//      trap loops at address 0x00.
//
// See KNOWN_ISSUES.md for detailed analysis.
// ============================================================================

// ============================================================================
// Architecture Width Configuration
// ============================================================================

// XLEN: Integer register and data path width (32 or 64)
// Phase 3 (2025-11-03): Default changed to 64 for RV64 upgrade
`ifndef XLEN
  `define XLEN 64
`endif

// FLEN: Floating-point register width (0=no FPU, 32=F only, 64=F+D)
`ifndef FLEN
  `define FLEN 64  // Default to 64 to support both F and D extensions
`endif

// DWIDTH: Data memory interface width (use FLEN to support RV32D with 64-bit FP loads/stores)
// For RV32I/M/A/C: XLEN=32, FLEN=0, DWIDTH should be 32
// For RV32F: XLEN=32, FLEN=32, DWIDTH=32
// For RV32D: XLEN=32, FLEN=64, DWIDTH=64
`ifndef DWIDTH
  `define DWIDTH `FLEN  // Use FLEN as data width to support wide FP loads/stores
`endif

// Derived parameters
`define XLEN_MINUS_1 (`XLEN - 1)
`define SHAMT_WIDTH  ($clog2(`XLEN))  // Shift amount width: 5 for RV32, 6 for RV64

// ============================================================================
// ISA Extension Configuration
// ============================================================================

// M Extension: Integer Multiply/Divide
`ifndef ENABLE_M_EXT
  `define ENABLE_M_EXT 0
`endif

// A Extension: Atomic Instructions
`ifndef ENABLE_A_EXT
  `define ENABLE_A_EXT 0
`endif

// C Extension: Compressed Instructions (16-bit)
`ifndef ENABLE_C_EXT
  `define ENABLE_C_EXT 0
`endif

// Zicsr: CSR Instructions (always enabled for now)
`ifndef ENABLE_ZICSR
  `define ENABLE_ZICSR 1
`endif

// Zifencei: Instruction Fence (requires I-cache)
`ifndef ENABLE_ZIFENCEI
  `define ENABLE_ZIFENCEI 0
`endif

// ============================================================================
// Cache Configuration
// ============================================================================

// Instruction Cache
`ifndef ICACHE_SIZE
  `define ICACHE_SIZE 4096  // 4KB default
`endif

`ifndef ICACHE_LINE_SIZE
  `define ICACHE_LINE_SIZE 32  // 32 bytes (8 words)
`endif

`ifndef ICACHE_WAYS
  `define ICACHE_WAYS 1  // Direct-mapped by default
`endif

// Data Cache
`ifndef DCACHE_SIZE
  `define DCACHE_SIZE 4096  // 4KB default
`endif

`ifndef DCACHE_LINE_SIZE
  `define DCACHE_LINE_SIZE 32  // 32 bytes (8 words)
`endif

`ifndef DCACHE_WAYS
  `define DCACHE_WAYS 1  // Direct-mapped by default
`endif

// L2 Cache (for multicore)
`ifndef L2_CACHE_SIZE
  `define L2_CACHE_SIZE 65536  // 64KB default
`endif

`ifndef L2_CACHE_ENABLE
  `define L2_CACHE_ENABLE 0
`endif

// ============================================================================
// Multicore Configuration
// ============================================================================

`ifndef NUM_CORES
  `define NUM_CORES 1
`endif

`ifndef ENABLE_COHERENCY
  `define ENABLE_COHERENCY 0
`endif

// ============================================================================
// Memory Configuration
// ============================================================================

// Memory sizes (in bytes)
// Phase 2 (2025-10-27): Expanded DMEM to 1MB for FreeRTOS
// Phase 3 (2025-11-03): Expanded to 1MB IMEM, 4MB DMEM for xv6/Linux
`ifndef IMEM_SIZE
  `define IMEM_SIZE 1048576  // 1MB instruction memory (Phase 3: RV64 upgrade)
`endif

`ifndef DMEM_SIZE
  `define DMEM_SIZE 4194304  // 4MB data memory (Phase 3: RV64 upgrade, xv6 preparation)
`endif

// Address width (derived from memory size)
`define IMEM_ADDR_WIDTH $clog2(`IMEM_SIZE)
`define DMEM_ADDR_WIDTH $clog2(`DMEM_SIZE)

// TLB Configuration
`ifndef TLB_ENTRIES
  `define TLB_ENTRIES 16  // Number of TLB entries (power of 2)
`endif

// ============================================================================
// Pipeline Configuration
// ============================================================================

`ifndef PIPELINE_STAGES
  `define PIPELINE_STAGES 5  // Classic 5-stage pipeline
`endif

// ============================================================================
// Debug and Verification
// ============================================================================

`ifndef ENABLE_ASSERTIONS
  `define ENABLE_ASSERTIONS 1
`endif

`ifndef ENABLE_COVERAGE
  `define ENABLE_COVERAGE 0
`endif

// ============================================================================
// Common Presets
// ============================================================================

// To use a preset, include one of these before including rv_config.vh:
//
// RV32I - Minimal 32-bit base ISA
//   -DCONFIG_RV32I
//
// RV32IM - 32-bit with multiply/divide
//   -DCONFIG_RV32IM
//
// RV32IMC - 32-bit with M and compressed
//   -DCONFIG_RV32IMC
//
// RV64I - 64-bit base ISA
//   -DCONFIG_RV64I
//
// RV64GC - 64-bit full-featured (IMAFC + Zicsr + Zifencei)
//   -DCONFIG_RV64GC

`ifdef CONFIG_RV32I
  `undef XLEN
  `define XLEN 32
  // Only set defaults if not already defined from command line
  `ifndef ENABLE_M_EXT
    `define ENABLE_M_EXT 0
  `endif
  `ifndef ENABLE_A_EXT
    `define ENABLE_A_EXT 0
  `endif
  `ifndef ENABLE_C_EXT
    `define ENABLE_C_EXT 0
  `endif
`endif

`ifdef CONFIG_RV32IM
  `undef XLEN
  `define XLEN 32
  `define ENABLE_M_EXT 1
  // Only set defaults if not already defined from command line
  `ifndef ENABLE_A_EXT
    `define ENABLE_A_EXT 0
  `endif
  `ifndef ENABLE_C_EXT
    `define ENABLE_C_EXT 0
  `endif
`endif

`ifdef CONFIG_RV32IMA
  `undef XLEN
  `define XLEN 32
  `undef ENABLE_M_EXT
  `define ENABLE_M_EXT 1
  `undef ENABLE_A_EXT
  `define ENABLE_A_EXT 1
  `undef ENABLE_C_EXT
  `define ENABLE_C_EXT 0
`endif

`ifdef CONFIG_RV32IMC
  `undef XLEN
  `define XLEN 32
  `undef ENABLE_M_EXT
  `define ENABLE_M_EXT 1
  `undef ENABLE_A_EXT
  `define ENABLE_A_EXT 0
  `undef ENABLE_C_EXT
  `define ENABLE_C_EXT 1
`endif

`ifdef CONFIG_RV32IMAF
  `undef XLEN
  `define XLEN 32
  `undef ENABLE_M_EXT
  `define ENABLE_M_EXT 1
  `undef ENABLE_A_EXT
  `define ENABLE_A_EXT 1
  `undef ENABLE_C_EXT
  `define ENABLE_C_EXT 0
  `undef ENABLE_F_EXT
  `define ENABLE_F_EXT 1
`endif

// ============================================================================
// DEPRECATED: CONFIG_RV64I and CONFIG_RV64GC
// ============================================================================
// These configuration shortcuts are deprecated in favor of explicit defines.
// Use command-line defines instead:
//   RV64I:  -DXLEN=64
//   RV64GC: -DXLEN=64 -DENABLE_M_EXT=1 -DENABLE_A_EXT=1 -DENABLE_C_EXT=1
//
// The blocks below are kept for backwards compatibility but do NOT override
// command-line defines (no undef).
// ============================================================================

`ifdef CONFIG_RV64I
  `ifndef XLEN
    `define XLEN 64
  `endif
  // Extensions default to OFF for minimal RV64I
  `ifndef ENABLE_M_EXT
    `define ENABLE_M_EXT 0
  `endif
  `ifndef ENABLE_A_EXT
    `define ENABLE_A_EXT 0
  `endif
  `ifndef ENABLE_C_EXT
    `define ENABLE_C_EXT 0
  `endif
`endif

`ifdef CONFIG_RV64GC
  `ifndef XLEN
    `define XLEN 64
  `endif
  // Extensions default to ON for RV64GC
  `ifndef ENABLE_M_EXT
    `define ENABLE_M_EXT 1
  `endif
  `ifndef ENABLE_A_EXT
    `define ENABLE_A_EXT 1
  `endif
  `ifndef ENABLE_C_EXT
    `define ENABLE_C_EXT 1
  `endif
  `ifndef ENABLE_ZIFENCEI
    `define ENABLE_ZIFENCEI 1
  `endif
`endif

`endif // RV_CONFIG_VH
