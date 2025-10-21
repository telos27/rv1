// Floating-Point Register File
// Implements 32 floating-point registers (f0-f31)
// Supports both F extension (FLEN=32) and D extension (FLEN=64)
// Includes NaN boxing logic for single-precision values in double-precision registers

module fp_register_file #(
  parameter FLEN = 32  // 32 for F extension, 64 for D extension
) (
  input  wire              clk,
  input  wire              reset_n,

  // Read ports (3 ports for FMA instructions: rs1 × rs2 + rs3)
  input  wire [4:0]        rs1_addr,
  input  wire [4:0]        rs2_addr,
  input  wire [4:0]        rs3_addr,
  output wire [FLEN-1:0]   rs1_data,
  output wire [FLEN-1:0]   rs2_data,
  output wire [FLEN-1:0]   rs3_data,

  // Write port
  input  wire              wr_en,
  input  wire [4:0]        rd_addr,
  input  wire [FLEN-1:0]   rd_data,

  // NaN boxing control (for single-precision writes when FLEN=64)
  input  wire              write_single  // 1: writing single-precision, apply NaN boxing
);

  // Register array: 32 x FLEN bits
  reg [FLEN-1:0] registers [0:31];

  // Write data with NaN boxing (combinational)
  wire [FLEN-1:0] wr_data_boxed;
  assign wr_data_boxed = (FLEN == 64 && write_single) ? {32'hFFFFFFFF, rd_data[31:0]} : rd_data;

  // Combinational reads with internal forwarding (3 independent read ports)
  // If reading the register being written this cycle, forward the write data
  // This is critical for FP load-use cases where WB stage writes and ID stage reads in the same cycle
  assign rs1_data = (wr_en && (rd_addr == rs1_addr)) ? wr_data_boxed : registers[rs1_addr];
  assign rs2_data = (wr_en && (rd_addr == rs2_addr)) ? wr_data_boxed : registers[rs2_addr];
  assign rs3_data = (wr_en && (rd_addr == rs3_addr)) ? wr_data_boxed : registers[rs3_addr];

  `ifdef DEBUG_FPU
  always @(*) begin
    if (wr_en && (rd_addr == rs1_addr) && rs1_addr != 0) begin
      $display("[FP_REG_FWD] Internal forward rs1: f%0d = %h (write_data)", rs1_addr, wr_data_boxed);
    end
    if (wr_en && (rd_addr == rs2_addr) && rs2_addr != 0) begin
      $display("[FP_REG_FWD] Internal forward rs2: f%0d = %h (write_data)", rs2_addr, wr_data_boxed);
    end
    if (wr_en && (rd_addr == rs3_addr) && rs3_addr != 0) begin
      $display("[FP_REG_FWD] Internal forward rs3: f%0d = %h (write_data)", rs3_addr, wr_data_boxed);
    end
  end
  `endif

  // Sequential write
  integer i;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset all registers to +0.0
      for (i = 0; i < 32; i = i + 1) begin
        registers[i] <= {FLEN{1'b0}};
      end
    end else if (wr_en) begin
      // Write to register with optional NaN boxing
      registers[rd_addr] <= wr_data_boxed;
      `ifdef DEBUG_FPU
      if (FLEN == 64 && write_single) begin
        $display("[FP_REG] Write f%0d = %h (NaN-boxed single)", rd_addr, wr_data_boxed);
      end else begin
        $display("[FP_REG] Write f%0d = %h", rd_addr, wr_data_boxed);
      end
      `endif
    end
  end

  // Note: Unlike integer register file, f0 is NOT hardwired to zero
  // All floating-point registers are general-purpose

endmodule
