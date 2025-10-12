// control.v - Main control unit for RISC-V
// Generates control signals based on opcode and function fields
// Parameterized for RV32/RV64 support
// Author: RV1 Project
// Date: 2025-10-09
// Updated: 2025-10-10 - Added CSR and trap support, RV64 support

`include "config/rv_config.vh"

module control #(
  parameter XLEN = `XLEN
) (
  input  wire [6:0] opcode,      // Opcode from instruction
  input  wire [2:0] funct3,      // Function3 field
  input  wire [6:0] funct7,      // Function7 field

  // Decoder inputs for special instructions
  input  wire       is_csr,      // CSR instruction
  input  wire       is_ecall,    // ECALL instruction
  input  wire       is_ebreak,   // EBREAK instruction
  input  wire       is_mret,     // MRET instruction
  input  wire       is_mul_div,  // M extension instruction
  input  wire [3:0] mul_div_op,  // M extension operation (from decoder)
  input  wire       is_word_op,  // RV64M: W-suffix instruction
  input  wire       is_atomic,   // A extension instruction
  input  wire [4:0] funct5,      // funct5 field for atomic instructions
  input  wire       is_fp,       // F/D extension instruction
  input  wire       is_fp_load,  // FLW/FLD
  input  wire       is_fp_store, // FSW/FSD
  input  wire       is_fp_op,    // FP computational operation
  input  wire       is_fp_fma,   // FP fused multiply-add

  // Standard control outputs
  output reg        reg_write,   // Register file write enable
  output reg        mem_read,    // Memory read enable
  output reg        mem_write,   // Memory write enable
  output reg        branch,      // Branch instruction
  output reg        jump,        // Jump instruction
  output reg  [3:0] alu_control, // ALU operation
  output reg        alu_src,     // ALU source: 0=rs2, 1=immediate
  output reg  [2:0] wb_sel,      // Write-back select: 000=ALU, 001=MEM, 010=PC+4, 011=CSR, 100=M_UNIT
  output reg  [2:0] imm_sel,     // Immediate format select

  // CSR control outputs
  output reg        csr_we,      // CSR write enable
  output reg        csr_src,     // CSR source: 0=rs1, 1=uimm

  // M extension control outputs
  output reg        mul_div_en,  // M extension unit enable
  output reg [3:0]  mul_div_op_out, // M extension operation (passed through)
  output reg        is_word_op_out,  // RV64M: W-suffix instruction (passed through)

  // A extension control outputs
  output reg        atomic_en,   // A extension unit enable
  output reg [4:0]  atomic_funct5, // Atomic operation (funct5)

  // F/D extension control outputs
  output reg        fp_reg_write,    // FP register file write enable
  output reg        int_reg_write_fp, // Integer register write (for FMV.X.W, FP compare)
  output reg        fp_mem_op,       // FP memory operation (load/store)
  output reg        fp_alu_en,       // FP ALU enable
  output reg [4:0]  fp_alu_op,       // FP ALU operation
  output reg        fp_use_dynamic_rm, // Use dynamic rounding mode from fcsr

  // Exception/trap outputs
  output reg        illegal_inst // Illegal instruction detected
);

  // Opcode definitions (RV32I)
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

  // RV64I-specific opcodes
  localparam OP_IMM_32 = 7'b0011011;  // ADDIW, SLLIW, SRLIW, SRAIW
  localparam OP_OP_32  = 7'b0111011;  // ADDW, SUBW, SLLW, SRLW, SRAW

  // A extension opcode
  localparam OP_AMO    = 7'b0101111;  // Atomic operations (LR, SC, AMO)

  // F/D extension opcodes
  localparam OP_LOAD_FP  = 7'b0000111;  // FLW, FLD
  localparam OP_STORE_FP = 7'b0100111;  // FSW, FSD
  localparam OP_MADD     = 7'b1000011;  // FMADD.S/D
  localparam OP_MSUB     = 7'b1000111;  // FMSUB.S/D
  localparam OP_NMSUB    = 7'b1001011;  // FNMSUB.S/D
  localparam OP_NMADD    = 7'b1001111;  // FNMADD.S/D
  localparam OP_OP_FP    = 7'b1010011;  // All other FP operations

  // FP ALU operation encoding
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

  // Immediate format select
  localparam IMM_I = 3'b000;
  localparam IMM_S = 3'b001;
  localparam IMM_B = 3'b010;
  localparam IMM_U = 3'b011;
  localparam IMM_J = 3'b100;

  // ALU control based on funct3 and funct7
  function [3:0] get_alu_control;
    input [2:0] f3;
    input [6:0] f7;
    input is_reg_op;  // 1 for R-type, 0 for I-type
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
    // Default values
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
        alu_control = 4'b0000;  // Pass through (0 + imm)
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
        wb_sel = 3'b010;  // Write PC+4
        imm_sel = IMM_J;
      end

      OP_JALR: begin
        // JALR: rd = PC + 4, PC = rs1 + imm_i
        reg_write = 1'b1;
        jump = 1'b1;
        alu_src = 1'b1;
        alu_control = 4'b0000;  // ADD
        wb_sel = 3'b010;  // Write PC+4
        imm_sel = IMM_I;
      end

      OP_BRANCH: begin
        // Branch instructions
        branch = 1'b1;
        alu_control = 4'b0001;  // SUB for comparison
        imm_sel = IMM_B;
      end

      OP_LOAD: begin
        // Load instructions
        reg_write = 1'b1;
        mem_read = 1'b1;
        alu_src = 1'b1;
        alu_control = 4'b0000;  // ADD (rs1 + offset)
        wb_sel = 3'b001;  // Write from memory
        imm_sel = IMM_I;
      end

      OP_STORE: begin
        // Store instructions
        mem_write = 1'b1;
        alu_src = 1'b1;
        alu_control = 4'b0000;  // ADD (rs1 + offset)
        imm_sel = IMM_S;
      end

      OP_IMM: begin
        // Immediate ALU operations
        reg_write = 1'b1;
        alu_src = 1'b1;
        alu_control = get_alu_control(funct3, funct7, 1'b0);
        wb_sel = 3'b000;
        imm_sel = IMM_I;
      end

      OP_OP: begin
        // Register-register ALU operations (or M extension)
        reg_write = 1'b1;
        alu_src = 1'b0;  // Use rs2

        if (is_mul_div) begin
          // M extension instruction
          mul_div_en = 1'b1;          // Enable M unit
          mul_div_op_out = mul_div_op; // Pass through operation
          is_word_op_out = is_word_op; // Pass through word-op flag
          wb_sel = 3'b100;             // Select M unit result
          alu_control = 4'b0000;       // ALU not used, but pass rs1 and rs2 through
        end else begin
          // Standard ALU operation
          alu_control = get_alu_control(funct3, funct7, 1'b1);
          wb_sel = 3'b000;
        end
      end

      OP_FENCE: begin
        // FENCE: No-op in our simple implementation
        // In a real system, this would flush caches/buffers
      end

      OP_IMM_32: begin
        // RV64I: 32-bit immediate operations (ADDIW, SLLIW, SRLIW, SRAIW)
        // These operate on lower 32 bits and sign-extend result to 64 bits
        if (XLEN == 64) begin
          reg_write = 1'b1;
          alu_src = 1'b1;
          alu_control = get_alu_control(funct3, funct7, 1'b0);
          wb_sel = 3'b000;
          imm_sel = IMM_I;
        end else begin
          // Illegal in RV32
          illegal_inst = 1'b1;
        end
      end

      OP_OP_32: begin
        // RV64I: 32-bit register operations (ADDW, SUBW, SLLW, SRLW, SRAW)
        // RV64M: 32-bit M extension (MULW, DIVW, DIVUW, REMW, REMUW)
        // These operate on lower 32 bits and sign-extend result to 64 bits
        if (XLEN == 64) begin
          reg_write = 1'b1;
          alu_src = 1'b0;  // Use rs2

          if (is_mul_div) begin
            // RV64M word operation
            mul_div_en = 1'b1;          // Enable M unit
            mul_div_op_out = mul_div_op; // Pass through operation
            is_word_op_out = is_word_op; // Pass through word-op flag (will be 1)
            wb_sel = 3'b100;             // Select M unit result
            alu_control = 4'b0000;       // ALU not used
          end else begin
            // RV64I word operation
            alu_control = get_alu_control(funct3, funct7, 1'b1);
            wb_sel = 3'b000;
          end
        end else begin
          // Illegal in RV32
          illegal_inst = 1'b1;
        end
      end

      OP_AMO: begin
        // A extension: Atomic operations (LR, SC, AMO)
        if (is_atomic) begin
          reg_write = 1'b1;          // Atomic ops write result to rd
          atomic_en = 1'b1;          // Enable atomic unit
          atomic_funct5 = funct5;    // Pass atomic operation type
          wb_sel = 3'b101;           // Write-back from atomic unit (new wb_sel value)
          alu_src = 1'b1;            // Use immediate (0) for address calculation
          alu_control = 4'b0000;     // ADD (rs1 + 0 = rs1)
          imm_sel = IMM_I;
        end else begin
          illegal_inst = 1'b1;
        end
      end

      OP_LOAD_FP: begin
        // FLW/FLD: Load floating-point value from memory
        if (is_fp_load) begin
          fp_reg_write = 1'b1;        // Write to FP register file
          mem_read = 1'b1;            // Read from memory
          fp_mem_op = 1'b1;           // FP memory operation
          alu_src = 1'b1;             // Use immediate
          alu_control = 4'b0000;      // ADD (rs1 + offset)
          imm_sel = IMM_I;
          wb_sel = 3'b001;            // Write-back from memory
        end else begin
          illegal_inst = 1'b1;
        end
      end

      OP_STORE_FP: begin
        // FSW/FSD: Store floating-point value to memory
        if (is_fp_store) begin
          mem_write = 1'b1;           // Write to memory
          fp_mem_op = 1'b1;           // FP memory operation
          alu_src = 1'b1;             // Use immediate
          alu_control = 4'b0000;      // ADD (rs1 + offset)
          imm_sel = IMM_S;
        end else begin
          illegal_inst = 1'b1;
        end
      end

      OP_MADD, OP_MSUB, OP_NMSUB, OP_NMADD: begin
        // FMA instructions: FMADD, FMSUB, FNMSUB, FNMADD
        if (is_fp_fma) begin
          fp_reg_write = 1'b1;        // Write to FP register file
          fp_alu_en = 1'b1;           // Enable FP ALU
          fp_use_dynamic_rm = (funct3 == 3'b111);  // Use dynamic RM if rm=111

          // Determine FMA variant
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
        // Floating-point computational operations
        if (is_fp_op) begin
          // Decode based on funct7 (which includes format bits)
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
            5'b11000, 5'b11001, 5'b11010, 5'b11011: begin  // FCVT (float to int, int to float, float to float)
              if (funct7[1:0] == 2'b00 || funct7[1:0] == 2'b01) begin  // FCVT to/from integer
                // Check rs2 for conversion type
                if (funct7[6] == 1'b1) begin
                  // FCVT.W.S/D, FCVT.WU.S/D, FCVT.L.S/D, FCVT.LU.S/D (FP to int)
                  int_reg_write_fp = 1'b1;  // Write to integer register
                end else begin
                  // FCVT.S.W, FCVT.S.WU, FCVT.S.L, FCVT.S.LU (int to FP)
                  fp_reg_write = 1'b1;  // Write to FP register
                end
                fp_alu_en = 1'b1;
                fp_alu_op = FP_CVT;
                fp_use_dynamic_rm = (funct3 == 3'b111);
              end else begin
                // FCVT.S.D or FCVT.D.S (single ↔ double conversion)
                fp_reg_write = 1'b1;
                fp_alu_en = 1'b1;
                fp_alu_op = FP_CVT;
                fp_use_dynamic_rm = (funct3 == 3'b111);
              end
            end
            5'b10100: begin  // FEQ.S/D, FLT.S/D, FLE.S/D (comparisons)
              int_reg_write_fp = 1'b1;  // Write result to integer register
              fp_alu_en = 1'b1;
              fp_alu_op = FP_CMP;
            end
            5'b11100: begin  // FMV.X.W/D, FCLASS.S/D
              int_reg_write_fp = 1'b1;  // Write to integer register
              if (funct3 == 3'b000) begin
                fp_alu_op = FP_MV_XW;  // FMV.X.W/D
              end else if (funct3 == 3'b001) begin
                fp_alu_en = 1'b1;
                fp_alu_op = FP_CLASS;  // FCLASS
              end else begin
                illegal_inst = 1'b1;
              end
            end
            5'b11110: begin  // FMV.W.X/D.X
              fp_reg_write = 1'b1;  // Write to FP register
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
        // SYSTEM instructions: CSR, ECALL, EBREAK, MRET
        if (is_csr) begin
          // CSR instructions
          reg_write = 1'b1;        // Write CSR read value to rd
          wb_sel = 3'b011;         // Write-back from CSR

          // Determine CSR write enable
          // For CSRRW/CSRRWI: always write (unless rd=x0, but that's handled in core)
          // For CSRRS/CSRRC/CSRRSI/CSRRCI: write if rs1/uimm != 0
          // We'll handle the write suppression in the core, so always enable here
          csr_we = 1'b1;

          // CSR source: immediate (1) for funct3[2]=1, register (0) otherwise
          csr_src = funct3[2];

        end else if (is_ecall || is_ebreak) begin
          // ECALL/EBREAK: trigger exception
          // These don't write to registers or memory
          // Exception will be handled in the core

        end else if (is_mret) begin
          // MRET: return from trap
          // This is handled as a special jump in the core
          jump = 1'b1;  // Indicate control flow change

        end else begin
          // Unknown SYSTEM instruction
          illegal_inst = 1'b1;
        end
      end

      default: begin
        // Invalid opcode: mark as illegal instruction
        illegal_inst = 1'b1;
      end
    endcase
  end

endmodule
