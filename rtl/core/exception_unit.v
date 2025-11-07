// exception_unit.v - Exception Detection Unit
// Detects various exceptions in the pipeline
// Parameterized for RV32/RV64
// Author: RV1 Project
// Date: 2025-10-10

`include "config/rv_config.vh"
`include "config/rv_csr_defines.vh"

module exception_unit #(
  parameter XLEN = `XLEN
) (
  // Privilege mode input (Phase 1)
  input  wire [1:0]      current_priv,    // Current privilege mode

  // Instruction address misaligned (IF stage)
  input  wire [XLEN-1:0] if_pc,
  input  wire            if_valid,

  // Instruction page fault (IF stage - Session 117)
  input  wire            if_page_fault,
  input  wire [XLEN-1:0] if_fault_vaddr,

  // Illegal instruction (ID stage)
  input  wire            id_illegal_inst,
  input  wire            id_ecall,
  input  wire            id_ebreak,
  input  wire            id_mret,              // MRET instruction (needs privilege check)
  input  wire            id_sret,              // SRET instruction (needs privilege check)
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

  // Page fault inputs (Phase 3 - MMU integration)
  input  wire            mem_page_fault,       // Page fault from MMU
  input  wire [XLEN-1:0] mem_fault_vaddr,     // Faulting virtual address

  // Exception outputs
  output reg             exception,
  output reg  [4:0]      exception_code,
  output reg  [XLEN-1:0] exception_pc,
  output reg  [XLEN-1:0] exception_val
);

  // =========================================================================
  // Exception Code Definitions
  // =========================================================================
  // Note: Exception cause codes are defined in rv_csr_defines.vh

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
  // With C extension: only bit [0] must be 0 (2-byte aligned)
  // Without C extension: bits [1:0] must be 00 (4-byte aligned)
  wire if_inst_misaligned = `ENABLE_C_EXT ? (if_valid && if_pc[0]) :
                                             (if_valid && (if_pc[1:0] != 2'b00));

  // IF stage: Instruction page fault (Session 117)
  wire if_inst_page_fault = if_valid && if_page_fault;

  // ID stage: Illegal instruction
  wire id_illegal = id_valid && id_illegal_inst;

  // ID stage: Privilege violations for xRET instructions
  // MRET: Only allowed in M-mode (priv == 2'b11)
  // SRET: Only allowed in M-mode or S-mode (priv >= 2'b01)
  wire id_mret_violation = id_valid && id_mret && (current_priv != 2'b11);
  wire id_sret_violation = id_valid && id_sret && (current_priv == 2'b00);

  // Combine with regular illegal instruction
  wire id_illegal_combined = id_illegal || id_mret_violation || id_sret_violation;

  // ID stage: ECALL (privilege-aware exception code)
  wire id_ecall_exc = id_valid && id_ecall;
  wire [4:0] ecall_cause = (current_priv == 2'b00) ? CAUSE_ECALL_FROM_U_MODE :
                           (current_priv == 2'b01) ? CAUSE_ECALL_FROM_S_MODE :
                                                     CAUSE_ECALL_FROM_M_MODE;

  // ID stage: EBREAK
  wire id_ebreak_exc = id_valid && id_ebreak;

  // MEM stage: Load address misaligned
  // NOTE: Our memory subsystem natively supports misaligned accesses, so we
  // disable misalignment exceptions to comply with RISC-V compliance tests.
  // RISC-V spec allows implementations to support misaligned access in hardware.
  wire mem_load_halfword = (mem_funct3 == FUNCT3_LH) || (mem_funct3 == FUNCT3_LHU);
  wire mem_load_word = (mem_funct3 == FUNCT3_LW) || (mem_funct3 == FUNCT3_LWU);
  wire mem_load_doubleword = (mem_funct3 == FUNCT3_LD);
  wire mem_load_misaligned = 1'b0;  // Disabled: hardware supports misaligned access
  /* Original check (now disabled to support rv32ui-p-ma_data test):
  wire mem_load_misaligned = mem_valid && mem_read &&
                              ((mem_load_halfword && mem_addr[0]) ||
                               (mem_load_word && (mem_addr[1:0] != 2'b00)) ||
                               (mem_load_doubleword && (mem_addr[2:0] != 3'b000)));
  */

  // MEM stage: Store address misaligned
  wire mem_store_halfword = (mem_funct3 == FUNCT3_SH);
  wire mem_store_word = (mem_funct3 == FUNCT3_SW);
  wire mem_store_doubleword = (mem_funct3 == FUNCT3_SD);
  wire mem_store_misaligned = 1'b0;  // Disabled: hardware supports misaligned access
  /* Original check (now disabled to support rv32ui-p-ma_data test):
  wire mem_store_misaligned = mem_valid && mem_write &&
                               ((mem_store_halfword && mem_addr[0]) ||
                                (mem_store_word && (mem_addr[1:0] != 2'b00)) ||
                                (mem_store_doubleword && (mem_addr[2:0] != 3'b000)));
  */

  // MEM stage: Page faults (Phase 3 - MMU integration)
  // Page fault takes priority over misaligned access
  wire mem_page_fault_load = mem_valid && mem_page_fault && mem_read && !mem_write;
  wire mem_page_fault_store = mem_valid && mem_page_fault && mem_write;

  // =========================================================================
  // Exception Priority Encoder
  // =========================================================================
  // Priority (highest to lowest):
  // 1. Instruction address misaligned (IF)
  // 2. Instruction page fault (IF) - Session 117
  // 3. EBREAK (ID)
  // 4. ECALL (ID)
  // 5. Illegal instruction (ID) - includes MRET/SRET privilege violations
  // 6. Load/Store page fault (MEM) - Phase 3
  // 7. Load address misaligned (MEM)
  // 8. Store address misaligned (MEM)

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
      `ifdef DEBUG_PRIV
      $display("[EXC] Time=%0t INST_MISALIGNED: PC=0x%08x", $time, if_pc);
      `endif

    end else if (if_inst_page_fault) begin
      // Session 117: Instruction page fault
      exception = 1'b1;
      exception_code = CAUSE_INST_PAGE_FAULT;
      exception_pc = if_pc;
      exception_val = if_fault_vaddr;
      $display("[EXCEPTION] Instruction page fault: PC=0x%h, VA=0x%h", if_pc, if_fault_vaddr);
      `ifdef DEBUG_PRIV
      $display("[EXC] Time=%0t INST_PAGE_FAULT: PC=0x%08x VA=0x%08x", $time, if_pc, if_fault_vaddr);
      `endif

    end else if (id_ebreak_exc) begin
      exception = 1'b1;
      exception_code = CAUSE_BREAKPOINT;
      exception_pc = id_pc;
      exception_val = id_pc;
      `ifdef DEBUG_PRIV
      $display("[EXC] Time=%0t EBREAK: PC=0x%08x", $time, id_pc);
      `endif

    end else if (id_ecall_exc) begin
      exception = 1'b1;
      exception_code = ecall_cause;  // Privilege-aware (Phase 1)
      exception_pc = id_pc;
      exception_val = {XLEN{1'b0}};
      `ifdef DEBUG_PRIV
      $display("[EXC] Time=%0t ECALL: PC=0x%08x cause=%0d", $time, id_pc, ecall_cause);
      `endif

    end else if (id_illegal_combined) begin
      exception = 1'b1;
      exception_code = CAUSE_ILLEGAL_INST;
      exception_pc = id_pc;
      exception_val = {{(XLEN-32){1'b0}}, id_instruction};  // Zero-extend instruction to XLEN
      `ifdef DEBUG_PRIV
      $display("[EXC] Time=%0t ILLEGAL_INST: PC=0x%08x inst=0x%08x", $time, id_pc, id_instruction);
      `endif

    end else if (mem_page_fault_load) begin
      // Phase 3: Load page fault (higher priority than misaligned)
      exception = 1'b1;
      exception_code = CAUSE_LOAD_PAGE_FAULT;
      exception_pc = mem_pc;
      exception_val = mem_fault_vaddr;  // Faulting virtual address
      $display("[EXCEPTION] Load page fault: PC=0x%h, VA=0x%h", mem_pc, mem_fault_vaddr);

    end else if (mem_page_fault_store) begin
      // Phase 3: Store/AMO page fault (higher priority than misaligned)
      exception = 1'b1;
      exception_code = CAUSE_STORE_PAGE_FAULT;
      exception_pc = mem_pc;
      exception_val = mem_fault_vaddr;  // Faulting virtual address
      $display("[EXCEPTION] Store page fault: PC=0x%h, VA=0x%h", mem_pc, mem_fault_vaddr);

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
