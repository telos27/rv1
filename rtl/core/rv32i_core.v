// rv32i_core.v - 顶层单周期 RV32I 处理器内核
// 将所有组件集成为一个完整处理器
// 作者: RV1 Project
// 日期: 2025-10-09

module rv32i_core #(
  parameter RESET_VECTOR = 32'h00000000,
  parameter IMEM_SIZE = 4096,
  parameter DMEM_SIZE = 4096,
  parameter MEM_FILE = ""
) (
  input  wire        clk,
  input  wire        reset_n,
  output wire [31:0] pc_out,        // 用于调试
  output wire [31:0] instr_out      // 用于调试
);

  // 内部信号
  wire [31:0] pc_current;
  wire [31:0] pc_next;
  wire        pc_stall;

  wire [31:0] instruction;

  // 解码器输出
  wire [6:0]  opcode;
  wire [4:0]  rd, rs1, rs2;
  wire [2:0]  funct3;
  wire [6:0]  funct7;
  wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;

  // 控制信号
  wire        reg_write;
  wire        mem_read;
  wire        mem_write;
  wire        branch;
  wire        jump;
  wire [3:0]  alu_control;
  wire        alu_src;
  wire [1:0]  wb_sel;
  wire [2:0]  imm_sel;

  // 寄存器堆信号
  wire [31:0] rs1_data;
  wire [31:0] rs2_data;
  wire [31:0] rd_data;

  // ALU 信号
  wire [31:0] alu_operand_a;
  wire [31:0] alu_operand_b;
  wire [31:0] alu_result;
  wire        alu_zero;
  wire        alu_lt;
  wire        alu_ltu;

  // 数据存储器信号
  wire [31:0] mem_read_data;

  // 分支/跳转信号
  wire        take_branch;
  wire [31:0] branch_target;
  wire [31:0] jump_target;

  // 立即数选择信号
  wire [31:0] immediate;

  // 调试输出
  assign pc_out = pc_current;
  assign instr_out = instruction;

  // 单周期设计中不使用停顿
  assign pc_stall = 1'b0;

  //==========================================================================
  // 程序计数器 (Program Counter)
  //==========================================================================
  pc #(
    .RESET_VECTOR(RESET_VECTOR)
  ) pc_inst (
    .clk(clk),
    .reset_n(reset_n),
    .stall(pc_stall),
    .pc_next(pc_next),
    .pc_current(pc_current)
  );

  //==========================================================================
  // 指令存储器
  //==========================================================================
  instruction_memory #(
    .MEM_SIZE(IMEM_SIZE),
    .MEM_FILE(MEM_FILE)
  ) imem (
    .addr(pc_current),
    .instruction(instruction)
  );

  //==========================================================================
  // 指令解码器
  //==========================================================================
  decoder decoder_inst (
    .instruction(instruction),
    .opcode(opcode),
    .rd(rd),
    .rs1(rs1),
    .rs2(rs2),
    .funct3(funct3),
    .funct7(funct7),
    .imm_i(imm_i),
    .imm_s(imm_s),
    .imm_b(imm_b),
    .imm_u(imm_u),
    .imm_j(imm_j)
  );

  //==========================================================================
  // 控制单元
  //==========================================================================
  control control_inst (
    .opcode(opcode),
    .funct3(funct3),
    .funct7(funct7),
    .reg_write(reg_write),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .branch(branch),
    .jump(jump),
    .alu_control(alu_control),
    .alu_src(alu_src),
    .wb_sel(wb_sel),
    .imm_sel(imm_sel)
  );

  //==========================================================================
  // 寄存器堆
  //==========================================================================
  register_file regfile (
    .clk(clk),
    .reset_n(reset_n),
    .rs1_addr(rs1),
    .rs2_addr(rs2),
    .rd_addr(rd),
    .rd_data(rd_data),
    .rd_wen(reg_write),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data)
  );

  //==========================================================================
  // 立即数选择
  //==========================================================================
  assign immediate = (imm_sel == 3'b000) ? imm_i :
                     (imm_sel == 3'b001) ? imm_s :
                     (imm_sel == 3'b010) ? imm_b :
                     (imm_sel == 3'b011) ? imm_u :
                     (imm_sel == 3'b100) ? imm_j :
                     32'h0;

  //==========================================================================
  // ALU 操作数选择
  //==========================================================================
  // 对于 AUIPC，operand_a 应为 PC；对于 LUI，operand_a 应为 0；其他情况为 rs1_data
  assign alu_operand_a = (opcode == 7'b0010111) ? pc_current :    // AUIPC
                         (opcode == 7'b0110111) ? 32'h0 :         // LUI
                         rs1_data;                                // 其他指令
  // 操作数 B：立即数或 rs2
  assign alu_operand_b = alu_src ? immediate : rs2_data;

  //==========================================================================
  // 算术逻辑单元 (ALU)
  //==========================================================================
  alu alu_inst (
    .operand_a(alu_operand_a),
    .operand_b(alu_operand_b),
    .alu_control(alu_control),
    .result(alu_result),
    .zero(alu_zero),
    .less_than(alu_lt),
    .less_than_unsigned(alu_ltu)
  );

  //==========================================================================
  // 分支单元
  //==========================================================================
  branch_unit branch_inst (
    .rs1_data(rs1_data),
    .rs2_data(rs2_data),
    .funct3(funct3),
    .branch(branch),
    .jump(jump),
    .take_branch(take_branch)
  );

  //==========================================================================
  // 分支/跳转目标地址计算
  //==========================================================================
  assign branch_target = pc_current + imm_b;

  // JALR 使用 rs1 + imm_i，JAL 使用 PC + imm_j
  assign jump_target = (opcode == 7'b1100111) ? (rs1_data + imm_i) & 32'hFFFFFFFE :
                                                  pc_current + imm_j;

  //==========================================================================
  // 下一条 PC 计算
  //==========================================================================
  assign pc_next = take_branch ? (jump ? jump_target : branch_target) :
                                  pc_current + 32'd4;

  //==========================================================================
  // 数据存储器
  //==========================================================================
  data_memory #(
    .MEM_SIZE(DMEM_SIZE)
  ) dmem (
    .clk(clk),
    .addr(alu_result),
    .write_data(rs2_data),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .funct3(funct3),
    .read_data(mem_read_data)
  );

  //==========================================================================
  // 写回数据选择 (Write-Back)
  //==========================================================================
  assign rd_data = (wb_sel == 2'b00) ? alu_result :      // ALU 结果
                   (wb_sel == 2'b01) ? mem_read_data :   // 数据存储器读出数据
                   (wb_sel == 2'b10) ? pc_current + 4 :  // PC + 4（用于 JAL/JALR）
                   32'h0;

endmodule
