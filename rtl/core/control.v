// control.v - Main control unit for RV32I
// Generates control signals based on opcode and function fields
// Author: RV1 Project
// Date: 2025-10-09

module control (
  input  wire [6:0] opcode,      // Opcode from instruction
  input  wire [2:0] funct3,      // Function3 field
  input  wire [6:0] funct7,      // Function7 field
  output reg        reg_write,   // Register file write enable
  output reg        mem_read,    // Memory read enable
  output reg        mem_write,   // Memory write enable
  output reg        branch,      // Branch instruction
  output reg        jump,        // Jump instruction
  output reg  [3:0] alu_control, // ALU operation
  output reg        alu_src,     // ALU source: 0=rs2, 1=immediate
  output reg  [1:0] wb_sel,      // Write-back select: 00=ALU, 01=MEM, 10=PC+4
  output reg  [2:0] imm_sel      // Immediate format select
);

  // Opcode definitions
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
    wb_sel = 2'b00;
    imm_sel = IMM_I;

    case (opcode)
      OP_LUI: begin
        // LUI: rd = imm_u
        reg_write = 1'b1;
        alu_src = 1'b1;
        alu_control = 4'b0000;  // Pass through (0 + imm)
        wb_sel = 2'b00;
        imm_sel = IMM_U;
      end

      OP_AUIPC: begin
        // AUIPC: rd = PC + imm_u
        reg_write = 1'b1;
        alu_src = 1'b1;
        alu_control = 4'b0000;  // ADD
        wb_sel = 2'b00;
        imm_sel = IMM_U;
      end

      OP_JAL: begin
        // JAL: rd = PC + 4, PC = PC + imm_j
        reg_write = 1'b1;
        jump = 1'b1;
        wb_sel = 2'b10;  // Write PC+4
        imm_sel = IMM_J;
      end

      OP_JALR: begin
        // JALR: rd = PC + 4, PC = rs1 + imm_i
        reg_write = 1'b1;
        jump = 1'b1;
        alu_src = 1'b1;
        alu_control = 4'b0000;  // ADD
        wb_sel = 2'b10;  // Write PC+4
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
        wb_sel = 2'b01;  // Write from memory
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
        wb_sel = 2'b00;
        imm_sel = IMM_I;
      end

      OP_OP: begin
        // Register-register ALU operations
        reg_write = 1'b1;
        alu_src = 1'b0;  // Use rs2
        alu_control = get_alu_control(funct3, funct7, 1'b1);
        wb_sel = 2'b00;
      end

      OP_FENCE: begin
        // FENCE: No-op in our simple implementation
        // In a real system, this would flush caches/buffers
      end

      OP_SYSTEM: begin
        // ECALL/EBREAK: No-op for now
        // Future: trigger exception
      end

      default: begin
        // Invalid opcode: all signals stay at default (no-op)
      end
    endcase
  end

endmodule
