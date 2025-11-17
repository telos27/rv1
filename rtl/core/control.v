// control.v - RISC-V 主控制单元
// 根据操作码和功能字段生成控制信号
// 支持 RV32/RV64 参数化
// 作者: RV1 Project
// 日期: 2025-10-09
// 更新: 2025-10-10 - 增加 CSR 和陷入支持, RV64 支持

`include "config/rv_config.vh"

module control #(
  parameter XLEN = `XLEN
) (
  input  wire [6:0] opcode,      // 指令操作码
  input  wire [2:0] funct3,      // funct3 字段
  input  wire [6:0] funct7,      // funct7 字段

  // 特殊指令译码输入
  input  wire       is_csr,      // CSR 指令
  input  wire       is_ecall,    // ECALL 指令
  input  wire       is_ebreak,   // EBREAK 指令
  input  wire       is_mret,     // MRET 指令
  input  wire       is_sret,     // SRET 指令
  input  wire       is_sfence_vma, // SFENCE.VMA 指令
  input  wire       is_mul_div,  // M 扩展指令
  input  wire [3:0] mul_div_op,  // M 扩展操作 (来自译码器)
  input  wire       is_word_op,  // RV64M: W 后缀指令
  input  wire       is_atomic,   // A 扩展指令
  input  wire [4:0] funct5,      // 原子指令 funct5 字段
  input  wire       is_fp,       // F/D 扩展指令
  input  wire       is_fp_load,  // FLW/FLD
  input  wire       is_fp_store, // FSW/FSD
  input  wire       is_fp_op,    // 浮点计算指令
  input  wire       is_fp_fma,   // 浮点 FMA 指令

  // FPU 状态输入 (来自 MSTATUS.FS)
  input  wire [1:0] mstatus_fs,  // FPU 状态: 00=关闭, 01=初始, 10=干净, 11=脏

  // 标准控制输出
  output reg        reg_write,   // 通用寄存器写使能
  output reg        mem_read,    // 访存读使能
  output reg        mem_write,   // 访存写使能
  output reg        branch,      // 分支指令
  output reg        jump,        // 跳转指令
  output reg  [3:0] alu_control, // ALU 操作
  output reg        alu_src,     // ALU 第二操作数来源: 0=rs2, 1=立即数
  output reg  [2:0] wb_sel,      // 写回选择: 000=ALU, 001=MEM, 010=PC+4, 011=CSR, 100=M 单元
  output reg  [2:0] imm_sel,     // 立即数格式选择

  // CSR 控制输出
  output reg        csr_we,      // CSR 写使能
  output reg        csr_src,     // CSR 写源: 0=rs1, 1=uimm

  // M 扩展控制输出
  output reg        mul_div_en,  // M 单元使能
  output reg [3:0]  mul_div_op_out, // M 单元操作 (透传)
  output reg        is_word_op_out,  // RV64M: W 后缀 (透传)

  // A 扩展控制输出
  output reg        atomic_en,   // 原子单元使能
  output reg [4:0]  atomic_funct5, // 原子操作 (funct5)

  // F/D 扩展控制输出
  output reg        fp_reg_write,    // 浮点寄存器写使能
  output reg        int_reg_write_fp, // 整数寄存器写使能 (FMV.X.W, 比较等)
  output reg        fp_mem_op,       // 浮点访存操作
  output reg        fp_alu_en,       // 浮点 ALU 使能
  output reg [4:0]  fp_alu_op,       // 浮点 ALU 操作
  output reg        fp_use_dynamic_rm, // 使用 fcsr 中的动态舍入模式

  // 异常/陷入输出
  output reg        illegal_inst // 非法指令检测
);

  // 操作码定义 (RV32I)
  localparam OP_LUI    = 7'b0110111;
  localparam OP_AUIPC  = 7'b0010111;
  localparam OP_JAL    = 7'b1101111;
  localparam OP_JALR   = 7'b1100111;
  localparam OP_BRANCH = 7'b1100011;
  localparam OP_LOAD   = 7'b0000011;
  localparam OP_STORE  = 7'b0100011;
  localparam OP_IMM    = 7'b0010011;
  localparam OP_OP     = 7'b0110011;
  localparam OP_FENCE  = 7'b0001111;
  localparam OP_SYSTEM = 7'b1110011;

  // RV64I 专用操作码
  localparam OP_IMM_32 = 7'b0011011;  // ADDIW, SLLIW, SRLIW, SRAIW
  localparam OP_OP_32  = 7'b0111011;  // ADDW, SUBW, SLLW, SRLW, SRAW

  // A 扩展操作码
  localparam OP_AMO    = 7'b0101111;  // 原子操作 (LR, SC, AMO)

  // F/D 扩展操作码
  localparam OP_LOAD_FP  = 7'b0000111;  // FLW, FLD
  localparam OP_STORE_FP = 7'b0100111;  // FSW, FSD
  localparam OP_MADD     = 7'b1000011;  // FMADD.S/D
  localparam OP_MSUB     = 7'b1000111;  // FMSUB.S/D
  localparam OP_NMSUB    = 7'b1001011;  // FNMSUB.S/D
  localparam OP_NMADD    = 7'b1001111;  // FNMADD.S/D
  localparam OP_OP_FP    = 7'b1010011;  // 其他所有浮点操作

  // FP ALU 操作编码
  localparam FP_ADD    = 5'b00000;
  localparam FP_SUB    = 5'b00001;
  localparam FP_MUL    = 5'b00010;
  localparam FP_DIV    = 5'b00011;
  localparam FP_SQRT   = 5'b00100;
  localparam FP_SGNJ   = 5'b00101;
  localparam FP_SGNJN  = 5'b00110;
  localparam FP_SGNJX  = 5'b00111;
  localparam FP_MIN    = 5'b01000;
  localparam FP_MAX    = 5'b01001;
  localparam FP_CVT    = 5'b01010;
  localparam FP_CMP    = 5'b01011;
  localparam FP_CLASS  = 5'b01100;
  localparam FP_FMA    = 5'b01101;
  localparam FP_FMSUB  = 5'b01110;
  localparam FP_FNMSUB = 5'b01111;
  localparam FP_FNMADD = 5'b10000;
  localparam FP_MV_XW  = 5'b10001;  // FMV.X.W
  localparam FP_MV_WX  = 5'b10010;  // FMV.W.X

  // 立即数格式选择
  localparam IMM_I = 3'b000;
  localparam IMM_S = 3'b001;
  localparam IMM_B = 3'b010;
  localparam IMM_U = 3'b011;
  localparam IMM_J = 3'b100;

  // 根据 funct3 和 funct7 生成 ALU 控制
  function [3:0] get_alu_control;
    input [2:0] f3;
    input [6:0] f7;
    input is_reg_op;  // 1 表示 R 型, 0 表示 I 型
    begin
      case (f3)
        3'b000: begin  // ADD/SUB/ADDI
          if (is_reg_op && f7[5])
            get_alu_control = 4'b0001;  // SUB
          else
            get_alu_control = 4'b0000;  // ADD
        end
        3'b001: get_alu_control = 4'b0010;  // SLL/SLLI
        3'b010: get_alu_control = 4'b0011;  // SLT/SLTI
        3'b011: get_alu_control = 4'b0100;  // SLTU/SLTIU
        3'b100: get_alu_control = 4'b0101;  // XOR/XORI
        3'b101: begin  // SRL/SRA/SRLI/SRAI
          if (f7[5])
            get_alu_control = 4'b0111;  // SRA
          else
            get_alu_control = 4'b0110;  // SRL
        end
        3'b110: get_alu_control = 4'b1000;  // OR/ORI
        3'b111: get_alu_control = 4'b1001;  // AND/ANDI
        default: get_alu_control = 4'b0000;
      endcase
    end
  endfunction

  always @(*) begin
    // 默认值
    reg_write = 1'b0;
    mem_read = 1'b0;
    mem_write = 1'b0;
    branch = 1'b0;
    jump = 1'b0;
    alu_control = 4'b0000;
    alu_src = 1'b0;
    wb_sel = 3'b000;
    imm_sel = IMM_I;
    csr_we = 1'b0;
    csr_src = 1'b0;
    mul_div_en = 1'b0;
    mul_div_op_out = 4'b0000;
    is_word_op_out = 1'b0;
    atomic_en = 1'b0;
    atomic_funct5 = 5'b00000;
    fp_reg_write = 1'b0;
    int_reg_write_fp = 1'b0;
    fp_mem_op = 1'b0;
    fp_alu_en = 1'b0;
    fp_alu_op = 5'b00000;
    fp_use_dynamic_rm = 1'b0;
    illegal_inst = 1'b0;

    case (opcode)
      OP_LUI: begin
        // LUI: rd = imm_u
        reg_write = 1'b1;
        alu_src = 1'b1;
        alu_control = 4'b0000;  // 传递 (0 + imm)
        wb_sel = 3'b000;
        imm_sel = IMM_U;
      end

      OP_AUIPC: begin
        // AUIPC: rd = PC + imm_u
        reg_write = 1'b1;
        alu_src = 1'b1;
        alu_control = 4'b0000;  // ADD
        wb_sel = 3'b000;
        imm_sel = IMM_U;
      end

      OP_JAL: begin
        // JAL: rd = PC + 4, PC = PC + imm_j
        reg_write = 1'b1;
        jump = 1'b1;
        wb_sel = 3'b010;  // 写入 PC+4
        imm_sel = IMM_J;
      end

      OP_JALR: begin
        // JALR: rd = PC + 4, PC = rs1 + imm_i
        reg_write = 1'b1;
        jump = 1'b1;
        alu_src = 1'b1;
        alu_control = 4'b0000;  // ADD
        wb_sel = 3'b010;  // 写入 PC+4
        imm_sel = IMM_I;
      end

      OP_BRANCH: begin
        // 分支指令
        branch = 1'b1;
        alu_control = 4'b0001;  // SUB 用于比较
        imm_sel = IMM_B;
      end

      OP_LOAD: begin
        // 读内存指令
        reg_write = 1'b1;
        mem_read = 1'b1;
        alu_src = 1'b1;
        alu_control = 4'b0000;  // ADD (rs1 + offset)
        wb_sel = 3'b001;  // 写入来自内存
        imm_sel = IMM_I;
      end

      OP_STORE: begin
        // 写内存指令
        mem_write = 1'b1;
        alu_src = 1'b1;
        alu_control = 4'b0000;  // ADD (rs1 + offset)
        imm_sel = IMM_S;
      end

      OP_IMM: begin
        // 立即数 ALU 运算
        reg_write = 1'b1;
        alu_src = 1'b1;
        alu_control = get_alu_control(funct3, funct7, 1'b0);
        wb_sel = 3'b000;
        imm_sel = IMM_I;
      end

      OP_OP: begin
        // 寄存器-寄存器 ALU 运算 (或 M 扩展)
        reg_write = 1'b1;
        alu_src = 1'b0;  // 使用 rs2

        if (is_mul_div) begin
          // M 扩展指令
          mul_div_en = 1'b1;          // 使能 M 单元
          mul_div_op_out = mul_div_op; // 传递操作
          is_word_op_out = is_word_op; // 传递字操作标志
          wb_sel = 3'b100;             // 选择 M 单元结果
          alu_control = 4'b0000;       // ALU 不使用，但传递 rs1 和 rs2
        end else begin
          // 标准 ALU 操作
          alu_control = get_alu_control(funct3, funct7, 1'b1);
          wb_sel = 3'b000;
        end
      end

      OP_FENCE: begin
        // FENCE: 在本实现中视为 NOP
        // 真实系统中会刷新缓存/缓冲
      end

      OP_IMM_32: begin
        // RV64I: 32 位立即数运算 (ADDIW, SLLIW, SRLIW, SRAIW)
        // 仅操作低 32 位并符号扩展到 64 位
        if (XLEN == 64) begin
          reg_write = 1'b1;
          alu_src = 1'b1;
          alu_control = get_alu_control(funct3, funct7, 1'b0);
          wb_sel = 3'b000;
          imm_sel = IMM_I;
        end else begin
          // RV32 中非法
          illegal_inst = 1'b1;
        end
      end

      OP_OP_32: begin
        // RV64I: 32 位寄存器运算 (ADDW, SUBW, SLLW, SRLW, SRAW)
        // RV64M: 32 位 M 扩展 (MULW, DIVW, DIVUW, REMW, REMUW)
        // 仅操作低 32 位并符号扩展到 64 位
        if (XLEN == 64) begin
          reg_write = 1'b1;
          alu_src = 1'b0;  // Use rs2

          if (is_mul_div) begin
            // RV64M 字操作
            mul_div_en = 1'b1;          // 使能 M 单元
            mul_div_op_out = mul_div_op; // 传递操作
            is_word_op_out = is_word_op; // 传递字操作标志 (将为 1)
            wb_sel = 3'b100;             // 选择 M 单元结果
            alu_control = 4'b0000;       // ALU 不使用
          end else begin
            // RV64I 字操作
            alu_control = get_alu_control(funct3, funct7, 1'b1);
            wb_sel = 3'b000;
          end
        end else begin
          // RV32 中非法
          illegal_inst = 1'b1;
        end
      end

      OP_AMO: begin
        // A 扩展: 原子指令 (LR, SC, AMO)
        if (is_atomic) begin
          reg_write = 1'b1;          // 原子操作写回到 rd
          atomic_en = 1'b1;          // 使能原子单元
          atomic_funct5 = funct5;    // 传递原子操作类型
          wb_sel = 3'b101;           // 从原子单元写回 (新的 wb_sel 值)
          alu_src = 1'b1;            // 使用立即数 (0) 进行地址计算
          alu_control = 4'b0000;     // ADD (rs1 + 0 = rs1)
          imm_sel = IMM_I;
        end else begin
          illegal_inst = 1'b1;
        end
      end

      OP_LOAD_FP: begin
        // FLW/FLD: 从内存加载浮点数
        // 检查 MSTATUS.FS - 若为 Off(00), 浮点指令非法
        `ifdef DEBUG_FPU
        $display("[CONTROL-FP] Time=%0t OP_LOAD_FP: mstatus_fs=%b is_fp_load=%b", $time, mstatus_fs, is_fp_load);
        `endif
        if (mstatus_fs == 2'b00) begin
          illegal_inst = 1'b1;
          `ifdef DEBUG_FPU
          $display("[CONTROL-FP] *** FP LOAD ILLEGAL - FS=00 ***");
          `endif
        end else if (is_fp_load) begin
          fp_reg_write = 1'b1;        // 写入浮点寄存器文件
          mem_read = 1'b1;            // 从内存读取
          fp_mem_op = 1'b1;           // 浮点内存操作
          alu_src = 1'b1;             // 使用立即数
          alu_control = 4'b0000;      // ADD (rs1 + offset)
          imm_sel = IMM_I;
          wb_sel = 3'b001;            // 从内存写回
        end else begin
          illegal_inst = 1'b1;
        end
      end

      OP_STORE_FP: begin
        // FSW/FSD: 向内存存储浮点数
        // 检查 MSTATUS.FS - 若为 Off(00), 浮点指令非法
        if (mstatus_fs == 2'b00) begin
          illegal_inst = 1'b1;
        end else if (is_fp_store) begin
          mem_write = 1'b1;           // 写入内存
          fp_mem_op = 1'b1;           // 浮点内存操作
          alu_src = 1'b1;             // 使用立即数
          alu_control = 4'b0000;      // ADD (rs1 + offset)
          imm_sel = IMM_S;
        end else begin
          illegal_inst = 1'b1;
        end
      end

      OP_MADD, OP_MSUB, OP_NMSUB, OP_NMADD: begin
        // FMA 指令: FMADD, FMSUB, FNMSUB, FNMADD
        // 检查 MSTATUS.FS - 若为 Off(00), 浮点指令非法
        if (mstatus_fs == 2'b00) begin
          illegal_inst = 1'b1;
        end else if (is_fp_fma) begin
          fp_reg_write = 1'b1;        // 写入浮点寄存器文件
          fp_alu_en = 1'b1;           // 使能浮点 ALU
          fp_use_dynamic_rm = (funct3 == 3'b111);  // 如果 rm=111，使用动态舍入模式

            // 确定 FMA 变体
          case (opcode)
            OP_MADD:  fp_alu_op = FP_FMA;
            OP_MSUB:  fp_alu_op = FP_FMSUB;
            OP_NMSUB: fp_alu_op = FP_FNMSUB;
            OP_NMADD: fp_alu_op = FP_FNMADD;
            default:  fp_alu_op = FP_FMA;
          endcase
        end else begin
          illegal_inst = 1'b1;
        end
      end

      OP_OP_FP: begin
        // 浮点计算指令
        // 检查 MSTATUS.FS - 若为 Off(00), 浮点指令非法
        if (mstatus_fs == 2'b00) begin
          illegal_inst = 1'b1;
        end else if (is_fp_op) begin
            // 基于 funct7 进行译码 (其中包含格式位)
          case (funct7[6:2])
            5'b00000: begin  // FADD.S/D
              fp_reg_write = 1'b1;
              fp_alu_en = 1'b1;
              fp_alu_op = FP_ADD;
              fp_use_dynamic_rm = (funct3 == 3'b111);
            end
            5'b00001: begin  // FSUB.S/D
              fp_reg_write = 1'b1;
              fp_alu_en = 1'b1;
              fp_alu_op = FP_SUB;
              fp_use_dynamic_rm = (funct3 == 3'b111);
            end
            5'b00010: begin  // FMUL.S/D
              fp_reg_write = 1'b1;
              fp_alu_en = 1'b1;
              fp_alu_op = FP_MUL;
              fp_use_dynamic_rm = (funct3 == 3'b111);
            end
            5'b00011: begin  // FDIV.S/D
              fp_reg_write = 1'b1;
              fp_alu_en = 1'b1;
              fp_alu_op = FP_DIV;
              fp_use_dynamic_rm = (funct3 == 3'b111);
            end
            5'b01011: begin  // FSQRT.S/D (rs2 must be 0)
              fp_reg_write = 1'b1;
              fp_alu_en = 1'b1;
              fp_alu_op = FP_SQRT;
              fp_use_dynamic_rm = (funct3 == 3'b111);
            end
            5'b00100: begin  // FSGNJ.S/D, FSGNJN.S/D, FSGNJX.S/D
              fp_reg_write = 1'b1;
              fp_alu_en = 1'b1;
              case (funct3)
                3'b000: fp_alu_op = FP_SGNJ;
                3'b001: fp_alu_op = FP_SGNJN;
                3'b010: fp_alu_op = FP_SGNJX;
                default: illegal_inst = 1'b1;
              endcase
            end
            5'b00101: begin  // FMIN.S/D, FMAX.S/D
              fp_reg_write = 1'b1;
              fp_alu_en = 1'b1;
              fp_alu_op = (funct3[0]) ? FP_MAX : FP_MIN;
            end
            5'b01000, 5'b11000, 5'b11001, 5'b11010, 5'b11011: begin  // FCVT (float↔float: 0x20-0x21, float↔int: 0x60-0x6F)
              // Bug #52 修复: 使用 funct7[6] 而不是 funct7[5] 区分 FP↔FP 与 FP↔INT
              // FCVT.S.D=0x20 (0b0100000), FCVT.D.S=0x21 (0b0100001) 的 funct7[6]=0
              // FCVT.W.S=0x60 (0b1100000), FCVT.S.W=0x68 (0b1101000) 的 funct7[6]=1
                if (funct7[6]) begin  // FCVT 与整数互转（0x60-0x6F 的 bit 6 置位）
                // 根据 RISC-V 规范使用 funct7[3] 区分转换方向
                // funct7[3]=0: 浮点→整数（FCVT.W.S = 0x60），funct7[3]=1: 整数→浮点（FCVT.S.W = 0x68）
                if (funct7[3] == 1'b0) begin
                  // FCVT.W.S/D, FCVT.WU.S/D, FCVT.L.S/D, FCVT.LU.S/D（浮点到整数）
                  reg_write = 1'b1;         // 使能写整数寄存器
                  int_reg_write_fp = 1'b1;  // 标记为 浮点→整数 操作
                  wb_sel = 3'b110;          // 选择 FPU 的整数结果写回
                end else begin
                  // FCVT.S.W, FCVT.S.WU, FCVT.S.L, FCVT.S.LU（整数到浮点）
                  fp_reg_write = 1'b1;  // 写入浮点寄存器
                end
                fp_alu_en = 1'b1;
                fp_alu_op = FP_CVT;
                fp_use_dynamic_rm = (funct3 == 3'b111);
                end else begin
                // FCVT.S.D 或 FCVT.D.S（单精度 ↔ 双精度 转换）
                fp_reg_write = 1'b1;
                fp_alu_en = 1'b1;
                fp_alu_op = FP_CVT;
                fp_use_dynamic_rm = (funct3 == 3'b111);
                end
              end
              5'b10100: begin  // FEQ.S/D, FLT.S/D, FLE.S/D（比较）
                reg_write = 1'b1;         // 使能写整数寄存器
                int_reg_write_fp = 1'b1;  // 标记为 浮点→整数 操作
                fp_alu_en = 1'b1;
                fp_alu_op = FP_CMP;
                wb_sel = 3'b110;          // 选择 FPU 的整数结果写回
              end
              5'b11100: begin  // FMV.X.W/D, FCLASS.S/D
                reg_write = 1'b1;         // 使能写整数寄存器
                int_reg_write_fp = 1'b1;  // 标记为 浮点→整数 操作
                wb_sel = 3'b110;          // 选择 FPU 的整数结果写回
                if (funct3 == 3'b000) begin
                fp_alu_en = 1'b1;       // 为 FMV.X.W 使能 FPU
                fp_alu_op = FP_MV_XW;  // FMV.X.W/D
                end else if (funct3 == 3'b001) begin
                fp_alu_en = 1'b1;
                fp_alu_op = FP_CLASS;  // FCLASS
                end else begin
                illegal_inst = 1'b1;
                end
              end
              5'b11110: begin  // FMV.W.X/D.X
                fp_reg_write = 1'b1;  // 写入浮点寄存器
                fp_alu_en = 1'b1;     // 为 FMV.W.X 使能 FPU
              fp_alu_op = FP_MV_WX;
            end
            default: begin
              illegal_inst = 1'b1;
            end
          endcase
        end else begin
          illegal_inst = 1'b1;
        end
      end

      OP_SYSTEM: begin
        // SYSTEM 指令: CSR, ECALL, EBREAK, MRET
        if (is_csr) begin
          // CSR 指令
          reg_write = 1'b1;        // 将 CSR 读出的值写回 rd
          wb_sel = 3'b011;         // 写回来源为 CSR

          // 决定 CSR 写使能
          // 对于 CSRRW/CSRRWI：总是写（除非 rd=x0，但这在内核中处理）
          // 对于 CSRRS/CSRRC/CSRRSI/CSRRCI：当 rs1/uimm != 0 时写
          // 这里统一始终拉高写使能，实际是否写入在内核中抑制
          csr_we = 1'b1;

          // CSR 写入数据来源：funct3[2]=1 时为立即数(1)，否则为寄存器(0)
          csr_src = funct3[2];

        end else if (is_ecall || is_ebreak) begin
          // ECALL/EBREAK: 触发异常
          // 不写寄存器或内存
          // 异常由核心处理

        end else if (is_mret) begin
          // MRET: 从陷入返回
          // Bug #30: 不要设置 jump=1 - MRET 通过 MEM 阶段的 mret_flush 特殊处理
          // 若设置 jump=1 会导致 EX 阶段使用错误目标
          jump = 1'b0;

        end else if (is_sret) begin
          // SRET: 从监督陷阱返回
          // Bug #30: 不要设置 jump=1 - SRET 通过 MEM 阶段的 sret_flush 特殊处理
          // 若设置 jump=1 会导致 EX 阶段使用错误目标
          jump = 1'b0;

        end else if (is_sfence_vma) begin
          // SFENCE.VMA: TLB fence (flush TLB)
          // 这是控制单元视角的空操作
          // MMU 将根据 rs1/rs2 的值处理 TLB 刷新
          // 不写寄存器，不访问内存，仅发出刷新信号

        end else begin
          // 未知 SYSTEM 指令
          illegal_inst = 1'b1;
        end
      end

      default: begin
        // 非法操作码: 标记为非法指令
        illegal_inst = 1'b1;
      end
    endcase
  end

  // 调试: 跟踪 FCVT 控制信号
  `ifdef DEBUG_FCVT_CONTROL
  always @(*) begin
    if (opcode == 7'b1010011 && is_fp_op && (funct7[6:2] == 5'b01000)) begin
      $display("[CONTROL] FCVT decode: funct7=%b, funct7[5]=%b, fp_reg_write=%b",
               funct7, funct7[5], fp_reg_write);
    end
  end
  `endif

endmodule
