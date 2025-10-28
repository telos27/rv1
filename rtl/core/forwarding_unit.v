// Forwarding Unit
// Detects data hazards and generates forwarding control signals
// Implements comprehensive forwarding for both ID and EX stages:
//   - ID stage: EX→ID, MEM→ID, WB→ID (for early branch resolution)
//   - EX stage: EX→EX, MEM→EX (for ALU operations)

module forwarding_unit (
  // ========================================
  // ID Stage Forwarding (for branches)
  // ========================================
  // Branches resolve in ID stage and need operands from instructions
  // that are still in the pipeline (EX, MEM, or WB stages)

  input  wire [4:0] id_rs1,            // ID stage source register 1 (integer)
  input  wire [4:0] id_rs2,            // ID stage source register 2 (integer)

  output reg  [2:0] id_forward_a,      // ID forward select for rs1
  output reg  [2:0] id_forward_b,      // ID forward select for rs2
  // Encoding: 3'b100=EX, 3'b010=MEM, 3'b001=WB, 3'b000=NONE

  // ========================================
  // EX Stage Forwarding (for ALU ops)
  // ========================================
  // ALU operations in EX stage need operands from MEM or WB stages

  input  wire [4:0] idex_rs1,          // EX stage source register 1 (integer)
  input  wire [4:0] idex_rs2,          // EX stage source register 2 (integer)

  output reg  [1:0] forward_a,         // EX forward select for operand A
  output reg  [1:0] forward_b,         // EX forward select for operand B
  // Encoding: 2'b10=MEM, 2'b01=WB, 2'b00=NONE

  // ========================================
  // Pipeline Stage Write Ports (for comparison)
  // ========================================

  // ID/EX register outputs (instruction currently in EX stage)
  input  wire [4:0] idex_rd,           // EX stage destination register
  input  wire       idex_reg_write,    // EX stage will write to register
  input  wire       idex_is_atomic,    // EX stage has atomic instruction (disable EX→ID forwarding)

  // EX/MEM register outputs (instruction in MEM stage)
  input  wire [4:0] exmem_rd,          // MEM stage destination register
  input  wire       exmem_reg_write,   // MEM stage will write to register
  input  wire       exmem_int_reg_write_fp, // MEM stage FP-to-INT write

  // MEM/WB register outputs (instruction in WB stage)
  input  wire [4:0] memwb_rd,          // WB stage destination register
  input  wire       memwb_reg_write,   // WB stage will write to register
  input  wire       memwb_int_reg_write_fp, // WB stage FP-to-INT write
  input  wire       memwb_valid,       // WB stage instruction is valid (not flushed)

  // ========================================
  // FP Register Forwarding
  // ========================================

  // ID stage FP forwarding (for FP branches/compares)
  input  wire [4:0] id_fp_rs1,         // ID stage FP source register 1
  input  wire [4:0] id_fp_rs2,         // ID stage FP source register 2
  input  wire [4:0] id_fp_rs3,         // ID stage FP source register 3

  output reg  [2:0] id_fp_forward_a,   // ID FP forward select for rs1
  output reg  [2:0] id_fp_forward_b,   // ID FP forward select for rs2
  output reg  [2:0] id_fp_forward_c,   // ID FP forward select for rs3

  // EX stage FP forwarding (for FP ALU ops)
  input  wire [4:0] idex_fp_rs1,       // EX stage FP source register 1
  input  wire [4:0] idex_fp_rs2,       // EX stage FP source register 2
  input  wire [4:0] idex_fp_rs3,       // EX stage FP source register 3 (FMA)

  output reg  [1:0] fp_forward_a,      // EX FP forward select for operand A
  output reg  [1:0] fp_forward_b,      // EX FP forward select for operand B
  output reg  [1:0] fp_forward_c,      // EX FP forward select for operand C

  // FP pipeline stage write ports
  input  wire [4:0] idex_fp_rd,        // EX stage FP destination
  input  wire       idex_fp_reg_write, // EX stage FP write enable
  input  wire [4:0] exmem_fp_rd,       // MEM stage FP destination
  input  wire       exmem_fp_reg_write,// MEM stage FP write enable
  input  wire [4:0] memwb_fp_rd,       // WB stage FP destination
  input  wire       memwb_fp_reg_write // WB stage FP write enable
);

  // ========================================
  // ID Stage Integer Register Forwarding
  // ========================================
  // Priority: EX > MEM > WB > RegFile
  // Used for early branch resolution in ID stage

  always @(*) begin
    // Default: no forwarding
    id_forward_a = 3'b000;

    // Check EX stage (highest priority - most recent instruction)
    // Skip EX forwarding for atomic operations (they take multiple cycles, result not ready)
    if (idex_reg_write && (idex_rd != 5'h0) && (idex_rd == id_rs1) && !idex_is_atomic) begin
      id_forward_a = 3'b100;  // Forward from EX stage
    end
    // Check MEM stage (second priority)
    // Include FP-to-INT writes (FMV.X.W, FCVT.W.S, FP compare, etc.)
    else if ((exmem_reg_write | exmem_int_reg_write_fp) && (exmem_rd != 5'h0) && (exmem_rd == id_rs1)) begin
      id_forward_a = 3'b010;  // Forward from MEM stage
    end
    // Check WB stage (lowest priority - oldest instruction)
    // CRITICAL: Only forward if memwb_valid=1 (prevents forwarding from flushed instructions)
    else if ((memwb_reg_write | memwb_int_reg_write_fp) && (memwb_rd != 5'h0) && (memwb_rd == id_rs1) && memwb_valid) begin
      id_forward_a = 3'b001;  // Forward from WB stage
    end
  end

  always @(*) begin
    // Default: no forwarding
    id_forward_b = 3'b000;

    // Check EX stage (highest priority)
    // Skip EX forwarding for atomic operations (they take multiple cycles, result not ready)
    if (idex_reg_write && (idex_rd != 5'h0) && (idex_rd == id_rs2) && !idex_is_atomic) begin
      id_forward_b = 3'b100;  // Forward from EX stage
    end
    // Check MEM stage (second priority)
    // Include FP-to-INT writes (FMV.X.W, FCVT.W.S, FP compare, etc.)
    else if ((exmem_reg_write | exmem_int_reg_write_fp) && (exmem_rd != 5'h0) && (exmem_rd == id_rs2)) begin
      id_forward_b = 3'b010;  // Forward from MEM stage
    end
    // Check WB stage (lowest priority)
    // CRITICAL: Only forward if memwb_valid=1 (prevents forwarding from flushed instructions)
    else if ((memwb_reg_write | memwb_int_reg_write_fp) && (memwb_rd != 5'h0) && (memwb_rd == id_rs2) && memwb_valid) begin
      id_forward_b = 3'b001;  // Forward from WB stage
    end
  end

  // ========================================
  // EX Stage Integer Register Forwarding
  // ========================================
  // Priority: MEM > WB > RegFile
  // Used for ALU operands in EX stage
  // Note: EX-to-EX forwarding handled by ID-to-EX pipeline register

  always @(*) begin
    // Default: no forwarding
    forward_a = 2'b00;

    // MEM hazard (highest priority): Forward from EX/MEM
    // Condition: EX/MEM.reg_write AND EX/MEM.rd != 0 AND EX/MEM.rd == ID/EX.rs1
    // Include FP-to-INT writes (FMV.X.W, FCVT.W.S, FP compare, etc.)
    if ((exmem_reg_write | exmem_int_reg_write_fp) && (exmem_rd != 5'h0) && (exmem_rd == idex_rs1)) begin
      forward_a = 2'b10;
      `ifdef DEBUG_FORWARD
      $display("[FORWARD_A] @%0t MEM hazard: rs1=x%0d matches exmem_rd=x%0d (fwd=2'b10)", $time, idex_rs1, exmem_rd);
      `endif
    end
    // WB hazard: Forward from MEM/WB (only if no MEM hazard)
    // Condition: MEM/WB.reg_write AND MEM/WB.rd != 0 AND MEM/WB.rd == ID/EX.rs1
    // Include FP-to-INT writes
    // CRITICAL: Only forward if memwb_valid=1 (prevents forwarding from flushed instructions)
    else if ((memwb_reg_write | memwb_int_reg_write_fp) && (memwb_rd != 5'h0) && (memwb_rd == idex_rs1) && memwb_valid) begin
      forward_a = 2'b01;
      `ifdef DEBUG_FORWARD
      $display("[FORWARD_A] @%0t WB hazard: rs1=x%0d matches memwb_rd=x%0d (fwd=2'b01)", $time, idex_rs1, memwb_rd);
      `endif
    end
    `ifdef DEBUG_FORWARD
    else if (idex_rs1 != 5'h0) begin
      $display("[FORWARD_A] @%0t No forward: rs1=x%0d (fwd=2'b00)", $time, idex_rs1);
    end
    `endif
  end

  always @(*) begin
    // Default: no forwarding
    forward_b = 2'b00;

    // MEM hazard (highest priority): Forward from EX/MEM
    // Include FP-to-INT writes (FMV.X.W, FCVT.W.S, FP compare, etc.)
    if ((exmem_reg_write | exmem_int_reg_write_fp) && (exmem_rd != 5'h0) && (exmem_rd == idex_rs2)) begin
      forward_b = 2'b10;
      `ifdef DEBUG_FORWARD
      $display("[FORWARD_B] @%0t MEM hazard: rs2=x%0d matches exmem_rd=x%0d (fwd=2'b10)", $time, idex_rs2, exmem_rd);
      `endif
    end
    // WB hazard: Forward from MEM/WB
    // Include FP-to-INT writes
    // CRITICAL: Only forward if memwb_valid=1 (prevents forwarding from flushed instructions)
    else if ((memwb_reg_write | memwb_int_reg_write_fp) && (memwb_rd != 5'h0) && (memwb_rd == idex_rs2) && memwb_valid) begin
      forward_b = 2'b01;
      `ifdef DEBUG_FORWARD
      $display("[FORWARD_B] @%0t WB hazard: rs2=x%0d matches memwb_rd=x%0d (fwd=2'b01)", $time, idex_rs2, memwb_rd);
      `endif
    end
    `ifdef DEBUG_FORWARD
    else if (idex_rs2 != 5'h0) begin
      $display("[FORWARD_B] @%0t No forward: rs2=x%0d (fwd=2'b00)", $time, idex_rs2);
    end
    `endif
  end

  // ========================================
  // ID Stage FP Register Forwarding
  // ========================================
  // Priority: EX > MEM > WB > FP RegFile
  // Note: FP registers don't have a hardwired-zero register like x0

  always @(*) begin
    // Default: no forwarding
    id_fp_forward_a = 3'b000;

    // Check EX stage (highest priority)
    if (idex_fp_reg_write && (idex_fp_rd == id_fp_rs1)) begin
      id_fp_forward_a = 3'b100;  // Forward from EX stage
    end
    // Check MEM stage (second priority)
    else if (exmem_fp_reg_write && (exmem_fp_rd == id_fp_rs1)) begin
      id_fp_forward_a = 3'b010;  // Forward from MEM stage
    end
    // Check WB stage (lowest priority)
    // CRITICAL: Only forward if memwb_valid=1 (prevents forwarding from flushed instructions)
    else if (memwb_fp_reg_write && (memwb_fp_rd == id_fp_rs1) && memwb_valid) begin
      id_fp_forward_a = 3'b001;  // Forward from WB stage
    end
  end

  always @(*) begin
    // Default: no forwarding
    id_fp_forward_b = 3'b000;

    // Check EX stage (highest priority)
    if (idex_fp_reg_write && (idex_fp_rd == id_fp_rs2)) begin
      id_fp_forward_b = 3'b100;  // Forward from EX stage
    end
    // Check MEM stage (second priority)
    else if (exmem_fp_reg_write && (exmem_fp_rd == id_fp_rs2)) begin
      id_fp_forward_b = 3'b010;  // Forward from MEM stage
    end
    // Check WB stage (lowest priority)
    // CRITICAL: Only forward if memwb_valid=1 (prevents forwarding from flushed instructions)
    else if (memwb_fp_reg_write && (memwb_fp_rd == id_fp_rs2) && memwb_valid) begin
      id_fp_forward_b = 3'b001;  // Forward from WB stage
    end
  end

  always @(*) begin
    // Default: no forwarding
    id_fp_forward_c = 3'b000;

    // Check EX stage (highest priority)
    if (idex_fp_reg_write && (idex_fp_rd == id_fp_rs3)) begin
      id_fp_forward_c = 3'b100;  // Forward from EX stage
    end
    // Check MEM stage (second priority)
    else if (exmem_fp_reg_write && (exmem_fp_rd == id_fp_rs3)) begin
      id_fp_forward_c = 3'b010;  // Forward from MEM stage
    end
    // Check WB stage (lowest priority)
    // CRITICAL: Only forward if memwb_valid=1 (prevents forwarding from flushed instructions)
    else if (memwb_fp_reg_write && (memwb_fp_rd == id_fp_rs3) && memwb_valid) begin
      id_fp_forward_c = 3'b001;  // Forward from WB stage
    end
  end

  // ========================================
  // EX Stage FP Register Forwarding
  // ========================================
  // Priority: MEM > WB > FP RegFile
  // Same logic as integer forwarding, but for FP register file

  always @(*) begin
    // Default: no forwarding
    fp_forward_a = 2'b00;

    // MEM hazard (highest priority): Forward from EX/MEM
    if (exmem_fp_reg_write && (exmem_fp_rd == idex_fp_rs1)) begin
      fp_forward_a = 2'b10;
    end
    // WB hazard: Forward from MEM/WB (only if no MEM hazard)
    // CRITICAL: Only forward if memwb_valid=1 (prevents forwarding from flushed instructions)
    else if (memwb_fp_reg_write && (memwb_fp_rd == idex_fp_rs1) && memwb_valid) begin
      fp_forward_a = 2'b01;
    end
  end

  always @(*) begin
    // Default: no forwarding
    fp_forward_b = 2'b00;

    // MEM hazard (highest priority): Forward from EX/MEM
    if (exmem_fp_reg_write && (exmem_fp_rd == idex_fp_rs2)) begin
      fp_forward_b = 2'b10;
    end
    // WB hazard: Forward from MEM/WB
    // CRITICAL: Only forward if memwb_valid=1 (prevents forwarding from flushed instructions)
    else if (memwb_fp_reg_write && (memwb_fp_rd == idex_fp_rs2) && memwb_valid) begin
      fp_forward_b = 2'b01;
    end
  end

  always @(*) begin
    // Default: no forwarding
    fp_forward_c = 2'b00;

    // MEM hazard (highest priority): Forward from EX/MEM
    if (exmem_fp_reg_write && (exmem_fp_rd == idex_fp_rs3)) begin
      fp_forward_c = 2'b10;
    end
    // WB hazard: Forward from MEM/WB
    // CRITICAL: Only forward if memwb_valid=1 (prevents forwarding from flushed instructions)
    else if (memwb_fp_reg_write && (memwb_fp_rd == idex_fp_rs3) && memwb_valid) begin
      fp_forward_c = 2'b01;
    end
  end

endmodule
