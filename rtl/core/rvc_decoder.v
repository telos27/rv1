// RVC 解码器 - RISC-V 压缩指令解压器
// 将 16 位压缩指令转换为 32 位标准指令
//
// 本模块实现了 RISC-V C（Compressed，压缩）扩展的解码逻辑。
// 它接收一条 16 位压缩指令，并将其展开为等价的 32 位指令，供后续流水线执行。
//
// 主要特性：
// - 支持 RV32C 和 RV64C
// - 支持所有象限（Q0、Q1、Q2）
// - 组合逻辑实现（单周期解压）
// - 非法指令检测

`include "config/rv_config.vh"

module rvc_decoder #(
  parameter XLEN = `XLEN
) (
  input  wire [15:0] compressed_instr,     // 16 位压缩指令
  input  wire        is_rv64,              // 1 = RV64 模式, 0 = RV32 模式
  output reg  [31:0] decompressed_instr,   // 32 位展开指令
  output reg         illegal_instr,        // 非法压缩指令标志
  output wire        is_compressed_out     // 压缩检测的直通信号
);

  // 检测指令是否为压缩指令（opcode != 11）
  wire [1:0] opcode = compressed_instr[1:0];
  assign is_compressed_out = (opcode != 2'b11);

  // 提取公共字段
  wire [2:0] funct3 = compressed_instr[15:13];
  wire [1:0] funct2 = compressed_instr[6:5];

  // 寄存器字段
  wire [4:0] rd     = compressed_instr[11:7];
  wire [4:0] rs1    = compressed_instr[11:7];
  wire [4:0] rs2    = compressed_instr[6:2];

  // 压缩寄存器字段（3 位 -> 映射到 x8-x15）
  wire [2:0] rd_p   = compressed_instr[4:2];
  wire [2:0] rs1_p  = compressed_instr[9:7];
  wire [2:0] rs2_p  = compressed_instr[4:2];

  // 展开后的压缩寄存器（加 8 得到 x8-x15）
  wire [4:0] rd_exp  = {2'b01, rd_p};
  wire [4:0] rs1_exp = {2'b01, rs1_p};
  wire [4:0] rs2_exp = {2'b01, rs2_p};

  // 特殊寄存器
  wire [4:0] x0 = 5'd0;   // 零寄存器
  wire [4:0] x1 = 5'd1;   // 返回地址
  wire [4:0] x2 = 5'd2;   // 栈指针

  // RISC-V 基础指令操作码
  localparam OP_IMM    = 7'b0010011;
  localparam OP        = 7'b0110011;
  localparam OP_IMM_32 = 7'b0011011;
  localparam OP_32     = 7'b0111011;
  localparam LUI       = 7'b0110111;
  localparam AUIPC     = 7'b0010111;
  localparam JAL       = 7'b1101111;
  localparam JALR      = 7'b1100111;
  localparam BRANCH    = 7'b1100011;
  localparam LOAD      = 7'b0000011;
  localparam STORE     = 7'b0100011;
  localparam SYSTEM    = 7'b1110011;
  localparam LOAD_FP   = 7'b0000111;  // FLW, FLD
  localparam STORE_FP  = 7'b0100111;  // FSW, FSD

  // funct3 编码
  localparam F3_ADD  = 3'b000;
  localparam F3_SLL  = 3'b001;
  localparam F3_SLT  = 3'b010;
  localparam F3_SLTU = 3'b011;
  localparam F3_XOR  = 3'b100;
  localparam F3_SR   = 3'b101;
  localparam F3_OR   = 3'b110;
  localparam F3_AND  = 3'b111;

  localparam F3_BEQ  = 3'b000;
  localparam F3_BNE  = 3'b001;

  localparam F3_LW   = 3'b010;
  localparam F3_LD   = 3'b011;
  localparam F3_SW   = 3'b010;
  localparam F3_SD   = 3'b011;
  localparam F3_FLW  = 3'b010;  // 单精度浮点加载
  localparam F3_FLD  = 3'b011;  // 双精度浮点加载
  localparam F3_FSW  = 3'b010;  // 单精度浮点存储
  localparam F3_FSD  = 3'b011;  // 双精度浮点存储

  // 立即数提取函数
  // 注意：立即数在压缩格式中被打乱，以提高硬件效率

  // C.ADDI4SPN: nzuimm[9:2]
  // 格式: 000 nzuimm[5:4|9:6|2|3] rd' 00
  // inst[12:11] = nzuimm[5:4], inst[10:7] = nzuimm[9:6], inst[6] = nzuimm[2], inst[5] = nzuimm[3]
  // 重新组装为: nzuimm = {nzuimm[9:6], nzuimm[5:4], nzuimm[3], nzuimm[2], 2'b00}
  wire [9:0] imm_addi4spn = {compressed_instr[10:7], compressed_instr[12:11],
                              compressed_instr[5], compressed_instr[6], 2'b00};

  // C.LW: offset[6:2]
  // 格式: 010 offset[5:3] rs1' offset[2|6] rd' 00
  // inst[12:10] = offset[5:3], inst[6] = offset[2], inst[5] = offset[6]
  // 重新组装为: {offset[6], offset[5:3], offset[2], 2'b00}
  wire [6:0] imm_lw = {compressed_instr[5], compressed_instr[12:10],
                        compressed_instr[6], 2'b00};

  // C.LD: offset[7:3] (RV64)
  wire [7:0] imm_ld = {2'b0, compressed_instr[6:5], compressed_instr[12:10], 3'b0};

  // C.LWSP: offset[7:2]
  // 格式: imm[5] 在位 12，中 imm[4:2|7:6] 在位 [6:2]
  // 位 [6:4] = uimm[4:2]，位 [3:2] = uimm[7:6]，位 [12] = uimm[5]
  wire [7:0] imm_lwsp = {compressed_instr[3:2], compressed_instr[12],
                          compressed_instr[6:4], 2'b00};

  // C.LDSP: offset[8:3] (RV64)
  // 位 [6:5] = uimm[4:3]，位 [4:2] = uimm[8:6]，位 [12] = uimm[5]
  wire [8:0] imm_ldsp = {compressed_instr[4:2], compressed_instr[12],
                          compressed_instr[6:5], 3'b0};

  // C.SWSP: offset[7:2]
  // 格式: 110 offset[5:2|7:6] rs2 10
  // inst[12:9] = offset[5:2]，inst[8:7] = offset[7:6]
  // 存储格式需要: imm[11:5] | rs2 | rs1 | 010 | imm[4:0] | 0100011
  // offset[7:2] 需要放在 imm[7:2]，其中 imm[1:0] = 00
  // 重新组装为: {offset[7:6], offset[5:2], 2'b00}
  wire [7:0] imm_swsp = {compressed_instr[8:7], compressed_instr[12:9], 2'b00};

  // C.SDSP: offset[8:3] (RV64)
  // 格式: 111 offset[5:3|8:6] rs2 10
  // inst[12:10] = offset[5:3]，inst[9:7] = offset[8:6]
  // 存储格式需要: imm[11:5] | rs2 | rs1 | 011 | imm[4:0] | 0100011
  // offset[8:3] 需要放在 imm[8:3]，其中 imm[2:0] = 000
  // 重新组装为: {offset[8:6], offset[5:3], 3'b000}
  wire [8:0] imm_sdsp = {compressed_instr[9:7], compressed_instr[12:10], 3'b000};

  // C.ADDI/C.LI: imm[5:0]
  wire [11:0] imm_addi = {{6{compressed_instr[12]}}, compressed_instr[12],
                           compressed_instr[6:2]};

  // C.ADDI16SP: nzimm[9:4]
  // 格式: 011 nzimm[9] 00010 nzimm[4|6|8:7|5] 01
  // inst[12] = nzimm[9], inst[6] = nzimm[4], inst[5] = nzimm[6],
  // inst[4:3] = nzimm[8:7], inst[2] = nzimm[5]
  // 重新组装为: {nzimm[9], nzimm[8:7], nzimm[6], nzimm[5], nzimm[4], 4'b0000}
  // = {inst[12], inst[4:3], inst[5], inst[2], inst[6], 4'b0000}
  wire [11:0] imm_addi16sp = {{3{compressed_instr[12]}}, compressed_instr[12],
                               compressed_instr[4:3], compressed_instr[5],
                               compressed_instr[2], compressed_instr[6], 4'b0000};

  // C.LUI: nzimm[17:12]
  wire [31:0] imm_lui = {{14{compressed_instr[12]}}, compressed_instr[12],
                          compressed_instr[6:2], 12'b0};

  // C.ANDI: imm[5:0]
  wire [11:0] imm_andi = {{6{compressed_instr[12]}}, compressed_instr[12],
                           compressed_instr[6:2]};

  // Shift amount (shamt)
  wire [5:0] shamt_32 = {1'b0, compressed_instr[12], compressed_instr[6:2]};
  wire [6:0] shamt_64 = {compressed_instr[12], compressed_instr[6:2]};
  wire [6:0] shamt = is_rv64 ? shamt_64 : {1'b0, shamt_32};

  // C.J/C.JAL: offset[11:1]
  // 格式: 101 offset[11|4|9:8|10|6|7|3:1|5] 01
  // inst[12] = offset[11], inst[11] = offset[4], inst[10:9] = offset[9:8],
  // inst[8] = offset[10], inst[7] = offset[6], inst[6] = offset[7],
  // inst[5:3] = offset[3:1], inst[2] = offset[5]
  // JAL 格式需要: imm[20|10:1|11|19:12]
  // 重新组装为: {offset[11], offset[10], offset[9:8], offset[7], offset[6], offset[5], offset[4], offset[3:1], 1'b0}
  wire [20:0] imm_j = {{9{compressed_instr[12]}}, compressed_instr[12],
                        compressed_instr[8], compressed_instr[10:9],
                        compressed_instr[6], compressed_instr[7],
                        compressed_instr[2], compressed_instr[11],
                        compressed_instr[5:3], 1'b0};

  // C.BEQZ/C.BNEZ: offset[8:1]
  // 格式: 110/111 offset[8|4:3] rs1' offset[7:6|2:1|5] 01
  // inst[12] = offset[8], inst[11:10] = offset[4:3], inst[6:5] = offset[7:6],
  // inst[4:3] = offset[2:1], inst[2] = offset[5]
  // Branch 格式需要: imm[12|10:5|4:1|11]
  // 重新组装为: {offset[8], offset[7:6], offset[5], offset[4:3], offset[2:1], 1'b0}
  // 对于分支编码: {imm[12], imm[10:5], imm[4:1], imm[11]}
  // offset[12:1] maps to imm[12:1], so imm[11] = offset[11]
  wire [12:0] imm_b = {{4{compressed_instr[12]}}, compressed_instr[12],
                        compressed_instr[6:5], compressed_instr[2],
                        compressed_instr[11:10], compressed_instr[4:3], 1'b0};

  // 解压缩逻辑
  always @(*) begin
    illegal_instr = 1'b0;
    decompressed_instr = 32'h00000013;  // 默认: ADDI x0, x0, 0 (NOP)

    case (opcode)
      // ================================================================
      // 象限 0 (op = 00)
      // ================================================================
      2'b00: begin
        case (funct3)
          3'b000: begin  // C.ADDI4SPN
            if (imm_addi4spn == 10'b0) begin
              illegal_instr = 1'b1;  // nzuimm must be non-zero
            end else begin
              // ADDI rd', x2, nzuimm (imm_addi4spn already includes scaling)
              decompressed_instr = {2'b0, imm_addi4spn[9:0], x2, F3_ADD, rd_exp, OP_IMM};
            end
          end

          3'b010: begin  // C.LW
            // LW rd', offset(rs1')
            decompressed_instr = {5'b0, imm_lw[6:0], rs1_exp, F3_LW, rd_exp, LOAD};
          end

          3'b011: begin  // C.LD (RV64) / C.FLW (RV32+F)
            if (is_rv64) begin
              // LD rd', offset(rs1')
              decompressed_instr = {4'b0, imm_ld[7:0], rs1_exp, F3_LD, rd_exp, LOAD};
            end else begin
              // C.FLW 未实现 (需要 F 扩展)
              illegal_instr = 1'b1;
            end
          end

          3'b110: begin  // C.SW
            // SW rs2', offset(rs1')
            // 使用与 C.LW 相同的偏移编码
            // 存储格式: imm[11:5] | rs2 | rs1 | 010 | imm[4:0] | 0100011
            decompressed_instr = {5'b0, imm_lw[6:5], rs2_exp, rs1_exp, F3_SW,
                                   imm_lw[4:0], STORE};
          end

          3'b111: begin  // C.SD (RV64) / C.FSW (RV32+F)
            if (is_rv64) begin
              // SD rs2', offset(rs1')
              // 使用与 C.LD 相同的偏移编码
              // S-type: imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
              decompressed_instr = {4'b0, imm_ld[7:5], rs2_exp, rs1_exp, F3_SD,
                                     imm_ld[4:0], STORE};
            end else begin
              // C.FSW 未实现 (需要 F 扩展)
              illegal_instr = 1'b1;
            end
          end

          default: illegal_instr = 1'b1;
        endcase
      end

      // ================================================================
      // 象限 1 (op = 01)
      // ================================================================
      2'b01: begin
        case (funct3)
          3'b000: begin  // C.NOP / C.ADDI
            if (rd == x0 && imm_addi == 12'b0) begin
              // C.NOP (ADDI x0, x0, 0)
              decompressed_instr = {12'b0, x0, F3_ADD, x0, OP_IMM};
            end else if (rd != x0) begin
              // C.ADDI: ADDI rd, rd, imm
              decompressed_instr = {imm_addi, rd, F3_ADD, rd, OP_IMM};
            end else begin
              // 保留 (rd=x0, imm!=0)
              illegal_instr = 1'b1;
            end
          end

          3'b001: begin  // C.JAL (RV32) / C.ADDIW (RV64)
            if (is_rv64) begin
              // C.ADDIW: ADDIW rd, rd, imm
              if (rd != x0) begin
                decompressed_instr = {imm_addi, rd, F3_ADD, rd, OP_IMM_32};
              end else begin
                illegal_instr = 1'b1;  // rd 必须非零
              end
            end else begin
              // C.JAL: JAL x1, offset
              decompressed_instr = {imm_j[20], imm_j[10:1], imm_j[11],
                                     imm_j[19:12], x1, JAL};
            end
          end

          3'b010: begin  // C.LI
            if (rd != x0) begin
              // ADDI rd, x0, imm
              decompressed_instr = {imm_addi, x0, F3_ADD, rd, OP_IMM};
            end else begin
              // Hint (rd=x0)
              decompressed_instr = {imm_addi, x0, F3_ADD, x0, OP_IMM};
            end
          end

          3'b011: begin  // C.ADDI16SP / C.LUI
            if (rd == x2) begin
              // C.ADDI16SP: ADDI x2, x2, nzimm
              if (imm_addi16sp == 12'b0) begin
                illegal_instr = 1'b1;  // nzimm 必须非零
              end else begin
                decompressed_instr = {imm_addi16sp, x2, F3_ADD, x2, OP_IMM};
              end
            end else if (rd != x0) begin
              // C.LUI: LUI rd, nzimm
              if (imm_lui == 32'b0) begin
                illegal_instr = 1'b1;  // nzimm 必须非零
              end else begin
                decompressed_instr = {imm_lui[31:12], rd, LUI};
              end
            end else begin
              illegal_instr = 1'b1;  // 保留
            end
          end

          3'b100: begin  // 算术/移位操作
            case (compressed_instr[11:10])
              2'b00: begin  // C.SRLI
                if (shamt[6] && !is_rv64) begin
                  illegal_instr = 1'b1;  // shamt[5] 在 RV32 中必须为 0
                end else begin
                  // SRLI rd', rd', shamt (rd' is at bits [9:7])
                  decompressed_instr = {1'b0, shamt[5:0], rs1_exp, F3_SR, rs1_exp, OP_IMM};
                end
              end

              2'b01: begin  // C.SRAI
                if (shamt[6] && !is_rv64) begin
                  illegal_instr = 1'b1;  // shamt[5] must be 0 in RV32
                end else begin
                  // SRAI rd', rd', shamt (rd' is at bits [9:7])
                  // 需要 funct7 = 0100000 用于 SRAI
                  decompressed_instr = {7'b0100000, shamt[4:0], rs1_exp, F3_SR, rs1_exp, OP_IMM};
                end
              end

              2'b10: begin  // C.ANDI
                // ANDI rd', rd', imm (rd' is at bits [9:7])
                decompressed_instr = {imm_andi, rs1_exp, F3_AND, rs1_exp, OP_IMM};
              end

              2'b11: begin  // 寄存器-寄存器操作
                case ({compressed_instr[12], funct2})
                  3'b000: begin  // C.SUB
                    // SUB rd', rd', rs2' (rd'/rs1' at [9:7], rs2' at [4:2])
                    decompressed_instr = {7'b0100000, rs2_exp, rs1_exp, F3_ADD,
                                           rs1_exp, OP};
                  end

                  3'b001: begin  // C.XOR
                    // XOR rd', rd', rs2' (rd'/rs1' at [9:7], rs2' at [4:2])
                    decompressed_instr = {7'b0000000, rs2_exp, rs1_exp, F3_XOR,
                                           rs1_exp, OP};
                  end

                  3'b010: begin  // C.OR
                    // OR rd', rd', rs2' (rd'/rs1' at [9:7], rs2' at [4:2])
                    decompressed_instr = {7'b0000000, rs2_exp, rs1_exp, F3_OR,
                                           rs1_exp, OP};
                  end

                  3'b011: begin  // C.AND
                    // AND rd', rd', rs2' (rd'/rs1' at [9:7], rs2' at [4:2])
                    decompressed_instr = {7'b0000000, rs2_exp, rs1_exp, F3_AND,
                                           rs1_exp, OP};
                  end

                  3'b100: begin  // C.SUBW (RV64)
                    if (is_rv64) begin
                      // SUBW rd', rd', rs2' (rd'/rs1' at [9:7], rs2' at [4:2])
                      decompressed_instr = {7'b0100000, rs2_exp, rs1_exp, F3_ADD,
                                             rs1_exp, OP_32};
                    end else begin
                      illegal_instr = 1'b1;
                    end
                  end

                  3'b101: begin  // C.ADDW (RV64)
                    if (is_rv64) begin
                      // ADDW rd', rd', rs2' (rd'/rs1' at [9:7], rs2' at [4:2])
                      decompressed_instr = {7'b0000000, rs2_exp, rs1_exp, F3_ADD,
                                             rs1_exp, OP_32};
                    end else begin
                      illegal_instr = 1'b1;
                    end
                  end

                  default: illegal_instr = 1'b1;
                endcase
              end
            endcase
          end

          3'b101: begin  // C.J
            // JAL x0, offset
            decompressed_instr = {imm_j[20], imm_j[10:1], imm_j[11],
                                   imm_j[19:12], x0, JAL};
          end

          3'b110: begin  // C.BEQZ
            // BEQ rs1', x0, offset
            decompressed_instr = {imm_b[12], imm_b[10:5], x0, rs1_exp, F3_BEQ,
                                   imm_b[4:1], imm_b[11], BRANCH};
          end

          3'b111: begin  // C.BNEZ
            // BNE rs1', x0, offset
            decompressed_instr = {imm_b[12], imm_b[10:5], x0, rs1_exp, F3_BNE,
                                   imm_b[4:1], imm_b[11], BRANCH};
          end
        endcase
      end

      // ================================================================
      // 象限 2 (op = 10)
      // ================================================================
      2'b10: begin
        case (funct3)
          3'b000: begin  // C.SLLI
            if (rd != x0) begin
              if (shamt[6] && !is_rv64) begin
                illegal_instr = 1'b1;  // shamt[5] 在 RV32 中必须为 0
              end else begin
                // SLLI rd, rd, shamt
                decompressed_instr = {1'b0, shamt[5:0], rd, F3_SLL, rd, OP_IMM};
              end
            end else begin
              // Hint (rd=x0)
              decompressed_instr = {1'b0, shamt[5:0], x0, F3_SLL, x0, OP_IMM};
            end
          end

          3'b010: begin  // C.LWSP
            if (rd != x0) begin
              // LW rd, offset(x2)
              decompressed_instr = {4'b0, imm_lwsp[7:0], x2, F3_LW, rd, LOAD};
            end else begin
              illegal_instr = 1'b1;  // rd 必须非零
            end
          end

          3'b001: begin  // C.FLDSP (RV32DC/RV64DC)
            // FLD rd, offset(x2)
            // 从堆栈加载双精度浮点数
            if (rd != x0) begin
              decompressed_instr = {3'b0, imm_ldsp[8:0], x2, F3_FLD, rd, LOAD_FP};
            end else begin
              illegal_instr = 1'b1;  // rd 必须非零
            end
          end

          3'b011: begin  // C.LDSP (RV64) / C.FLWSP (RV32FC)
            if (is_rv64) begin
              if (rd != x0) begin
                // LD rd, offset(x2)
                decompressed_instr = {3'b0, imm_ldsp[8:0], x2, F3_LD, rd, LOAD};
              end else begin
                illegal_instr = 1'b1;  // rd 必须非零
              end
            end else begin
              // C.FLWSP - FLW rd, offset(x2)
              // 从堆栈加载单精度浮点数
              if (rd != x0) begin
                decompressed_instr = {4'b0, imm_lwsp[7:0], x2, F3_FLW, rd, LOAD_FP};
              end else begin
                illegal_instr = 1'b1;  // rd 必须非零
              end
            end
          end

          3'b100: begin  // C.JR / C.MV / C.EBREAK / C.JALR / C.ADD
            if (compressed_instr[12] == 1'b0) begin
              if (rs2 == x0) begin
                // C.JR
                if (rs1 != x0) begin
                  // JALR x0, 0(rs1)
                  decompressed_instr = {12'b0, rs1, F3_ADD, x0, JALR};
                end else begin
                  illegal_instr = 1'b1;  // rs1 必须非零
                end
              end else begin
                // C.MV：应当展开为 ADDI rd, rs2, 0（而不是 ADD rd, x0, rs2）
                if (rd != x0) begin
                  // ADDI rd, rs2, 0
                  decompressed_instr = {12'b0, rs2, F3_ADD, rd, OP_IMM};
                end else begin
                  // Hint (rd=x0)
                  decompressed_instr = {12'b0, rs2, F3_ADD, x0, OP_IMM};
                end
              end
            end else begin  // compressed_instr[12] == 1
              if (rs2 == x0) begin
                if (rs1 == x0) begin
                  // C.EBREAK
                  decompressed_instr = 32'h00100073;  // EBREAK
                end else begin
                  // C.JALR
                  // JALR x1, 0(rs1)
                  decompressed_instr = {12'b0, rs1, F3_ADD, x1, JALR};
                end
              end else begin
                // C.ADD
                if (rd != x0) begin
                  // ADD rd, rd, rs2
                  decompressed_instr = {7'b0000000, rs2, rd, F3_ADD, rd, OP};
                end else begin
                  // Hint (rd=x0)
                  decompressed_instr = {7'b0000000, rs2, x0, F3_ADD, x0, OP};
                end
              end
            end
          end

          3'b101: begin  // C.FSDSP (RV32DC/RV64DC)
            // FSD rs2, offset(x2)
            // 存储双精度浮点数到堆栈
            // S-type: imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
            decompressed_instr = {3'b0, imm_sdsp[8:5], rs2, x2, F3_FSD,
                                   imm_sdsp[4:0], STORE_FP};
          end

          3'b110: begin  // C.SWSP
            // SW rs2, offset(x2)
            // S-type: imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
            decompressed_instr = {4'b0, imm_swsp[7:5], rs2, x2, F3_SW,
                                   imm_swsp[4:0], STORE};
          end

          3'b111: begin  // C.SDSP (RV64) / C.FSWSP (RV32FC)
            if (is_rv64) begin
              // SD rs2, offset(x2)
              // S-type: imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
              decompressed_instr = {3'b0, imm_sdsp[8:5], rs2, x2, F3_SD,
                                     imm_sdsp[4:0], STORE};
            end else begin
              // C.FSWSP - FSW rs2, offset(x2)
              // 存储单精度浮点数到堆栈
              decompressed_instr = {4'b0, imm_swsp[7:5], rs2, x2, F3_FSW,
                                     imm_swsp[4:0], STORE_FP};
            end
          end

          default: illegal_instr = 1'b1;
        endcase
      end

      // ================================================================
      // 象限 3 (op = 11) - 非压缩（32 位指令）
      // ================================================================
      2'b11: begin
        // 这是一个 32 位指令，不是压缩指令
        // 不是非法指令 - 只是非压缩指令
        // 调用者应在使用解压缩输出之前检查 is_compressed_out
        illegal_instr = 1'b0;
        decompressed_instr = 32'h00000013;  // 输出 NOP（不用于 32 位指令）
      end
    endcase
  end

endmodule
