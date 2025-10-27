// dmem_bus_adapter.v - Bus Adapter for Data Memory
// Adapts the data_memory module to the simple_bus interface
// Author: RV1 Project
// Date: 2025-10-27

`include "config/rv_config.vh"

module dmem_bus_adapter #(
  parameter XLEN     = `XLEN,
  parameter FLEN     = `FLEN,
  parameter MEM_SIZE = 16384,
  parameter MEM_FILE = ""
) (
  input  wire             clk,
  input  wire             reset_n,

  // Bus slave interface
  input  wire             req_valid,
  input  wire [XLEN-1:0]  req_addr,
  input  wire [63:0]      req_wdata,
  input  wire             req_we,
  input  wire [2:0]       req_size,
  output wire             req_ready,
  output wire [63:0]      req_rdata
);

  // Data memory is synchronous and always ready (1-cycle latency)
  assign req_ready = 1'b1;

  // Instantiate data memory
  data_memory #(
    .XLEN(XLEN),
    .FLEN(FLEN),
    .MEM_SIZE(MEM_SIZE),
    .MEM_FILE(MEM_FILE)
  ) dmem (
    .clk(clk),
    .addr(req_addr),
    .write_data(req_wdata),
    .mem_read(req_valid && !req_we),
    .mem_write(req_valid && req_we),
    .funct3(req_size),
    .read_data(req_rdata)
  );

endmodule
