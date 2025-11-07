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

  // Session 114: Registered memory has 1-cycle read latency
  // - Writes: Complete in 0 cycles (ready immediately)
  // - Reads: Complete in 1 cycle (ready next cycle after request accepted)
  // This matches FPGA BRAM behavior with registered outputs
  //
  // Protocol:
  // Cycle N:   req_valid=1, req_we=0 (read request) → req_ready=0 (not ready yet)
  // Cycle N+1: req_valid=1 (still requesting) → req_ready=1 (data now ready)
  //
  // The CPU will stall for one cycle when req_ready=0, then proceed when req_ready=1

  reg read_in_progress_r;

  always @(posedge clk) begin
    if (!reset_n) begin
      read_in_progress_r <= 1'b0;
    end else begin
      // Set when we accept a read request, clear when ready
      if (req_valid && !req_we && !read_in_progress_r) begin
        // New read request - will take 1 cycle
        read_in_progress_r <= 1'b1;
      end else if (read_in_progress_r) begin
        // Read completes after 1 cycle
        read_in_progress_r <= 1'b0;
      end
    end
  end

  // Ready signal:
  // - Writes: Always ready immediately (0-cycle latency)
  // - Reads: NOT ready on first cycle (req_valid && !req_we && !read_in_progress)
  //          Ready on second cycle (read_in_progress_r)
  assign req_ready = req_we || read_in_progress_r;

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
