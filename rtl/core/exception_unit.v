// exception_unit.v - Exception Detection Unit
// Detects various exceptions in the pipeline
// Parameterized for RV32/RV64
// Author: RV1 Project
// Date: 2025-10-10

`include "config/rv_config.vh"

module exception_unit #(
  parameter XLEN = `XLEN
) (
  // Instruction address misaligned (IF stage)
  input  wire [XLEN-1:0] if_pc,
  input  wire            if_valid,

  // Illegal instruction (ID stage)
  input  wire            id_illegal_inst,
  input  wire            id_ecall,
  input  wire            id_ebreak,
  input  wire [XLEN-1:0] id_pc,
  input  wire [31:0]     id_instruction,       // Instructions always 32-bit
  input  wire            id_valid,

  // Misaligned access (MEM stage)
  input  wire [XLEN-1:0] mem_addr,
  input  wire            mem_read,
  input  wire            mem_write,
  input  wire [2:0]      mem_funct3,
  input  wire [XLEN-1:0] mem_pc,
  input  wire [31:0]     mem_instruction,      // Instructions always 32-bit
  input  wire            mem_valid,

  // Exception outputs
  output reg             exception,
  output reg  [4:0]      exception_code,
  output reg  [XLEN-1:0] exception_pc,
  output reg  [XLEN-1:0] exception_val
);

  // =========================================================================
  // Exception Code Definitions (RISC-V Spec)
  // =========================================================================

  localparam CAUSE_INST_ADDR_MISALIGNED = 5'd0;
  localparam CAUSE_INST_ACCESS_FAULT    = 5'd1;
  localparam CAUSE_ILLEGAL_INST         = 5'd2;
  localparam CAUSE_BREAKPOINT           = 5'd3;
  localparam CAUSE_LOAD_ADDR_MISALIGNED = 5'd4;
  localparam CAUSE_LOAD_ACCESS_FAULT    = 5'd5;
  localparam CAUSE_STORE_ADDR_MISALIGNED= 5'd6;
  localparam CAUSE_STORE_ACCESS_FAULT   = 5'd7;
  localparam CAUSE_ECALL_FROM_U_MODE    = 5'd8;
  localparam CAUSE_ECALL_FROM_S_MODE    = 5'd9;
  localparam CAUSE_ECALL_FROM_M_MODE    = 5'd11;

  // funct3 encodings for load/store
  localparam FUNCT3_LB  = 3'b000;
  localparam FUNCT3_LH  = 3'b001;
  localparam FUNCT3_LW  = 3'b010;
  localparam FUNCT3_LD  = 3'b011;  // RV64 only
  localparam FUNCT3_LBU = 3'b100;
  localparam FUNCT3_LHU = 3'b101;
  localparam FUNCT3_LWU = 3'b110;  // RV64 only
  localparam FUNCT3_SB  = 3'b000;
  localparam FUNCT3_SH  = 3'b001;
  localparam FUNCT3_SW  = 3'b010;
  localparam FUNCT3_SD  = 3'b011;  // RV64 only

  // =========================================================================
  // Exception Detection Logic
  // =========================================================================

  // IF stage: Instruction address misaligned
  wire if_inst_misaligned = if_valid && (if_pc[1:0] != 2'b00);

  // ID stage: Illegal instruction
  wire id_illegal = id_valid && id_illegal_inst;

  // ID stage: ECALL
  wire id_ecall_exc = id_valid && id_ecall;

  // ID stage: EBREAK
  wire id_ebreak_exc = id_valid && id_ebreak;

  // MEM stage: Load address misaligned
  wire mem_load_halfword = (mem_funct3 == FUNCT3_LH) || (mem_funct3 == FUNCT3_LHU);
  wire mem_load_word = (mem_funct3 == FUNCT3_LW) || (mem_funct3 == FUNCT3_LWU);
  wire mem_load_doubleword = (mem_funct3 == FUNCT3_LD);
  wire mem_load_misaligned = mem_valid && mem_read &&
                              ((mem_load_halfword && mem_addr[0]) ||
                               (mem_load_word && (mem_addr[1:0] != 2'b00)) ||
                               (mem_load_doubleword && (mem_addr[2:0] != 3'b000)));

  // MEM stage: Store address misaligned
  wire mem_store_halfword = (mem_funct3 == FUNCT3_SH);
  wire mem_store_word = (mem_funct3 == FUNCT3_SW);
  wire mem_store_doubleword = (mem_funct3 == FUNCT3_SD);
  wire mem_store_misaligned = mem_valid && mem_write &&
                               ((mem_store_halfword && mem_addr[0]) ||
                                (mem_store_word && (mem_addr[1:0] != 2'b00)) ||
                                (mem_store_doubleword && (mem_addr[2:0] != 3'b000)));

  // =========================================================================
  // Exception Priority Encoder
  // =========================================================================
  // Priority (highest to lowest):
  // 1. Instruction address misaligned (IF)
  // 2. Illegal instruction (ID)
  // 3. EBREAK (ID)
  // 4. ECALL (ID)
  // 5. Load address misaligned (MEM)
  // 6. Store address misaligned (MEM)

  always @(*) begin
    // Default: no exception
    exception = 1'b0;
    exception_code = 5'd0;
    exception_pc = {XLEN{1'b0}};
    exception_val = {XLEN{1'b0}};

    // Priority encoder (highest priority first)
    if (if_inst_misaligned) begin
      exception = 1'b1;
      exception_code = CAUSE_INST_ADDR_MISALIGNED;
      exception_pc = if_pc;
      exception_val = if_pc;

    end else if (id_ebreak_exc) begin
      exception = 1'b1;
      exception_code = CAUSE_BREAKPOINT;
      exception_pc = id_pc;
      exception_val = id_pc;

    end else if (id_ecall_exc) begin
      exception = 1'b1;
      exception_code = CAUSE_ECALL_FROM_M_MODE;  // M-mode only for now
      exception_pc = id_pc;
      exception_val = {XLEN{1'b0}};

    end else if (id_illegal) begin
      exception = 1'b1;
      exception_code = CAUSE_ILLEGAL_INST;
      exception_pc = id_pc;
      exception_val = {{(XLEN-32){1'b0}}, id_instruction};  // Zero-extend instruction to XLEN

    end else if (mem_load_misaligned) begin
      exception = 1'b1;
      exception_code = CAUSE_LOAD_ADDR_MISALIGNED;
      exception_pc = mem_pc;
      exception_val = mem_addr;

    end else if (mem_store_misaligned) begin
      exception = 1'b1;
      exception_code = CAUSE_STORE_ADDR_MISALIGNED;
      exception_pc = mem_pc;
      exception_val = mem_addr;

    end
  end

endmodule
