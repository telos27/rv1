// Forwarding Unit
// Detects data hazards and generates forwarding control signals
// Implements EX-to-EX and MEM-to-EX forwarding paths

module forwarding_unit (
  // Inputs from ID/EX register (current instruction in EX stage)
  input  wire [4:0] idex_rs1,          // Source register 1 address (integer)
  input  wire [4:0] idex_rs2,          // Source register 2 address (integer)

  // Inputs from EX/MEM register (previous instruction in MEM stage)
  input  wire [4:0] exmem_rd,          // Destination register address (integer)
  input  wire       exmem_reg_write,   // Register write enable (integer)

  // Inputs from MEM/WB register (instruction in WB stage)
  input  wire [4:0] memwb_rd,          // Destination register address (integer)
  input  wire       memwb_reg_write,   // Register write enable (integer)

  // Forwarding control outputs (integer registers)
  output reg  [1:0] forward_a,         // Forward select for operand A
  output reg  [1:0] forward_b,         // Forward select for operand B

  // F/D extension: FP register forwarding inputs
  input  wire [4:0] idex_fp_rs1,       // FP source register 1 address
  input  wire [4:0] idex_fp_rs2,       // FP source register 2 address
  input  wire [4:0] idex_fp_rs3,       // FP source register 3 address (FMA)
  input  wire [4:0] exmem_fp_rd,       // FP destination register address (MEM stage)
  input  wire       exmem_fp_reg_write,// FP register write enable (MEM stage)
  input  wire [4:0] memwb_fp_rd,       // FP destination register address (WB stage)
  input  wire       memwb_fp_reg_write,// FP register write enable (WB stage)

  // FP forwarding control outputs
  output reg  [1:0] fp_forward_a,      // FP forward select for operand A
  output reg  [1:0] fp_forward_b,      // FP forward select for operand B
  output reg  [1:0] fp_forward_c       // FP forward select for operand C (FMA)
);

  // Forward select encoding:
  //   2'b00: No forwarding (use register file data)
  //   2'b01: Forward from MEM/WB stage
  //   2'b10: Forward from EX/MEM stage

  always @(*) begin
    // Default: no forwarding
    forward_a = 2'b00;

    // EX hazard (highest priority): Forward from EX/MEM
    // Condition: EX/MEM.reg_write AND EX/MEM.rd != 0 AND EX/MEM.rd == ID/EX.rs1
    if (exmem_reg_write && (exmem_rd != 5'h0) && (exmem_rd == idex_rs1)) begin
      forward_a = 2'b10;
    end
    // MEM hazard: Forward from MEM/WB (only if no EX hazard)
    // Condition: MEM/WB.reg_write AND MEM/WB.rd != 0 AND MEM/WB.rd == ID/EX.rs1
    //            AND NOT (EX/MEM forwarding for rs1)
    else if (memwb_reg_write && (memwb_rd != 5'h0) && (memwb_rd == idex_rs1)) begin
      forward_a = 2'b01;
    end
  end

  always @(*) begin
    // Default: no forwarding
    forward_b = 2'b00;

    // EX hazard (highest priority): Forward from EX/MEM
    if (exmem_reg_write && (exmem_rd != 5'h0) && (exmem_rd == idex_rs2)) begin
      forward_b = 2'b10;
    end
    // MEM hazard: Forward from MEM/WB (only if no EX hazard)
    else if (memwb_reg_write && (memwb_rd != 5'h0) && (memwb_rd == idex_rs2)) begin
      forward_b = 2'b01;
    end
  end

  // ========================================
  // FP Register Forwarding Logic
  // ========================================
  // Same logic as integer forwarding, but for FP register file
  // Note: FP registers can have f0 as destination (unlike integer x0)

  always @(*) begin
    // Default: no forwarding
    fp_forward_a = 2'b00;

    // EX hazard (highest priority): Forward from EX/MEM
    if (exmem_fp_reg_write && (exmem_fp_rd == idex_fp_rs1)) begin
      fp_forward_a = 2'b10;
    end
    // MEM hazard: Forward from MEM/WB (only if no EX hazard)
    else if (memwb_fp_reg_write && (memwb_fp_rd == idex_fp_rs1)) begin
      fp_forward_a = 2'b01;
    end
  end

  always @(*) begin
    // Default: no forwarding
    fp_forward_b = 2'b00;

    // EX hazard (highest priority): Forward from EX/MEM
    if (exmem_fp_reg_write && (exmem_fp_rd == idex_fp_rs2)) begin
      fp_forward_b = 2'b10;
    end
    // MEM hazard: Forward from MEM/WB (only if no EX hazard)
    else if (memwb_fp_reg_write && (memwb_fp_rd == idex_fp_rs2)) begin
      fp_forward_b = 2'b01;
    end
  end

  always @(*) begin
    // Default: no forwarding
    fp_forward_c = 2'b00;

    // EX hazard (highest priority): Forward from EX/MEM
    if (exmem_fp_reg_write && (exmem_fp_rd == idex_fp_rs3)) begin
      fp_forward_c = 2'b10;
    end
    // MEM hazard: Forward from MEM/WB (only if no EX hazard)
    else if (memwb_fp_reg_write && (memwb_fp_rd == idex_fp_rs3)) begin
      fp_forward_c = 2'b01;
    end
  end

endmodule
