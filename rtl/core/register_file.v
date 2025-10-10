// register_file.v - 32-register register file for RISC-V
// Implements 32 general-purpose registers with x0 hardwired to zero
// Author: RV1 Project
// Date: 2025-10-09
// Updated: 2025-10-10 - Parameterized for XLEN (32/64-bit support)

`include "config/rv_config.vh"

module register_file #(
  parameter XLEN = `XLEN  // Register width: 32 or 64 bits
) (
  input  wire             clk,         // Clock
  input  wire             reset_n,     // Active-low reset
  input  wire [4:0]       rs1_addr,    // Read port 1 address
  input  wire [4:0]       rs2_addr,    // Read port 2 address
  input  wire [4:0]       rd_addr,     // Write port address
  input  wire [XLEN-1:0]  rd_data,     // Write port data
  input  wire             rd_wen,      // Write enable
  output wire [XLEN-1:0]  rs1_data,    // Read port 1 data
  output wire [XLEN-1:0]  rs2_data     // Read port 2 data
);

  // Register array (x0-x31)
  // RV32: 32 x 32-bit registers
  // RV64: 32 x 64-bit registers
  reg [XLEN-1:0] registers [0:31];

  // Initialize registers and write on posedge
  integer i;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset all registers to zero
      for (i = 0; i < 32; i = i + 1) begin
        registers[i] <= {XLEN{1'b0}};
      end
    end else begin
      // Write operation
      if (rd_wen && rd_addr != 5'h0) begin
        // x0 is hardwired to zero, so don't write to it
        registers[rd_addr] <= rd_data;
      end
    end
  end

  // Read operations (combinational with internal forwarding)
  // x0 always reads as zero
  // Internal forwarding: if reading the register being written, return write data
  assign rs1_data = (rs1_addr == 5'h0) ? {XLEN{1'b0}} :
                    (rd_wen && (rd_addr == rs1_addr) && (rd_addr != 5'h0)) ? rd_data :
                    registers[rs1_addr];
  assign rs2_data = (rs2_addr == 5'h0) ? {XLEN{1'b0}} :
                    (rd_wen && (rd_addr == rs2_addr) && (rd_addr != 5'h0)) ? rd_data :
                    registers[rs2_addr];

endmodule
