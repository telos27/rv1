// pc.v - Program Counter for RISC-V
// Holds and updates the program counter
// Author: RV1 Project
// Date: 2025-10-09
// Updated: 2025-10-10 - Parameterized for XLEN (32/64-bit support)

`include "config/rv_config.vh"

module pc #(
  parameter XLEN = `XLEN,               // PC width: 32 or 64 bits
  parameter RESET_VECTOR = {XLEN{1'b0}} // Reset vector (default: 0x0)
) (
  input  wire             clk,         // Clock
  input  wire             reset_n,     // Active-low reset
  input  wire             stall,       // Stall signal (freeze PC)
  input  wire [XLEN-1:0]  pc_next,     // Next PC value
  output reg  [XLEN-1:0]  pc_current   // Current PC value
);

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      pc_current <= RESET_VECTOR;
    end else if (!stall) begin
      pc_current <= pc_next;
    end
    // If stall is high, PC holds its current value
  end

endmodule
