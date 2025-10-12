// RVC Decoder - RISC-V Compressed Instruction Decompressor
// Converts 16-bit compressed instructions to 32-bit standard instructions
//
// This module implements the RISC-V C (Compressed) extension decoder.
// It takes a 16-bit compressed instruction and expands it to the equivalent
// 32-bit instruction that the rest of the pipeline can execute.
//
// Key features:
// - Supports RV32C and RV64C
// - All quadrants (Q0, Q1, Q2) supported
// - Combinational logic (single-cycle decompression)
// - Illegal instruction detection

module rvc_decoder #(
  parameter XLEN = 32
) (
  input  wire [15:0] compressed_instr,     // 16-bit compressed instruction
  input  wire        is_rv64,              // 1 = RV64 mode, 0 = RV32 mode
  output reg  [31:0] decompressed_instr,   // 32-bit expanded instruction
  output reg         illegal_instr,        // Illegal compressed instruction flag
  output wire        is_compressed_out     // Pass-through of compression detection
);

  // Detect if instruction is compressed (opcode != 11)
  wire [1:0] opcode = compressed_instr[1:0];
  assign is_compressed_out = (opcode != 2'b11);

  // Extract common fields
  wire [2:0] funct3 = compressed_instr[15:13];
  wire [1:0] funct2 = compressed_instr[6:5];

  // Register fields
  wire [4:0] rd     = compressed_instr[11:7];
  wire [4:0] rs1    = compressed_instr[11:7];
  wire [4:0] rs2    = compressed_instr[6:2];

  // Compressed register fields (3-bit -> map to x8-x15)
  wire [2:0] rd_p   = compressed_instr[4:2];
  wire [2:0] rs1_p  = compressed_instr[9:7];
  wire [2:0] rs2_p  = compressed_instr[4:2];

  // Expanded compressed registers (add 8 to get x8-x15)
  wire [4:0] rd_exp  = {2'b01, rd_p};
  wire [4:0] rs1_exp = {2'b01, rs1_p};
  wire [4:0] rs2_exp = {2'b01, rs2_p};

  // Special registers
  wire [4:0] x0 = 5'd0;   // Zero register
  wire [4:0] x1 = 5'd1;   // Return address
  wire [4:0] x2 = 5'd2;   // Stack pointer

  // RISC-V base instruction opcodes
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

  // funct3 codes
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

  // Immediate extraction functions
  // Note: Immediates are scrambled in compressed format for hardware efficiency

  // C.ADDI4SPN: nzuimm[9:2]
  // Instruction bits [12:5] encode nzuimm[5:4|9:6|2|3]
  // Reassemble as nzuimm[9:6|5:4|3:2] + scale by 4
  wire [9:0] imm_addi4spn = {compressed_instr[10:7], compressed_instr[12:11],
                              compressed_instr[5], compressed_instr[6], 2'b0};

  // C.LW: offset[6:2]
  // Instruction bits [12:10] encode uimm[5:3], bits [6:5] encode uimm[2|6]
  wire [6:0] imm_lw = {2'b0, compressed_instr[5], compressed_instr[12:10],
                        compressed_instr[6], 2'b0};

  // C.LD: offset[7:3] (RV64)
  wire [7:0] imm_ld = {2'b0, compressed_instr[6:5], compressed_instr[12:10], 3'b0};

  // C.LWSP: offset[7:2]
  // Format: imm[5] in bit 12, imm[4:2|7:6] in bits [6:2]
  // bits [6:4] = uimm[4:2], bits [3:2] = uimm[7:6], bit [12] = uimm[5]
  wire [7:0] imm_lwsp = {compressed_instr[3:2], compressed_instr[12],
                          compressed_instr[6:4], 2'b00};

  // C.LDSP: offset[8:3] (RV64)
  // bits [6:5] = uimm[4:3], bits [4:2] = uimm[8:6], bit [12] = uimm[5]
  wire [8:0] imm_ldsp = {compressed_instr[4:2], compressed_instr[12],
                          compressed_instr[6:5], 3'b0};

  // C.SWSP: offset[7:2]
  // bits [12:9] = uimm[5:2], bits [8:7] = uimm[7:6]
  wire [7:0] imm_swsp = {compressed_instr[8:7], compressed_instr[12:9], 2'b0};

  // C.SDSP: offset[8:3] (RV64)
  // bits [12:10] = uimm[5:3], bits [9:7] = uimm[8:6]
  wire [8:0] imm_sdsp = {compressed_instr[9:7], compressed_instr[12:10], 3'b0};

  // C.ADDI/C.LI: imm[5:0]
  wire [11:0] imm_addi = {{6{compressed_instr[12]}}, compressed_instr[12],
                           compressed_instr[6:2]};

  // C.ADDI16SP: nzimm[9:4]
  // Bit 12 = nzimm[9], bits [6:2] = nzimm[4|6|8:7|5]
  wire [11:0] imm_addi16sp = {{3{compressed_instr[12]}}, compressed_instr[12],
                               compressed_instr[4:3], compressed_instr[5],
                               compressed_instr[2], compressed_instr[6], 4'b0};

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
  // bits [12:2] encode imm[11|4|9:8|10|6|7|3:1|5]
  // JAL format needs: imm[20|10:1|11|19:12]
  wire [20:0] imm_j = {{9{compressed_instr[12]}}, compressed_instr[12],
                        compressed_instr[8], compressed_instr[10:9],
                        compressed_instr[6], compressed_instr[7],
                        compressed_instr[2], compressed_instr[11],
                        compressed_instr[5:3], 1'b0};

  // C.BEQZ/C.BNEZ: offset[8:1]
  wire [12:0] imm_b = {{4{compressed_instr[12]}}, compressed_instr[12],
                        compressed_instr[6:5], compressed_instr[2],
                        compressed_instr[11:10], compressed_instr[4:3], 1'b0};

  // Decompression logic
  always @(*) begin
    illegal_instr = 1'b0;
    decompressed_instr = 32'h00000013;  // Default: ADDI x0, x0, 0 (NOP)

    case (opcode)
      // ================================================================
      // Quadrant 0 (op = 00)
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
              // C.FLW not implemented (requires F extension)
              illegal_instr = 1'b1;
            end
          end

          3'b110: begin  // C.SW
            // SW rs2', offset(rs1')
            decompressed_instr = {5'b0, imm_lw[6:2], rs2_exp, rs1_exp, F3_SW,
                                   imm_lw[1:0], 3'b0, STORE};
          end

          3'b111: begin  // C.SD (RV64) / C.FSW (RV32+F)
            if (is_rv64) begin
              // SD rs2', offset(rs1')
              decompressed_instr = {4'b0, imm_ld[7:3], rs2_exp, rs1_exp, F3_SD,
                                     imm_ld[2:0], 2'b0, STORE};
            end else begin
              // C.FSW not implemented (requires F extension)
              illegal_instr = 1'b1;
            end
          end

          default: illegal_instr = 1'b1;
        endcase
      end

      // ================================================================
      // Quadrant 1 (op = 01)
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
              // Reserved (rd=x0, imm!=0)
              illegal_instr = 1'b1;
            end
          end

          3'b001: begin  // C.JAL (RV32) / C.ADDIW (RV64)
            if (is_rv64) begin
              // C.ADDIW: ADDIW rd, rd, imm
              if (rd != x0) begin
                decompressed_instr = {imm_addi, rd, F3_ADD, rd, OP_IMM_32};
              end else begin
                illegal_instr = 1'b1;  // rd must be non-zero
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
                illegal_instr = 1'b1;  // nzimm must be non-zero
              end else begin
                decompressed_instr = {imm_addi16sp, x2, F3_ADD, x2, OP_IMM};
              end
            end else if (rd != x0) begin
              // C.LUI: LUI rd, nzimm
              if (imm_lui == 32'b0) begin
                illegal_instr = 1'b1;  // nzimm must be non-zero
              end else begin
                decompressed_instr = {imm_lui[31:12], rd, LUI};
              end
            end else begin
              illegal_instr = 1'b1;  // Reserved
            end
          end

          3'b100: begin  // Arithmetic/shift operations
            case (compressed_instr[11:10])
              2'b00: begin  // C.SRLI
                if (shamt[6] && !is_rv64) begin
                  illegal_instr = 1'b1;  // shamt[5] must be 0 in RV32
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
                  // Need funct7 = 0100000 for SRAI
                  decompressed_instr = {7'b0100000, shamt[4:0], rs1_exp, F3_SR, rs1_exp, OP_IMM};
                end
              end

              2'b10: begin  // C.ANDI
                // ANDI rd', rd', imm (rd' is at bits [9:7])
                decompressed_instr = {imm_andi, rs1_exp, F3_AND, rs1_exp, OP_IMM};
              end

              2'b11: begin  // Register-register ops
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
      // Quadrant 2 (op = 10)
      // ================================================================
      2'b10: begin
        case (funct3)
          3'b000: begin  // C.SLLI
            if (rd != x0) begin
              if (shamt[6] && !is_rv64) begin
                illegal_instr = 1'b1;  // shamt[5] must be 0 in RV32
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
              illegal_instr = 1'b1;  // rd must be non-zero
            end
          end

          3'b011: begin  // C.LDSP (RV64) / C.FLWSP (RV32+F)
            if (is_rv64) begin
              if (rd != x0) begin
                // LD rd, offset(x2)
                decompressed_instr = {3'b0, imm_ldsp[8:0], x2, F3_LD, rd, LOAD};
              end else begin
                illegal_instr = 1'b1;  // rd must be non-zero
              end
            end else begin
              // C.FLWSP not implemented (requires F extension)
              illegal_instr = 1'b1;
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
                  illegal_instr = 1'b1;  // rs1 must be non-zero
                end
              end else begin
                // C.MV
                if (rd != x0) begin
                  // ADD rd, x0, rs2
                  decompressed_instr = {7'b0000000, rs2, x0, F3_ADD, rd, OP};
                end else begin
                  // Hint (rd=x0)
                  decompressed_instr = {7'b0000000, rs2, x0, F3_ADD, x0, OP};
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

          3'b110: begin  // C.SWSP
            // SW rs2, offset(x2)
            decompressed_instr = {4'b0, imm_swsp[7:2], rs2, x2, F3_SW,
                                   imm_swsp[1:0], 3'b0, STORE};
          end

          3'b111: begin  // C.SDSP (RV64) / C.FSWSP (RV32+F)
            if (is_rv64) begin
              // SD rs2, offset(x2)
              decompressed_instr = {3'b0, imm_sdsp[8:3], rs2, x2, F3_SD,
                                     imm_sdsp[2:0], 2'b0, STORE};
            end else begin
              // C.FSWSP not implemented (requires F extension)
              illegal_instr = 1'b1;
            end
          end

          default: illegal_instr = 1'b1;
        endcase
      end

      // ================================================================
      // Quadrant 3 (op = 11) - Not compressed (32-bit instruction)
      // ================================================================
      2'b11: begin
        // This is a 32-bit instruction, not compressed
        // Should not reach here if caller checks is_compressed first
        illegal_instr = 1'b1;
      end
    endcase
  end

endmodule
