// IF/ID Pipeline Register
// Latches outputs from Instruction Fetch stage for use in Decode stage
// Supports stall (hold current value) and flush (insert NOP bubble)
// Updated: 2025-10-10 - Parameterized for XLEN (32/64-bit support)

`include "config/rv_config.vh"

module ifid_register #(
  parameter XLEN = `XLEN  // PC width: 32 or 64 bits
) (
  input  wire             clk,
  input  wire             reset_n,
  input  wire             stall,           // Hold current values (for load-use hazard)
  input  wire             flush,           // Clear to NOP (for branch misprediction)

  // Inputs from IF stage
  input  wire [XLEN-1:0]  pc_in,
  input  wire [31:0]      instruction_in,  // Instructions always 32-bit
  input  wire             is_compressed_in, // Was the original instruction compressed?
  input  wire             page_fault_in,    // Session 117: Instruction page fault
  input  wire [XLEN-1:0]  fault_vaddr_in,   // Session 117: Faulting virtual address

  // Outputs to ID stage
  output reg  [XLEN-1:0]  pc_out,
  output reg  [31:0]      instruction_out,
  output reg              valid_out,       // 0 = bubble (NOP), 1 = valid instruction
  output reg              is_compressed_out, // Pipelined compressed flag
  output reg              page_fault_out,    // Session 117: Instruction page fault
  output reg  [XLEN-1:0]  fault_vaddr_out   // Session 117: Faulting virtual address
);

  // NOP instruction encoding (ADDI x0, x0, 0)
  localparam NOP = 32'h00000013;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset: insert NOP bubble
      pc_out            <= {XLEN{1'b0}};
      instruction_out   <= NOP;
      valid_out         <= 1'b0;
      is_compressed_out <= 1'b0;  // NOPs are not compressed
      page_fault_out    <= 1'b0;  // Session 117
      fault_vaddr_out   <= {XLEN{1'b0}};  // Session 117
    end else if (flush) begin
      // Flush: insert NOP bubble (branch taken)
      pc_out            <= {XLEN{1'b0}};
      instruction_out   <= NOP;
      valid_out         <= 1'b0;
      is_compressed_out <= 1'b0;  // NOPs are not compressed
      page_fault_out    <= 1'b0;  // Session 117: Clear page fault on flush
      fault_vaddr_out   <= {XLEN{1'b0}};  // Session 117
    end else if (stall) begin
      // Stall: hold current values (load-use hazard)
      pc_out            <= pc_out;
      instruction_out   <= instruction_out;
      valid_out         <= valid_out;
      is_compressed_out <= is_compressed_out;
      page_fault_out    <= page_fault_out;  // Session 117
      fault_vaddr_out   <= fault_vaddr_out;  // Session 117
    end else begin
      // Normal operation: latch new values
      pc_out            <= pc_in;
      instruction_out   <= instruction_in;
      valid_out         <= 1'b1;
      is_compressed_out <= is_compressed_in;
      page_fault_out    <= page_fault_in;  // Session 117
      fault_vaddr_out   <= fault_vaddr_in;  // Session 117
    end
  end

endmodule
