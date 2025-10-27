// rv_soc.v - RV1 System-on-Chip
// Simple SoC wrapper integrating CPU core with CLINT peripheral
// Phase 1: CLINT timer and software interrupts
// Author: RV1 Project
// Date: 2025-10-26

`include "config/rv_config.vh"

module rv_soc #(
  parameter XLEN = `XLEN,
  parameter RESET_VECTOR = {XLEN{1'b0}},
  parameter IMEM_SIZE = 16384,      // 16KB instruction memory
  parameter DMEM_SIZE = 16384,      // 16KB data memory
  parameter MEM_FILE = "",
  parameter NUM_HARTS = 1           // Number of hardware threads
) (
  input  wire             clk,
  input  wire             reset_n,

  // Debug outputs
  output wire [XLEN-1:0]  pc_out,
  output wire [31:0]      instr_out
);

  //==========================================================================
  // Internal Signals
  //==========================================================================

  // CLINT interrupt outputs
  wire             mtip;              // Machine Timer Interrupt
  wire             msip;              // Machine Software Interrupt

  //==========================================================================
  // CPU Core
  //==========================================================================

  rv_core_pipelined #(
    .XLEN(XLEN),
    .RESET_VECTOR(RESET_VECTOR),
    .IMEM_SIZE(IMEM_SIZE),
    .DMEM_SIZE(DMEM_SIZE),
    .MEM_FILE(MEM_FILE)
  ) core (
    .clk(clk),
    .reset_n(reset_n),
    .mtip_in(mtip),
    .msip_in(msip),
    .pc_out(pc_out),
    .instr_out(instr_out)
  );

  //==========================================================================
  // CLINT (Core-Local Interruptor)
  //==========================================================================
  // Note: For Phase 1, CLINT is included but not memory-mapped yet.
  // Memory-mapped access will be added in future phases when we implement
  // a proper bus interconnect. For now, CLINT runs autonomously with
  // MTIME incrementing and MTIMECMP initialized to max (no interrupts).

  clint #(
    .NUM_HARTS(NUM_HARTS),
    .BASE_ADDR(32'h0200_0000)
  ) clint_inst (
    .clk(clk),
    .reset_n(reset_n),
    // Memory-mapped interface (not connected yet - Phase 2)
    .req_valid(1'b0),                // No memory-mapped access yet
    .req_addr(16'h0),
    .req_wdata(64'h0),
    .req_we(1'b0),
    .req_size(3'h0),
    .req_ready(),                    // Unused
    .req_rdata(),                    // Unused
    // Interrupt outputs
    .mti_o(mtip),
    .msi_o(msip)
  );

endmodule
