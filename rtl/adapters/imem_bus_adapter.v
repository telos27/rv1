// imem_bus_adapter.v - IMEM Bus Adapter
// Adapts instruction memory for bus access (read-only)
// Author: RV1 Project
// Date: 2025-10-27 (Session 33)
//
// Purpose: Allow data loads from IMEM for .rodata section copy
// This enables startup code to copy read-only data from IMEM to DMEM
// in a Harvard architecture system.

`include "config/rv_config.vh"

module imem_bus_adapter (
  input  wire             clk,
  input  wire             reset_n,

  // Bus slave interface (read-only)
  input  wire             req_valid,
  input  wire [31:0]      req_addr,
  output wire             req_ready,
  output wire [31:0]      req_rdata,

  // Instruction memory interface
  output wire [31:0]      imem_addr,
  input  wire [31:0]      imem_rdata
);

  // Simple passthrough - IMEM already has combinational read
  assign imem_addr  = req_addr;
  assign req_rdata  = imem_rdata;
  assign req_ready  = req_valid;  // Always ready for reads

endmodule
