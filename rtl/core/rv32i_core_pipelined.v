// rv32i_core_pipelined.v - 5-Stage Pipelined RV32I Processor Core
// Implements classic RISC pipeline: IF -> ID -> EX -> MEM -> WB
// Includes data forwarding and hazard detection
// Author: RV1 Project
// Date: 2025-10-10

module rv32i_core_pipelined #(
  parameter RESET_VECTOR = 32'h00000000,
  parameter IMEM_SIZE = 4096,
  parameter DMEM_SIZE = 16384,
  parameter MEM_FILE = ""
) (
  input  wire        clk,
  input  wire        reset_n,
  output wire [31:0] pc_out,        // For debugging
  output wire [31:0] instr_out      // For debugging
);

  //==========================================================================
  // Pipeline Control Signals
  //==========================================================================
  wire stall_pc;           // Stall PC (from hazard detection)
  wire stall_ifid;         // Stall IF/ID register
  wire flush_ifid;         // Flush IF/ID register (branch misprediction)
  wire flush_idex;         // Flush ID/EX register (bubble insertion)
  wire [1:0] forward_a;    // Forwarding select for ALU operand A
  wire [1:0] forward_b;    // Forwarding select for ALU operand B

  //==========================================================================
  // IF Stage Signals
  //==========================================================================
  wire [31:0] pc_current;
  wire [31:0] pc_next;
  wire [31:0] pc_plus_4;
  wire [31:0] if_instruction;

  //==========================================================================
  // IF/ID Pipeline Register Outputs
  //==========================================================================
  wire [31:0] ifid_pc;
  wire [31:0] ifid_instruction;
  wire        ifid_valid;

  //==========================================================================
  // ID Stage Signals
  //==========================================================================
  // Decoder outputs
  wire [6:0]  id_opcode;
  wire [4:0]  id_rd, id_rs1, id_rs2;
  wire [2:0]  id_funct3;
  wire [6:0]  id_funct7;
  wire [31:0] id_imm_i, id_imm_s, id_imm_b, id_imm_u, id_imm_j;

  // Control signals
  wire        id_reg_write;
  wire        id_mem_read;
  wire        id_mem_write;
  wire        id_branch;
  wire        id_jump;
  wire [3:0]  id_alu_control;
  wire        id_alu_src;
  wire [1:0]  id_wb_sel;
  wire [2:0]  id_imm_sel;

  // Register file outputs
  wire [31:0] id_rs1_data;
  wire [31:0] id_rs2_data;

  // Immediate selection
  wire [31:0] id_immediate;

  //==========================================================================
  // ID/EX Pipeline Register Outputs
  //==========================================================================
  wire [31:0] idex_pc;
  wire [31:0] idex_rs1_data;
  wire [31:0] idex_rs2_data;
  wire [4:0]  idex_rs1_addr;
  wire [4:0]  idex_rs2_addr;
  wire [4:0]  idex_rd_addr;
  wire [31:0] idex_imm;
  wire [6:0]  idex_opcode;
  wire [2:0]  idex_funct3;
  wire [6:0]  idex_funct7;
  wire [3:0]  idex_alu_control;
  wire        idex_alu_src;
  wire        idex_branch;
  wire        idex_jump;
  wire        idex_mem_read;
  wire        idex_mem_write;
  wire        idex_reg_write;
  wire [1:0]  idex_wb_sel;
  wire        idex_valid;

  //==========================================================================
  // EX Stage Signals
  //==========================================================================
  wire [31:0] ex_alu_operand_a;
  wire [31:0] ex_alu_operand_b;
  wire [31:0] ex_alu_operand_a_forwarded;
  wire [31:0] ex_alu_operand_b_forwarded;
  wire [31:0] ex_alu_result;
  wire        ex_alu_zero;
  wire        ex_alu_lt;
  wire        ex_alu_ltu;
  wire        ex_take_branch;
  wire [31:0] ex_branch_target;
  wire [31:0] ex_jump_target;
  wire [31:0] ex_pc_plus_4;

  //==========================================================================
  // EX/MEM Pipeline Register Outputs
  //==========================================================================
  wire [31:0] exmem_alu_result;
  wire [31:0] exmem_mem_write_data;
  wire [4:0]  exmem_rd_addr;
  wire [31:0] exmem_pc_plus_4;
  wire [2:0]  exmem_funct3;
  wire        exmem_mem_read;
  wire        exmem_mem_write;
  wire        exmem_reg_write;
  wire [1:0]  exmem_wb_sel;

  //==========================================================================
  // MEM Stage Signals
  //==========================================================================
  wire [31:0] mem_read_data;

  //==========================================================================
  // MEM/WB Pipeline Register Outputs
  //==========================================================================
  wire [31:0] memwb_alu_result;
  wire [31:0] memwb_mem_read_data;
  wire [4:0]  memwb_rd_addr;
  wire [31:0] memwb_pc_plus_4;
  wire        memwb_reg_write;
  wire [1:0]  memwb_wb_sel;

  //==========================================================================
  // WB Stage Signals
  //==========================================================================
  wire [31:0] wb_data;

  //==========================================================================
  // Debug outputs
  //==========================================================================
  assign pc_out = pc_current;
  assign instr_out = if_instruction;

  //==========================================================================
  // IF STAGE: Instruction Fetch
  //==========================================================================

  // PC calculation
  assign pc_plus_4 = pc_current + 32'd4;

  // PC selection: branch/jump target or PC+4
  assign pc_next = ex_take_branch ? (idex_jump ? ex_jump_target : ex_branch_target) : pc_plus_4;

  // Branch/jump causes flush
  assign flush_ifid = ex_take_branch;

  // Program Counter
  pc #(
    .RESET_VECTOR(RESET_VECTOR)
  ) pc_inst (
    .clk(clk),
    .reset_n(reset_n),
    .stall(stall_pc),
    .pc_next(pc_next),
    .pc_current(pc_current)
  );

  // Instruction Memory
  instruction_memory #(
    .MEM_SIZE(IMEM_SIZE),
    .MEM_FILE(MEM_FILE)
  ) imem (
    .addr(pc_current),
    .instruction(if_instruction)
  );

  // IF/ID Pipeline Register
  ifid_register ifid_reg (
    .clk(clk),
    .reset_n(reset_n),
    .stall(stall_ifid),
    .flush(flush_ifid),
    .pc_in(pc_current),
    .instruction_in(if_instruction),
    .pc_out(ifid_pc),
    .instruction_out(ifid_instruction),
    .valid_out(ifid_valid)
  );

  //==========================================================================
  // ID STAGE: Instruction Decode
  //==========================================================================

  // Instruction Decoder
  decoder decoder_inst (
    .instruction(ifid_instruction),
    .opcode(id_opcode),
    .rd(id_rd),
    .rs1(id_rs1),
    .rs2(id_rs2),
    .funct3(id_funct3),
    .funct7(id_funct7),
    .imm_i(id_imm_i),
    .imm_s(id_imm_s),
    .imm_b(id_imm_b),
    .imm_u(id_imm_u),
    .imm_j(id_imm_j)
  );

  // Control Unit
  control control_inst (
    .opcode(id_opcode),
    .funct3(id_funct3),
    .funct7(id_funct7),
    .reg_write(id_reg_write),
    .mem_read(id_mem_read),
    .mem_write(id_mem_write),
    .branch(id_branch),
    .jump(id_jump),
    .alu_control(id_alu_control),
    .alu_src(id_alu_src),
    .wb_sel(id_wb_sel),
    .imm_sel(id_imm_sel)
  );

  // Register File
  register_file regfile (
    .clk(clk),
    .reset_n(reset_n),
    .rs1_addr(id_rs1),
    .rs2_addr(id_rs2),
    .rd_addr(memwb_rd_addr),          // Write from WB stage
    .rd_data(wb_data),                // Write data from WB stage
    .rd_wen(memwb_reg_write),         // Write enable from WB stage
    .rs1_data(id_rs1_data),
    .rs2_data(id_rs2_data)
  );

  // Immediate Selection
  assign id_immediate = (id_imm_sel == 3'b000) ? id_imm_i :
                        (id_imm_sel == 3'b001) ? id_imm_s :
                        (id_imm_sel == 3'b010) ? id_imm_b :
                        (id_imm_sel == 3'b011) ? id_imm_u :
                        (id_imm_sel == 3'b100) ? id_imm_j :
                        32'h0;

  // Hazard Detection Unit
  hazard_detection_unit hazard_unit (
    .idex_mem_read(idex_mem_read),
    .idex_rd(idex_rd_addr),
    .ifid_rs1(id_rs1),
    .ifid_rs2(id_rs2),
    .stall_pc(stall_pc),
    .stall_ifid(stall_ifid),
    .bubble_idex(flush_idex)
  );

  // ID/EX Pipeline Register
  idex_register idex_reg (
    .clk(clk),
    .reset_n(reset_n),
    .flush(flush_idex),
    // Data inputs
    .pc_in(ifid_pc),
    .rs1_data_in(id_rs1_data),
    .rs2_data_in(id_rs2_data),
    .rs1_addr_in(id_rs1),
    .rs2_addr_in(id_rs2),
    .rd_addr_in(id_rd),
    .imm_in(id_immediate),
    .opcode_in(id_opcode),
    .funct3_in(id_funct3),
    .funct7_in(id_funct7),
    // Control inputs
    .alu_control_in(id_alu_control),
    .alu_src_in(id_alu_src),
    .branch_in(id_branch),
    .jump_in(id_jump),
    .mem_read_in(id_mem_read),
    .mem_write_in(id_mem_write),
    .reg_write_in(id_reg_write),
    .wb_sel_in(id_wb_sel),
    .valid_in(ifid_valid),
    // Data outputs
    .pc_out(idex_pc),
    .rs1_data_out(idex_rs1_data),
    .rs2_data_out(idex_rs2_data),
    .rs1_addr_out(idex_rs1_addr),
    .rs2_addr_out(idex_rs2_addr),
    .rd_addr_out(idex_rd_addr),
    .imm_out(idex_imm),
    .opcode_out(idex_opcode),
    .funct3_out(idex_funct3),
    .funct7_out(idex_funct7),
    // Control outputs
    .alu_control_out(idex_alu_control),
    .alu_src_out(idex_alu_src),
    .branch_out(idex_branch),
    .jump_out(idex_jump),
    .mem_read_out(idex_mem_read),
    .mem_write_out(idex_mem_write),
    .reg_write_out(idex_reg_write),
    .wb_sel_out(idex_wb_sel),
    .valid_out(idex_valid)
  );

  //==========================================================================
  // EX STAGE: Execute
  //==========================================================================

  assign ex_pc_plus_4 = idex_pc + 32'd4;

  // Forwarding Unit
  forwarding_unit forward_unit (
    .idex_rs1(idex_rs1_addr),
    .idex_rs2(idex_rs2_addr),
    .exmem_rd(exmem_rd_addr),
    .exmem_reg_write(exmem_reg_write),
    .memwb_rd(memwb_rd_addr),
    .memwb_reg_write(memwb_reg_write),
    .forward_a(forward_a),
    .forward_b(forward_b)
  );

  // ALU Operand A selection (with forwarding)
  assign ex_alu_operand_a = (idex_opcode == 7'b0010111) ? idex_pc : idex_rs1_data;

  assign ex_alu_operand_a_forwarded = (forward_a == 2'b10) ? exmem_alu_result :    // EX hazard
                                      (forward_a == 2'b01) ? wb_data :              // MEM hazard
                                      ex_alu_operand_a;                              // No hazard

  // ALU Operand B selection (with forwarding)
  wire [31:0] ex_rs2_data_forwarded;
  assign ex_rs2_data_forwarded = (forward_b == 2'b10) ? exmem_alu_result :         // EX hazard
                                  (forward_b == 2'b01) ? wb_data :                  // MEM hazard
                                  idex_rs2_data;                                     // No hazard

  assign ex_alu_operand_b = idex_alu_src ? idex_imm : ex_rs2_data_forwarded;

  // ALU
  alu alu_inst (
    .operand_a(ex_alu_operand_a_forwarded),
    .operand_b(ex_alu_operand_b),
    .alu_control(idex_alu_control),
    .result(ex_alu_result),
    .zero(ex_alu_zero),
    .less_than(ex_alu_lt),
    .less_than_unsigned(ex_alu_ltu)
  );

  // Branch Unit
  branch_unit branch_inst (
    .rs1_data(ex_alu_operand_a_forwarded),
    .rs2_data(ex_rs2_data_forwarded),
    .funct3(idex_funct3),
    .branch(idex_branch),
    .jump(idex_jump),
    .take_branch(ex_take_branch)
  );

  // Branch/Jump Target Calculation
  assign ex_branch_target = idex_pc + idex_imm;

  // JALR uses rs1 + imm, JAL uses PC + imm
  assign ex_jump_target = (idex_opcode == 7'b1100111) ?
                          (ex_alu_operand_a_forwarded + idex_imm) & 32'hFFFFFFFE :
                          idex_pc + idex_imm;

  // EX/MEM Pipeline Register
  exmem_register exmem_reg (
    .clk(clk),
    .reset_n(reset_n),
    .alu_result_in(ex_alu_result),
    .mem_write_data_in(ex_rs2_data_forwarded),
    .rd_addr_in(idex_rd_addr),
    .pc_plus_4_in(ex_pc_plus_4),
    .funct3_in(idex_funct3),
    .mem_read_in(idex_mem_read),
    .mem_write_in(idex_mem_write),
    .reg_write_in(idex_reg_write),
    .wb_sel_in(idex_wb_sel),
    .alu_result_out(exmem_alu_result),
    .mem_write_data_out(exmem_mem_write_data),
    .rd_addr_out(exmem_rd_addr),
    .pc_plus_4_out(exmem_pc_plus_4),
    .funct3_out(exmem_funct3),
    .mem_read_out(exmem_mem_read),
    .mem_write_out(exmem_mem_write),
    .reg_write_out(exmem_reg_write),
    .wb_sel_out(exmem_wb_sel)
  );

  //==========================================================================
  // MEM STAGE: Memory Access
  //==========================================================================

  // Data Memory
  data_memory #(
    .MEM_SIZE(DMEM_SIZE)
  ) dmem (
    .clk(clk),
    .addr(exmem_alu_result),
    .write_data(exmem_mem_write_data),
    .mem_read(exmem_mem_read),
    .mem_write(exmem_mem_write),
    .funct3(exmem_funct3),
    .read_data(mem_read_data)
  );

  // MEM/WB Pipeline Register
  memwb_register memwb_reg (
    .clk(clk),
    .reset_n(reset_n),
    .alu_result_in(exmem_alu_result),
    .mem_read_data_in(mem_read_data),
    .rd_addr_in(exmem_rd_addr),
    .pc_plus_4_in(exmem_pc_plus_4),
    .reg_write_in(exmem_reg_write),
    .wb_sel_in(exmem_wb_sel),
    .alu_result_out(memwb_alu_result),
    .mem_read_data_out(memwb_mem_read_data),
    .rd_addr_out(memwb_rd_addr),
    .pc_plus_4_out(memwb_pc_plus_4),
    .reg_write_out(memwb_reg_write),
    .wb_sel_out(memwb_wb_sel)
  );

  //==========================================================================
  // WB STAGE: Write Back
  //==========================================================================

  // Write-Back Data Selection
  assign wb_data = (memwb_wb_sel == 2'b00) ? memwb_alu_result :      // ALU result
                   (memwb_wb_sel == 2'b01) ? memwb_mem_read_data :   // Memory data
                   (memwb_wb_sel == 2'b10) ? memwb_pc_plus_4 :       // PC + 4 (JAL/JALR)
                   32'h0;

endmodule
