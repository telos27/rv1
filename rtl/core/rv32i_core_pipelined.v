// rv_core_pipelined.v - 5-Stage Pipelined RISC-V Processor Core
// Implements classic RISC pipeline: IF -> ID -> EX -> MEM -> WB
// Includes data forwarding and hazard detection
// Parameterized for RV32/RV64 support
// Author: RV1 Project
// Date: 2025-10-10

`include "config/rv_config.vh"
`include "config/rv_csr_defines.vh"

module rv_core_pipelined #(
  parameter XLEN = `XLEN,
  parameter RESET_VECTOR = {XLEN{1'b0}},
  parameter IMEM_SIZE = 4096,
  parameter DMEM_SIZE = 16384,
  parameter MEM_FILE = ""
) (
  input  wire             clk,
  input  wire             reset_n,

  // External interrupt inputs (from CLINT/PLIC)
  input  wire             mtip_in,       // Machine Timer Interrupt Pending
  input  wire             msip_in,       // Machine Software Interrupt Pending
  input  wire             meip_in,       // Machine External Interrupt Pending (from PLIC)
  input  wire             seip_in,       // Supervisor External Interrupt Pending (from PLIC)

  // Bus master interface (to memory interconnect)
  output wire             bus_req_valid,
  output wire [XLEN-1:0]  bus_req_addr,
  output wire [63:0]      bus_req_wdata,
  output wire             bus_req_we,
  output wire [2:0]       bus_req_size,
  input  wire             bus_req_ready,
  input  wire [63:0]      bus_req_rdata,

  output wire [XLEN-1:0]  pc_out,        // For debugging
  output wire [31:0]      instr_out      // For debugging (instructions always 32-bit)
);

  //==========================================================================
  // Pipeline Control Signals
  //==========================================================================
  wire stall_pc;           // Stall PC (from hazard detection)
  wire stall_ifid;         // Stall IF/ID register
  wire flush_ifid;         // Flush IF/ID register (branch misprediction)
  wire flush_idex;         // Flush ID/EX register (bubble insertion or branch)
  wire flush_idex_hazard;  // Flush from hazard detection (load-use)
  // ID stage forwarding control signals
  wire [2:0] id_forward_a;       // ID stage forward select for rs1 (3'b100=EX, 3'b010=MEM, 3'b001=WB, 3'b000=NONE)
  wire [2:0] id_forward_b;       // ID stage forward select for rs2
  wire [2:0] id_fp_forward_a;    // ID stage FP forward select for rs1
  wire [2:0] id_fp_forward_b;    // ID stage FP forward select for rs2
  wire [2:0] id_fp_forward_c;    // ID stage FP forward select for rs3

  // EX stage forwarding control signals
  wire [1:0] forward_a;          // EX stage forward select for ALU operand A (2'b10=MEM, 2'b01=WB, 2'b00=NONE)
  wire [1:0] forward_b;          // EX stage forward select for ALU operand B

  // Trap/exception control
  wire trap_flush;         // Flush pipeline on trap
  wire mret_flush;         // Flush pipeline on MRET
  wire sret_flush;         // Flush pipeline on SRET

  // Privilege mode tracking
  reg  [1:0] current_priv; // Current privilege mode: 00=U, 01=S, 11=M
  wire [1:0] trap_target_priv;  // Target privilege for trap
  wire [1:0] mpp;          // Machine Previous Privilege from MSTATUS
  wire       spp;          // Supervisor Previous Privilege from MSTATUS

  //==========================================================================
  // IF Stage Signals
  //==========================================================================
  wire [XLEN-1:0] pc_current;
  wire [XLEN-1:0] pc_next;
  wire [XLEN-1:0] pc_plus_4;
  wire [XLEN-1:0] pc_plus_2;
  wire [XLEN-1:0] pc_increment;      // +2 for compressed, +4 for normal
  wire [31:0]     if_instruction_raw; // Raw instruction from memory
  wire [31:0]     if_instruction;     // Final instruction (decompressed if needed)
  wire            if_is_compressed;   // Instruction is compressed
  wire            if_illegal_c_instr; // Illegal compressed instruction

  //==========================================================================
  // IF/ID Pipeline Register Outputs
  //==========================================================================
  wire [XLEN-1:0] ifid_pc;
  wire [31:0]     ifid_instruction;  // Instructions always 32-bit
  wire            ifid_valid;
  wire            ifid_is_compressed; // Was the instruction originally compressed?

  //==========================================================================
  // ID Stage Signals
  //==========================================================================
  // Decoder outputs
  wire [6:0]      id_opcode;
  wire [4:0]      id_rd, id_rs1, id_rs2;
  wire [2:0]      id_funct3;
  wire [6:0]      id_funct7;
  wire [XLEN-1:0] id_imm_i, id_imm_s, id_imm_b, id_imm_u, id_imm_j;
  wire            id_is_csr_dec;   // CSR instruction from decoder
  wire            id_is_ecall_dec; // ECALL from decoder
  wire            id_is_ebreak_dec; // EBREAK from decoder
  wire            id_is_mret_dec;   // MRET from decoder
  wire            id_is_sret_dec;   // SRET from decoder
  wire            id_is_sfence_vma_dec; // SFENCE.VMA from decoder
  wire            id_is_mul_div_dec; // M extension instruction from decoder
  wire [3:0]      id_mul_div_op_dec; // M extension operation from decoder
  wire            id_is_word_op_dec; // RV64M word operation from decoder
  wire            id_is_atomic_dec;  // A extension instruction from decoder
  wire [4:0]      id_funct5_dec;     // funct5 field from decoder (atomic op)
  wire            id_aq_dec;         // Acquire bit from decoder
  wire            id_rl_dec;         // Release bit from decoder
  wire [4:0]      id_rs3;            // Third source register (FMA)
  wire            id_is_fp;          // F/D extension instruction from decoder
  wire            id_is_fp_load;     // FP load instruction
  wire            id_is_fp_store;    // FP store instruction
  wire            id_is_fp_op;       // FP computational operation
  wire            id_is_fp_fma;      // FP FMA instruction
  wire [2:0]      id_fp_rm;          // FP rounding mode from instruction
  wire            id_fp_fmt;         // FP format: 0=single, 1=double

  // Control signals
  wire        id_reg_write;
  wire        id_mem_read;
  wire        id_mem_write;
  wire        id_branch;
  wire        id_jump;
  wire [3:0]  id_alu_control;
  wire        id_alu_src;
  wire [2:0]  id_wb_sel;
  wire [2:0]  id_imm_sel;

  // CSR signals
  wire [11:0]     id_csr_addr;
  wire [4:0]      id_csr_uimm;
  wire            id_csr_we;
  wire            id_csr_src;
  wire [XLEN-1:0] id_csr_wdata;

  // Exception signals
  wire            id_is_ecall;
  wire            id_is_ebreak;
  wire            id_is_mret;
  wire            id_is_sret;
  wire            id_is_sfence_vma;
  wire            id_illegal_inst_from_control; // Illegal from control unit only
  wire            id_illegal_inst;               // Combined illegal (control + RVC)

  // Register file outputs
  wire [XLEN-1:0] id_rs1_data;
  wire [XLEN-1:0] id_rs2_data;

  // FP control signals from control unit
  wire            id_fp_reg_write;    // FP register write enable
  wire            id_int_reg_write_fp;// Integer register write (FP compare/classify/FMV.X.W)
  wire            id_fp_mem_op;       // FP memory operation
  wire            id_fp_alu_en;       // FP ALU enable
  wire [4:0]      id_fp_alu_op;       // FP ALU operation
  wire            id_fp_use_dynamic_rm; // Use dynamic rounding mode from frm CSR

  // FP register file outputs
  wire [`FLEN-1:0] id_fp_rs1_data;
  wire [`FLEN-1:0] id_fp_rs2_data;
  wire [`FLEN-1:0] id_fp_rs3_data;
  wire [`FLEN-1:0] id_fp_rs1_data_raw; // Raw FP register file output
  wire [`FLEN-1:0] id_fp_rs2_data_raw;
  wire [`FLEN-1:0] id_fp_rs3_data_raw;

  // Immediate selection
  wire [XLEN-1:0] id_immediate;

  //==========================================================================
  // ID/EX Pipeline Register Outputs
  //==========================================================================
  wire [XLEN-1:0] idex_pc;
  wire [XLEN-1:0] idex_rs1_data;
  wire [XLEN-1:0] idex_rs2_data;
  wire [4:0]      idex_rs1_addr;
  wire [4:0]      idex_rs2_addr;
  wire [4:0]      idex_rd_addr;
  wire [XLEN-1:0] idex_imm;
  wire [6:0]      idex_opcode;
  wire [2:0]      idex_funct3;
  wire [6:0]      idex_funct7;
  wire [3:0]      idex_alu_control;
  wire            idex_alu_src;
  wire            idex_branch;
  wire            idex_jump;
  wire            idex_mem_read;
  wire            idex_mem_write;
  wire            idex_reg_write;
  wire [2:0]      idex_wb_sel;
  wire            idex_valid;
  wire            idex_is_mul_div;
  wire [3:0]      idex_mul_div_op;
  wire            idex_is_word_op;
  wire            idex_is_atomic;
  wire [4:0]      idex_funct5;
  wire            idex_aq;
  wire            idex_rl;
  wire [`FLEN-1:0] idex_fp_rs1_data;
  wire [`FLEN-1:0] idex_fp_rs2_data;
  wire [`FLEN-1:0] idex_fp_rs3_data;
  wire [4:0]      idex_fp_rs1_addr;
  wire [4:0]      idex_fp_rs2_addr;
  wire [4:0]      idex_fp_rs3_addr;
  wire [4:0]      idex_fp_rd_addr;
  wire            idex_fp_reg_write;
  wire            idex_int_reg_write_fp;
  wire            idex_fp_mem_op;
  wire            idex_fp_alu_en;
  wire [4:0]      idex_fp_alu_op;
  wire [2:0]      idex_fp_rm;
  wire            idex_fp_use_dynamic_rm;
  wire            idex_fp_fmt;
  wire [11:0]     idex_csr_addr;
  wire            idex_csr_we;
  wire            idex_csr_src;
  wire [XLEN-1:0] idex_csr_wdata;
  wire            idex_is_csr;
  wire            idex_is_ecall;
  wire            idex_is_ebreak;
  wire            idex_is_mret;
  wire            idex_is_sret;
  wire            idex_is_sfence_vma;
  wire            idex_illegal_inst;
  wire [31:0]     idex_instruction;
  wire            idex_is_compressed;  // Bug #42: Track if instruction was compressed  // Instructions always 32-bit

  //==========================================================================
  // EX Stage Signals
  //==========================================================================
  wire [XLEN-1:0] ex_alu_operand_a;
  wire [XLEN-1:0] ex_alu_operand_b;
  wire [XLEN-1:0] ex_alu_operand_a_forwarded;
  wire [XLEN-1:0] ex_alu_operand_b_forwarded;
  wire [XLEN-1:0] ex_alu_result;
  wire            ex_alu_zero;
  wire            ex_alu_lt;
  wire            ex_alu_ltu;
  wire            ex_take_branch;
  wire [XLEN-1:0] ex_branch_target;
  wire [XLEN-1:0] ex_jump_target;
  wire [XLEN-1:0] ex_pc_plus_4;
  wire [XLEN-1:0] ex_csr_rdata;       // CSR read data
  wire            ex_illegal_csr;     // Illegal CSR access

  // M extension signals
  wire [XLEN-1:0] ex_mul_div_result;
  wire            ex_mul_div_busy;
  wire            ex_mul_div_ready;

  // F/D extension signals
  wire [`FLEN-1:0] ex_fp_operand_a;        // FP operand A (potentially forwarded)
  wire [`FLEN-1:0] ex_fp_operand_b;        // FP operand B (potentially forwarded)
  wire [`FLEN-1:0] ex_fp_operand_c;        // FP operand C (potentially forwarded, for FMA)
  wire [`FLEN-1:0] ex_fp_result;           // FP result from FPU
  wire [XLEN-1:0] ex_int_result_fp;       // Integer result from FP ops (compare/classify/FMV.X.W)
  wire            ex_fpu_busy;             // FPU busy signal
  wire            ex_fpu_done;             // FPU done signal
  wire [2:0]      ex_fp_rounding_mode;     // Final rounding mode (from instruction or frm CSR)
  wire            ex_fp_flag_nv;           // FP exception flags
  wire            ex_fp_flag_dz;
  wire            ex_fp_flag_of;
  wire            ex_fp_flag_uf;
  wire            ex_fp_flag_nx;
  wire [1:0]      fp_forward_a;            // FP forwarding control signals
  wire [1:0]      fp_forward_b;
  wire [1:0]      fp_forward_c;

  // Hold EX/MEM register when M instruction or A instruction or FP instruction or MMU is executing
  wire            hold_exmem;
  assign hold_exmem = (idex_is_mul_div && idex_valid && !ex_mul_div_ready) ||
                      (idex_is_atomic && idex_valid && !ex_atomic_done) ||
                      (idex_fp_alu_en && idex_valid && !ex_fpu_done) ||
                      mmu_busy;  // Phase 3: Stall on MMU page table walk

  // M unit start signal: pulse once when M instruction first enters EX
  // Only start if not already busy or ready (prevents restarting)
  wire            m_unit_start;
  assign m_unit_start = idex_is_mul_div && idex_valid && !ex_mul_div_busy && !ex_mul_div_ready;

  // FPU start signal: pulse once when FP instruction first enters EX
  // Start FPU when: (1) FP ALU op enabled, (2) valid instruction, (3) FPU not busy
  // Note: Don't check !ex_fpu_done here - done is a completion flag, not a busy flag
  wire            fpu_start;
  assign fpu_start = idex_fp_alu_en && idex_valid && !ex_fpu_busy;

  `ifdef DEBUG_FPU
  always @(posedge clk) begin
    if (fpu_start) begin
      $display("[CORE] FPU START: PC=%h fp_alu_op=%0d rs1=%0d rs2=%0d rs3=%0d rd=%0d",
               idex_pc, idex_fp_alu_op, idex_rs1_addr, idex_rs2_addr, idex_fp_rs3_addr, idex_rd_addr);
      $display("       FP operands: a=%h b=%h c=%h", ex_fp_operand_a, ex_fp_operand_b, ex_fp_operand_c);
      $display("       INT operand: int_operand=%h (ex_alu_operand_a_forwarded)", ex_alu_operand_a_forwarded);
      $display("       INT rs1 data: idex_rs1_data=%h, forward_a=%b", idex_rs1_data, forward_a);
    end
    if (idex_valid && (idex_opcode == 7'b1010011)) begin  // FP opcode
      $display("[FP_DECODE] PC=%h instr=%h opcode=%b funct7=%b rs2=%d fp_alu_en=%b fpu_busy=%b",
               idex_pc, idex_instruction, idex_opcode, idex_funct7, idex_rs2_addr, idex_fp_alu_en, ex_fpu_busy);
    end
    // Trace all branches to understand control flow
    if (idex_valid && (idex_branch || idex_jump)) begin
      $display("[BRANCH] PC=%h instr=%h branch=%b jump=%b take=%b target=%h",
               idex_pc, idex_instruction, idex_branch, idex_jump, ex_take_branch,
               idex_branch ? ex_branch_target : ex_jump_target);
      if (idex_branch) begin
        $display("         rs1_data=%h (x%0d fwd=%b) rs2_data=%h (x%0d fwd=%b)",
                 ex_alu_operand_a_forwarded, idex_rs1_addr, forward_a,
                 ex_rs2_data_forwarded, idex_rs2_addr, forward_b);
        $display("         exmem: rd=x%0d reg_wr=%b int_wr_fp=%b alu_res=%h int_res_fp=%h fwd_data=%h",
                 exmem_rd_addr, exmem_reg_write, exmem_int_reg_write_fp, exmem_alu_result, exmem_int_result_fp, exmem_forward_data);
        $display("         memwb: rd=x%0d reg_wr=%b int_wr_fp=%b wb_data=%h",
                 memwb_rd_addr, memwb_reg_write, memwb_int_reg_write_fp, wb_data);
      end
    end
    // Trace gp writes to track test progress
    if (memwb_reg_write && (memwb_rd_addr == 3)) begin
      $display("[GP_WRITE] GP <= %h (test number)", wb_data);
    end
    // Trace FP-to-INT writebacks
    if (memwb_int_reg_write_fp && memwb_reg_write) begin
      $display("[WB_FP2INT] x%0d <= %h (wb_sel=%b int_result_fp=%h wb_data=%h)",
               memwb_rd_addr, wb_data, memwb_wb_sel, memwb_int_result_fp, wb_data);
    end
  end
  `endif

  // Debug: FPU Execution (specifically for FCVT debugging)
  `ifdef DEBUG_FPU_EXEC
  always @(posedge clk) begin
    if (fpu_start) begin
      $display("[%0t] [FPU] START: op=%0d, rs1=f%0d, rs2=%0d, rd=f%0d, pc=%h",
               $time, idex_fp_alu_op, idex_fp_rs1_addr, idex_fp_rs2_addr, idex_fp_rd_addr, idex_pc);
      if (idex_fp_alu_op == 5'b01010) begin  // FP_CVT
        $display("[%0t] [FPU] FCVT START: fp_operand_a=%h, int_operand=%h",
                 $time, ex_fp_operand_a, ex_alu_operand_a_forwarded);
      end
    end
    if (ex_fpu_done) begin
      $display("[%0t] [FPU] DONE: result=%h, busy=%b, pc=%h",
               $time, ex_fp_result, ex_fpu_busy, idex_pc);
    end
  end
  `endif

  //==========================================================================
  // EX/MEM Pipeline Register Outputs
  //==========================================================================
  wire [XLEN-1:0] exmem_alu_result;
  wire [XLEN-1:0] exmem_mem_write_data;      // Integer store data
  wire [`FLEN-1:0] exmem_fp_mem_write_data;  // FP store data
  wire [4:0]      exmem_rd_addr;
  wire [XLEN-1:0] exmem_pc_plus_4;
  wire [2:0]      exmem_funct3;
  wire            exmem_mem_read;
  wire            exmem_mem_write;
  wire            exmem_reg_write;
  wire [2:0]      exmem_wb_sel;
  wire            exmem_valid;
  wire [XLEN-1:0] exmem_mul_div_result;
  wire [XLEN-1:0] exmem_atomic_result;
  wire            exmem_is_atomic;
  wire [`FLEN-1:0] exmem_fp_result;
  wire [XLEN-1:0] exmem_int_result_fp;
  wire [4:0]      exmem_fp_rd_addr;
  wire            exmem_fp_reg_write;
  wire            exmem_int_reg_write_fp;
  wire            exmem_fp_mem_op;
  wire            exmem_fp_fmt;
  wire            exmem_fp_flag_nv;
  wire            exmem_fp_flag_dz;
  wire            exmem_fp_flag_of;
  wire            exmem_fp_flag_uf;
  wire            exmem_fp_flag_nx;
  wire [11:0]     exmem_csr_addr;
  wire            exmem_csr_we;
  wire [XLEN-1:0] exmem_csr_rdata;
  wire            exmem_is_mret;
  wire            exmem_is_sret;
  wire            exmem_is_sfence_vma;
  wire [4:0]      exmem_rs1_addr;
  wire [4:0]      exmem_rs2_addr;
  wire [XLEN-1:0] exmem_rs1_data;
  wire [31:0]     exmem_instruction;  // Instructions always 32-bit
  wire [XLEN-1:0] exmem_pc;

  //==========================================================================
  // MEM Stage Signals
  //==========================================================================
  wire [XLEN-1:0] mem_read_data;      // Integer load data (lower bits)
  wire [`FLEN-1:0] fp_mem_read_data;  // FP load data (full 64-bit for RV32D)

  //==========================================================================
  // MMU Signals (Phase 3)
  //==========================================================================
  // MMU translation request
  wire            mmu_req_valid;
  wire [XLEN-1:0] mmu_req_vaddr;
  wire            mmu_req_is_store;
  wire            mmu_req_is_fetch;
  wire [2:0]      mmu_req_size;
  wire            mmu_req_ready;
  wire [XLEN-1:0] mmu_req_paddr;
  wire            mmu_req_page_fault;
  wire [XLEN-1:0] mmu_req_fault_vaddr;

  // MMU page table walk memory interface
  wire            mmu_ptw_req_valid;
  wire [XLEN-1:0] mmu_ptw_req_addr;
  wire            mmu_ptw_req_ready;
  wire [XLEN-1:0] mmu_ptw_resp_data;
  wire            mmu_ptw_resp_valid;

  // TLB flush control
  wire            tlb_flush_all;
  wire            tlb_flush_vaddr;
  wire [XLEN-1:0] tlb_flush_addr;
  wire            mmu_busy;  // MMU is busy (page table walk in progress)

  //==========================================================================
  // MEM/WB Pipeline Register Outputs
  //==========================================================================
  wire [XLEN-1:0] memwb_alu_result;
  wire [XLEN-1:0] memwb_mem_read_data;       // Integer load data
  wire [`FLEN-1:0] memwb_fp_mem_read_data;   // FP load data
  wire [4:0]      memwb_rd_addr;
  wire [XLEN-1:0] memwb_pc_plus_4;
  wire            memwb_reg_write;
  wire [2:0]      memwb_wb_sel;
  wire            memwb_valid;
  wire [XLEN-1:0] memwb_mul_div_result;
  wire [XLEN-1:0] memwb_atomic_result;
  wire [`FLEN-1:0] memwb_fp_result;
  wire [XLEN-1:0] memwb_int_result_fp;
  wire [4:0]      memwb_fp_rd_addr;
  wire            memwb_fp_reg_write;
  wire            memwb_int_reg_write_fp;
  wire            memwb_fp_fmt;
  wire            memwb_fp_flag_nv;
  wire            memwb_fp_flag_dz;
  wire            memwb_fp_flag_of;
  wire            memwb_fp_flag_uf;
  wire            memwb_fp_flag_nx;
  wire [XLEN-1:0] memwb_csr_rdata;
  wire            memwb_csr_we;

  //==========================================================================
  // CSR and Exception Signals
  //==========================================================================
  wire            exception;
  wire [4:0]      exception_code;     // 5-bit exception code for mcause
  wire [XLEN-1:0] exception_pc;
  wire [XLEN-1:0] exception_val;

  // Registered exception signals to prevent glitches during trap handling
  // The exception unit outputs are combinational and can glitch during the clock cycle.
  // We register them to ensure stable values when the CSR file samples them.
  reg             exception_r;
  reg [4:0]       exception_code_r;
  reg [XLEN-1:0]  exception_pc_r;
  reg [XLEN-1:0]  exception_val_r;
  reg             exception_r_hold;  // Hold exception_r for one extra cycle
  reg [1:0]       exception_priv_r;  // Privilege mode when exception occurred
  reg [1:0]       exception_target_priv_r;  // Target privilege for trap (latched)

  // Gate exception signal to prevent propagation to subsequent instructions
  // Once exception_r is latched, ignore new exceptions until fully processed
  wire exception_gated = exception && !exception_r && !exception_taken_r;

  // Compute trap target privilege for the CURRENT exception (not latched)
  // This must use the un-latched exception_code and current_priv to get correct delegation
  function [1:0] compute_trap_target;
    input [4:0] cause;
    input [1:0] curr_priv;
    input [XLEN-1:0] medeleg;
    begin
      `ifdef DEBUG_EXCEPTION
      $display("[CORE_DELEG] compute_trap_target: cause=%0d curr_priv=%b medeleg=%h medeleg[cause]=%b",
               cause, curr_priv, medeleg, medeleg[cause]);
      `endif
      // M-mode traps never delegate
      if (curr_priv == 2'b11) begin
        compute_trap_target = 2'b11;  // M-mode
        `ifdef DEBUG_EXCEPTION
        $display("[CORE_DELEG] -> M-mode (curr_priv==M)");
        `endif
      end
      // Check if exception is delegated to S-mode
      else if (medeleg[cause] && (curr_priv <= 2'b01)) begin
        compute_trap_target = 2'b01;  // S-mode
        `ifdef DEBUG_EXCEPTION
        $display("[CORE_DELEG] -> S-mode (delegated)");
        `endif
      end
      else begin
        compute_trap_target = 2'b11;  // M-mode (default)
        `ifdef DEBUG_EXCEPTION
        $display("[CORE_DELEG] -> M-mode (no delegation)");
        `endif
      end
    end
  endfunction

  // Compute target privilege from current (un-latched) exception
  wire [1:0] current_trap_target = compute_trap_target(exception_code, current_priv, medeleg);

  // Exception signal registration
  // Latch exception signals when exception first occurs, hold for one cycle
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      exception_r            <= 1'b0;
      exception_code_r       <= 5'd0;
      exception_pc_r         <= {XLEN{1'b0}};
      exception_val_r        <= {XLEN{1'b0}};
      exception_r_hold       <= 1'b0;
      exception_priv_r       <= 2'b11;  // Default to M-mode
      exception_target_priv_r <= 2'b11;  // Default to M-mode
    end else begin
      // Latch exception info when exception FIRST asserts (using gated signal)
      if (exception_gated) begin
        exception_r            <= 1'b1;  // Will pulse for one cycle
        exception_code_r       <= exception_code;
        exception_pc_r         <= exception_pc;
        exception_val_r        <= exception_val;
        exception_priv_r       <= current_priv;  // Latch current privilege at time of exception
        exception_target_priv_r <= current_trap_target;  // Use computed target (not CSR's trap_target_priv)
        exception_r_hold       <= 1'b0;
        `ifdef DEBUG_EXCEPTION
        $display("[EXC_LATCH] Latching exception code=%0d PC=%h priv=%b target=%b (exception=%b taken=%b)",
                 exception_code, exception_pc, current_priv, current_trap_target, exception, exception_taken_r);
        `endif
      end else begin
        // Clear exception_r after one cycle
        exception_r      <= 1'b0;
        exception_r_hold <= exception_r;  // Track previous value for clearing exception_taken_r
      end
    end
  end

  wire [XLEN-1:0] trap_vector;
  wire [XLEN-1:0] mepc;
  wire [XLEN-1:0] sepc;
  wire            mstatus_sum;  // MSTATUS.SUM bit (for MMU)
  wire            mstatus_mxr;  // MSTATUS.MXR bit (for MMU)
  wire [XLEN-1:0] satp;         // SATP register (for MMU)
  wire [XLEN-1:0] csr_satp;     // Alias for MMU
  wire            mstatus_mie;
  wire            mstatus_sie;
  wire            mstatus_mpie;
  wire            mstatus_spie;
  wire [2:0]      csr_frm;            // FP rounding mode from frm CSR
  wire [4:0]      csr_fflags;         // FP exception flags from fflags CSR
  wire [XLEN-1:0] medeleg;            // Machine exception delegation register
  wire [XLEN-1:0] mip;                // Machine Interrupt Pending register
  wire [XLEN-1:0] mie;                // Machine Interrupt Enable register
  wire [XLEN-1:0] mideleg;            // Machine Interrupt Delegation register
  // Note: csr_frm and csr_fflags are now connected to CSR file outputs

  //==========================================================================
  // WB Stage Signals
  //==========================================================================
  wire [XLEN-1:0] wb_data;
  wire [`FLEN-1:0] wb_fp_data;         // FP write-back data

  //==========================================================================
  // Debug outputs
  //==========================================================================
  assign pc_out = pc_current;
  assign instr_out = if_instruction;

  //==========================================================================
  // IF STAGE: Instruction Fetch
  //==========================================================================

  // PC calculation (support both 2-byte and 4-byte increments for C extension)
  assign pc_plus_2 = pc_current + 32'd2;
  assign pc_plus_4 = pc_current + 32'd4;
  assign pc_increment = if_is_compressed ? pc_plus_2 : pc_plus_4;

  // Trap and xRET handling
  // Use GATED exception for immediate flush to prevent next instruction from executing
  // The exception_gated signal prevents propagation to subsequent instructions
  // Note: We use exception_gated (not exception_r) to get 0-cycle trap latency

  // xRET flushes unconditionally when in MEM stage - has priority over exceptions
  // This prevents spurious exceptions from instructions fetched after xRET
  assign mret_flush = exmem_is_mret && exmem_valid;  // MRET in MEM stage
  assign sret_flush = exmem_is_sret && exmem_valid;  // SRET in MEM stage

  // Trap flush only if not executing xRET (xRET has priority)
  assign trap_flush = exception_gated && !mret_flush && !sret_flush;

  // Track exception to prevent re-triggering
  // Set when exception first occurs, clear one cycle after trap flush
  reg exception_taken_r;
  reg trap_flush_r;  // Register trap_flush for clearing exception_taken_r
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      exception_taken_r <= 1'b0;
      trap_flush_r <= 1'b0;
    end else begin
      trap_flush_r <= trap_flush;  // Latch trap_flush
      if (exception_gated)
        exception_taken_r <= 1'b1;  // Set on first exception (using gated signal)
      else if (trap_flush_r)
        exception_taken_r <= 1'b0;  // Clear one cycle after trap flush
    end
  end

  //==========================================================================
  // Privilege Mode Tracking
  //==========================================================================
  // Privilege mode state machine: updates on trap entry and xRET
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      current_priv <= 2'b11;  // Start in Machine mode on reset
    end else begin
      if (trap_flush) begin
        // On trap entry, move to target privilege level
        // With 0-cycle trap latency, use current (un-latched) target privilege
        current_priv <= current_trap_target;
        `ifdef DEBUG_PRIV
        $display("[PRIV] Time=%0t TRAP: priv %b -> %b (current)", $time, current_priv, current_trap_target);
        `endif
      end else if (mret_flush) begin
        // On MRET, restore privilege from MSTATUS.MPP
        current_priv <= mpp;
        `ifdef DEBUG_PRIV
        $display("[PRIV] Time=%0t MRET: priv %b -> %b (from MPP) mepc=0x%08x", $time, current_priv, mpp, mepc);
        `endif
      end else if (sret_flush) begin
        // On SRET, restore privilege from MSTATUS.SPP
        current_priv <= {1'b0, spp};  // SPP: 0=U, 1=S -> {1'b0, spp} = 00 or 01
        `ifdef DEBUG_PRIV
        $display("[PRIV] Time=%0t SRET: priv %b -> %b (from SPP=%b)", $time, current_priv, {1'b0, spp}, spp);
        `endif
      end
    end
  end

  // PC selection: priority order - trap > mret > sret > branch/jump > PC+increment
  // Note: Branches/jumps can target 2-byte aligned addresses (for C extension)
  assign pc_next = trap_flush ? trap_vector :
                   mret_flush ? mepc :
                   sret_flush ? sepc :
                   ex_take_branch ? (idex_jump ? ex_jump_target : ex_branch_target) :
                   pc_increment;

  // Pipeline flush: trap/xRET flushes all stages, branch flushes IF/ID and ID/EX
  assign flush_ifid = trap_flush | mret_flush | sret_flush | ex_take_branch;
  assign flush_idex = trap_flush | mret_flush | sret_flush | flush_idex_hazard | ex_take_branch;

  // PC stall control: override stall on flush (trap/xRET/branch)
  // When a control flow change occurs, PC MUST update regardless of hazards
  wire pc_stall_gated;
  assign pc_stall_gated = stall_pc && !(trap_flush | mret_flush | sret_flush | ex_take_branch);

  // Program Counter
  pc #(
    .XLEN(XLEN),
    .RESET_VECTOR(RESET_VECTOR)
  ) pc_inst (
    .clk(clk),
    .reset_n(reset_n),
    .stall(pc_stall_gated),
    .pc_next(pc_next),
    .pc_current(pc_current)
  );

  // Instruction Memory (writable for FENCE.I support)
  // IMEM write enable - only for addresses in IMEM range (0x0-0xFFFF for 64KB IMEM)
  // This prevents DMEM stores (e.g., 0x80000000) from corrupting IMEM
  wire imem_write_enable = exmem_mem_write && exmem_valid && !exception &&
                           (exmem_alu_result < IMEM_SIZE);

  instruction_memory #(
    .XLEN(XLEN),
    .MEM_SIZE(IMEM_SIZE),
    .MEM_FILE(MEM_FILE)
  ) imem (
    .clk(clk),
    .addr(pc_current),
    .instruction(if_instruction_raw),
    // Write interface for self-modifying code (FENCE.I)
    .mem_write(imem_write_enable),
    .write_addr(exmem_alu_result),
    .write_data(exmem_mem_write_data),
    .funct3(exmem_funct3)
  );

  // RVC Decoder (C Extension - Compressed Instruction Decompressor)
  // Detects and expands 16-bit compressed instructions to 32-bit equivalents
  // For the C extension, we need to select the correct 16 bits based on PC alignment
  wire [15:0] if_compressed_instr_candidate;
  wire [31:0] if_instruction_decompressed;

  // RISC-V C extension: Compressed instructions are identified by bits [1:0] != 11
  // The instruction memory fetches 32 bits starting at halfword-aligned address.
  // Since halfword_addr = {PC[XLEN-1:1], 1'b0}, the fetch always starts at an even address.
  // The instruction at PC always starts in the LOWER 16 bits of the fetched word!
  // - When PC is 2-byte aligned (PC = 0, 2, 4, 6, 8, a, c, e, ...): bits [15:0]
  // - The upper 16 bits [31:16] contain the NEXT potential 16-bit instruction
  //
  // BUG FIX: Always use lower 16 bits and check bits [1:0] for compression detection
  assign if_compressed_instr_candidate = if_instruction_raw[15:0];

  // Detect if instruction is compressed by checking bits [1:0] of lower 16 bits
  wire if_instr_is_compressed = (if_instruction_raw[1:0] != 2'b11);

  rvc_decoder #(
    .XLEN(XLEN)
  ) rvc_dec (
    .compressed_instr(if_compressed_instr_candidate),
    .is_rv64(XLEN == 64),
    .decompressed_instr(if_instruction_decompressed),
    .illegal_instr(if_illegal_c_instr),
    .is_compressed_out() // Not used, we compute it ourselves
  );

  // Use our corrected compression detection
  assign if_is_compressed = if_instr_is_compressed;

  // Select final instruction: decompressed if compressed, otherwise full 32-bit from memory
  assign if_instruction = if_is_compressed ? if_instruction_decompressed : if_instruction_raw;

  // IF/ID Pipeline Register
  ifid_register #(
    .XLEN(XLEN)
  ) ifid_reg (
    .clk(clk),
    .reset_n(reset_n),
    .stall(stall_ifid),
    .flush(flush_ifid),
    .pc_in(pc_current),
    .instruction_in(if_instruction),    // Already decompressed if it was compressed
    .is_compressed_in(if_is_compressed),
    .pc_out(ifid_pc),
    .instruction_out(ifid_instruction),
    .valid_out(ifid_valid),
    .is_compressed_out(ifid_is_compressed)
  );

  //==========================================================================
  // ID STAGE: Instruction Decode
  //==========================================================================

  // Instruction Decoder
  decoder #(
    .XLEN(XLEN)
  ) decoder_inst (
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
    .imm_j(id_imm_j),
    .csr_addr(id_csr_addr),
    .csr_uimm(id_csr_uimm),
    .is_csr(id_is_csr_dec),
    .is_ecall(id_is_ecall_dec),
    .is_ebreak(id_is_ebreak_dec),
    .is_mret(id_is_mret_dec),
    .is_sret(id_is_sret_dec),
    .is_sfence_vma(id_is_sfence_vma_dec),
    .is_mul_div(id_is_mul_div_dec),
    .mul_div_op(id_mul_div_op_dec),
    .is_word_op(id_is_word_op_dec),
    // A extension outputs
    .is_atomic(id_is_atomic_dec),
    .funct5(id_funct5_dec),
    .aq(id_aq_dec),
    .rl(id_rl_dec),
    // F/D extension outputs
    .rs3(id_rs3),
    .is_fp(id_is_fp),
    .is_fp_load(id_is_fp_load),
    .is_fp_store(id_is_fp_store),
    .is_fp_op(id_is_fp_op),
    .is_fp_fma(id_is_fp_fma),
    .fp_rm(id_fp_rm),
    .fp_fmt(id_fp_fmt)
  );

  // M extension control signals from control unit (not used directly, but available)
  wire        id_mul_div_en;       // M unit enable from control
  wire [3:0]  id_mul_div_op_ctrl;  // M operation from control (pass-through)
  wire        id_is_word_op_ctrl;  // Word-op from control (pass-through)

  // A extension control signals from control unit
  wire        id_atomic_en;        // A unit enable from control
  wire [4:0]  id_atomic_funct5;    // Atomic operation from control (pass-through)

  // Control Unit
  control #(
    .XLEN(XLEN)
  ) control_inst (
    .opcode(id_opcode),
    .funct3(id_funct3),
    .funct7(id_funct7),
    // Decoder special instruction flags
    .is_csr(id_is_csr_dec),
    .is_ecall(id_is_ecall_dec),
    .is_ebreak(id_is_ebreak_dec),
    .is_mret(id_is_mret_dec),
    .is_sret(id_is_sret_dec),
    .is_sfence_vma(id_is_sfence_vma_dec),
    .is_mul_div(id_is_mul_div_dec),
    .mul_div_op(id_mul_div_op_dec),
    .is_word_op(id_is_word_op_dec),
    .is_atomic(id_is_atomic_dec),
    .funct5(id_funct5_dec),
    // F/D extension inputs
    .is_fp(id_is_fp),
    .is_fp_load(id_is_fp_load),
    .is_fp_store(id_is_fp_store),
    .is_fp_op(id_is_fp_op),
    .is_fp_fma(id_is_fp_fma),
    // Note: fp_rm comes from decoder, not control
    // Standard outputs
    .reg_write(id_reg_write),
    .mem_read(id_mem_read),
    .mem_write(id_mem_write),
    .branch(id_branch),
    .jump(id_jump),
    .alu_control(id_alu_control),
    .alu_src(id_alu_src),
    .wb_sel(id_wb_sel),
    .imm_sel(id_imm_sel),
    .csr_we(id_csr_we),
    .csr_src(id_csr_src),
    // M extension outputs
    .mul_div_en(id_mul_div_en),
    .mul_div_op_out(id_mul_div_op_ctrl),
    .is_word_op_out(id_is_word_op_ctrl),
    // A extension outputs
    .atomic_en(id_atomic_en),
    .atomic_funct5(id_atomic_funct5),
    // F/D extension outputs
    .fp_reg_write(id_fp_reg_write),
    .int_reg_write_fp(id_int_reg_write_fp),
    .fp_mem_op(id_fp_mem_op),
    .fp_alu_en(id_fp_alu_en),
    .fp_alu_op(id_fp_alu_op),
    .fp_use_dynamic_rm(id_fp_use_dynamic_rm),
    .illegal_inst(id_illegal_inst_from_control)
  );

  // Combine illegal instruction signals from control unit and RVC decoder
  // Bug #29: Illegal compressed instructions were not being caught, causing PC corruption
  // Only check RVC illegal flag if the instruction was actually compressed (after pipelining through IFID)
  // Note: We need to buffer the illegal flag for one cycle to match the pipeline stage
  reg if_illegal_c_instr_buffered;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      if_illegal_c_instr_buffered <= 1'b0;
    else if (!stall_ifid && !flush_ifid)
      if_illegal_c_instr_buffered <= if_illegal_c_instr;
    else if (flush_ifid)
      if_illegal_c_instr_buffered <= 1'b0;  // Flush clears the illegal flag
  end

  assign id_illegal_inst = id_illegal_inst_from_control | (ifid_is_compressed & if_illegal_c_instr_buffered);

  // Pass through decoder flags for pipeline
  assign id_is_ecall = id_is_ecall_dec;
  assign id_is_ebreak = id_is_ebreak_dec;
  assign id_is_mret = id_is_mret_dec;
  assign id_is_sret = id_is_sret_dec;
  assign id_is_sfence_vma = id_is_sfence_vma_dec;

  // Register File
  wire [XLEN-1:0] id_rs1_data_raw;  // Raw register file output
  wire [XLEN-1:0] id_rs2_data_raw;  // Raw register file output

  // Writeback gating: Prevent flushed instructions from writing registers
  // Instructions that cause exceptions may advance to EXMEM/MEMWB before being invalidated
  // Gate register writes with memwb_valid to ensure only valid instructions commit
  wire int_reg_write_enable = (memwb_reg_write | memwb_int_reg_write_fp) && memwb_valid;

  register_file #(
    .XLEN(XLEN)
  ) regfile (
    .clk(clk),
    .reset_n(reset_n),
    .rs1_addr(id_rs1),
    .rs2_addr(id_rs2),
    .rd_addr(memwb_rd_addr),          // Write from WB stage
    .rd_data(wb_data),                // Write data from WB stage
    .rd_wen(int_reg_write_enable),    // Gated write enable: prevents flushed instruction writes
    .rs1_data(id_rs1_data_raw),
    .rs2_data(id_rs2_data_raw)
  );

  // ID Stage Integer Register Forwarding Muxes
  // Driven by centralized forwarding_unit outputs
  // Priority: EX > MEM > WB > Register File

  // Forward data from EX stage: use atomic_result for atomic instructions, alu_result otherwise
  // For atomic instructions, always forward atomic_result (even if 0 initially)
  wire [XLEN-1:0] ex_forward_data;
  assign ex_forward_data = idex_is_atomic ? ex_atomic_result : ex_alu_result;

  assign id_rs1_data = (id_forward_a == 3'b100) ? ex_forward_data :     // Forward from EX stage (atomic or ALU)
                       (id_forward_a == 3'b010) ? exmem_forward_data :  // Forward from MEM stage (atomic or ALU)
                       (id_forward_a == 3'b001) ? wb_data :             // Forward from WB stage
                       id_rs1_data_raw;                                  // Use register file value

  assign id_rs2_data = (id_forward_b == 3'b100) ? ex_forward_data :     // Forward from EX stage (atomic or ALU)
                       (id_forward_b == 3'b010) ? exmem_forward_data :  // Forward from MEM stage (atomic or ALU)
                       (id_forward_b == 3'b001) ? wb_data :             // Forward from WB stage
                       id_rs2_data_raw;                                  // Use register file value

  `ifdef DEBUG_EXCEPTION
  always @(posedge clk) begin
    // Debug branch at PC=0x60 (the mcause comparison)
    if (ifid_pc == 32'h60 && id_branch) begin
      $display("[BRANCH_0x60] rs1=x%0d rs2=x%0d rs1_data=%h rs2_data=%h fwd_a=%b fwd_b=%b",
               id_rs1, id_rs2, id_rs1_data, id_rs2_data, id_forward_a, id_forward_b);
      $display("[BRANCH_0x60] exmem_rd=x%0d exmem_reg_write=%b exmem_data=%h",
               exmem_rd_addr, exmem_reg_write, exmem_forward_data);
      $display("[BRANCH_0x60] idex_rd=x%0d idex_reg_write=%b idex_data=%h",
               idex_rd_addr, idex_reg_write, ex_forward_data);
    end
  end
  `endif

  `ifdef DEBUG_ATOMIC
  always @(posedge clk) begin
    if (id_opcode == 7'b0110011 && id_rd == 5'd14 && id_rs1 == 5'd14) begin // ADD to x14 from x14
      $display("[ID_ADD] @%0t ADD x14, x%0d, x%0d: rs1_data=%h (fwd_a=%b), rs2_data=%h (fwd_b=%b), PC=%h",
               $time, id_rs1, id_rs2, id_rs1_data, id_forward_a, id_rs2_data, id_forward_b, ifid_pc);
      $display("[ID_ADD_DBG] regfile_x14=%h, idex_is_atomic=%b, idex_rd=%d, exmem_rd=%d, memwb_rd=%d",
               id_rs1_data_raw, idex_is_atomic, idex_rd_addr, exmem_rd_addr, memwb_rd_addr);
      $display("[ID_ADD_FWD] idex_is_atomic=%b, exmem_is_atomic=%b, exmem_rd=%d, id_forward_a=%b",
               idex_is_atomic, exmem_is_atomic, exmem_rd_addr, id_forward_a);
      $display("[ID_ADD_FWD2] exmem_alu=%h, exmem_atomic=%h, exmem_fwd=%h, hold_exmem=%b",
               exmem_alu_result, exmem_atomic_result, exmem_forward_data, hold_exmem);
    end
    // Track writeback to x14
    if (memwb_reg_write && memwb_rd_addr == 5'd14) begin
      $display("[WB_X14] @%0t Writing x14 <= %h (wb_sel=%b, alu_result=%h, atomic_result=%h)",
               $time, wb_data, memwb_wb_sel, memwb_alu_result, memwb_atomic_result);
    end
  end
  `endif

  // Debug: WB stage FP register write
  `ifdef DEBUG_FPU_CONVERTER
  always @(posedge clk) begin
    if (memwb_fp_reg_write) begin
      $display("[%0t] [WB] FP write: f%0d <= 0x%h (wb_sel=%b, from %s)",
               $time, memwb_fp_rd_addr, wb_fp_data, memwb_wb_sel,
               (memwb_wb_sel == 3'b001) ? "MEM" : "FPU");
    end
  end
  `endif

  // FP Register File
  // Gate FP register writes with memwb_valid for consistency with integer register file
  wire fp_reg_write_enable = memwb_fp_reg_write && memwb_valid;

  fp_register_file #(
    .FLEN(`FLEN)  // 32 for F-only, 64 for F+D extensions
  ) fp_regfile (
    .clk(clk),
    .reset_n(reset_n),
    .rs1_addr(id_rs1),
    .rs2_addr(id_rs2),
    .rs3_addr(id_rs3),
    .rs1_data(id_fp_rs1_data_raw),
    .rs2_data(id_fp_rs2_data_raw),
    .rs3_data(id_fp_rs3_data_raw),
    .wr_en(fp_reg_write_enable),  // Gated write enable: prevents flushed instruction writes
    .rd_addr(memwb_fp_rd_addr),
    .rd_data(wb_fp_data),
    .write_single(~memwb_fp_fmt)  // 1 for single-precision (fmt=0), 0 for double-precision (fmt=1)
  );

  // ID Stage FP Register Forwarding Muxes
  // Driven by centralized forwarding_unit outputs
  // Priority: EX > MEM > WB > FP Register File

  assign id_fp_rs1_data = (id_fp_forward_a == 3'b100) ? ex_fp_result :      // Forward from EX stage
                          (id_fp_forward_a == 3'b010) ? exmem_fp_result :   // Forward from MEM stage
                          (id_fp_forward_a == 3'b001) ? wb_fp_data :        // Forward from WB stage
                          id_fp_rs1_data_raw;                                // Use FP register file value

  assign id_fp_rs2_data = (id_fp_forward_b == 3'b100) ? ex_fp_result :      // Forward from EX stage
                          (id_fp_forward_b == 3'b010) ? exmem_fp_result :   // Forward from MEM stage
                          (id_fp_forward_b == 3'b001) ? wb_fp_data :        // Forward from WB stage
                          id_fp_rs2_data_raw;                                // Use FP register file value

  assign id_fp_rs3_data = (id_fp_forward_c == 3'b100) ? ex_fp_result :      // Forward from EX stage
                          (id_fp_forward_c == 3'b010) ? exmem_fp_result :   // Forward from MEM stage
                          (id_fp_forward_c == 3'b001) ? wb_fp_data :        // Forward from WB stage
                          id_fp_rs3_data_raw;                                // Use FP register file value

  // Immediate Selection
  // For atomic operations, force immediate to 0 (address is rs1 + 0)
  assign id_immediate = id_is_atomic_dec ? {XLEN{1'b0}} :
                        (id_imm_sel == 3'b000) ? id_imm_i :
                        (id_imm_sel == 3'b001) ? id_imm_s :
                        (id_imm_sel == 3'b010) ? id_imm_b :
                        (id_imm_sel == 3'b011) ? id_imm_u :
                        (id_imm_sel == 3'b100) ? id_imm_j :
                        {XLEN{1'b0}};

  // CSR Address Extraction (from immediate field bits[31:20])
  assign id_csr_addr = ifid_instruction[31:20];

  // CSR Write Data (either rs1 data or zero-extended uimm from rs1 field)
  assign id_csr_wdata = id_csr_src ? {{(XLEN-5){1'b0}}, id_rs1} : id_rs1_data;

  // CSR Write Enable Suppression (RISC-V spec requirement)
  // For CSRRS/CSRRC (funct3[1]=1): if rs1=x0, don't write (read-only operation)
  // For CSRRSI/CSRRCI (funct3[1]=1): if uimm=0, don't write (read-only operation)
  // This allows reading read-only CSRs without triggering illegal instruction exception
  // Suppress if: (funct3[1] == 1) AND (rs1_field == 0)
  wire id_csr_write_suppress = id_funct3[1] && (id_rs1 == 5'h0);
  wire id_csr_we_actual = id_csr_we && !id_csr_write_suppress;

  // Hazard Detection Unit
  hazard_detection_unit hazard_unit (
    .clk(clk),
    // Integer load-use hazard inputs
    .idex_mem_read(idex_mem_read),
    .idex_rd(idex_rd_addr),
    .ifid_rs1(id_rs1),
    .ifid_rs2(id_rs2),
    // FP load-use hazard inputs
    .idex_fp_rd(idex_fp_rd_addr),
    .idex_fp_mem_op(idex_fp_mem_op),
    .ifid_fp_rs1(id_rs1),           // FP register addresses use same rs1/rs2/rs3 fields
    .ifid_fp_rs2(id_rs2),
    .ifid_fp_rs3(id_rs3),
    // M extension
    .mul_div_busy(ex_mul_div_busy),
    .idex_is_mul_div(idex_is_mul_div),
    // A extension
    .atomic_busy(ex_atomic_busy),
    .atomic_done(ex_atomic_done),
    .idex_is_atomic(idex_is_atomic),
    .exmem_is_atomic(exmem_is_atomic),
    .exmem_rd(exmem_rd_addr),
    // F/D extension
    .fpu_busy(ex_fpu_busy),
    .fpu_done(ex_fpu_done),
    .idex_fp_alu_en(idex_fp_alu_en),
    .exmem_fp_reg_write(exmem_fp_reg_write),
    .memwb_fp_reg_write(memwb_fp_reg_write),
    // CSR signals (for FFLAGS/FCSR dependency checking and RAW hazards)
    .id_csr_addr(id_csr_addr),
    .id_csr_we(id_csr_we),
    .id_is_csr(id_is_csr_dec),
    .idex_csr_we(idex_csr_we),
    .exmem_csr_we(exmem_csr_we),
    .memwb_csr_we(memwb_csr_we),
    // xRET signals (MRET/SRET modify CSRs)
    .exmem_is_mret(exmem_is_mret),
    .exmem_is_sret(exmem_is_sret),
    // MMU
    .mmu_busy(mmu_busy),
    // Outputs
    .stall_pc(stall_pc),
    .stall_ifid(stall_ifid),
    .bubble_idex(flush_idex_hazard)
  );

  // ID/EX Pipeline Register
  idex_register #(
    .XLEN(XLEN),
    .FLEN(`FLEN)
  ) idex_reg (
    .clk(clk),
    .reset_n(reset_n),
    .hold(hold_exmem),
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
    // M extension inputs
    .is_mul_div_in(id_is_mul_div_dec),
    .mul_div_op_in(id_mul_div_op_dec),
    .is_word_op_in(id_is_word_op_dec),
    // A extension inputs
    .is_atomic_in(id_is_atomic_dec),
    .funct5_in(id_funct5_dec),
    .aq_in(id_aq_dec),
    .rl_in(id_rl_dec),
    // F/D extension inputs
    .fp_rs1_data_in(id_fp_rs1_data),
    .fp_rs2_data_in(id_fp_rs2_data),
    .fp_rs3_data_in(id_fp_rs3_data),
    .fp_rs1_addr_in(id_rs1),
    .fp_rs2_addr_in(id_rs2),
    .fp_rs3_addr_in(id_rs3),
    .fp_rd_addr_in(id_rd),
    .fp_reg_write_in(id_fp_reg_write),
    .int_reg_write_fp_in(id_int_reg_write_fp),
    .fp_mem_op_in(id_fp_mem_op),
    .fp_alu_en_in(id_fp_alu_en),
    .fp_alu_op_in(id_fp_alu_op),
    .fp_rm_in(id_fp_rm),
    .fp_use_dynamic_rm_in(id_fp_use_dynamic_rm),
    .fp_fmt_in(id_fp_fmt),
    // CSR inputs
    .csr_addr_in(id_csr_addr),
    .csr_we_in(id_csr_we_actual),
    .csr_src_in(id_csr_src),
    .csr_wdata_in(id_csr_wdata),
    .is_csr_in(id_is_csr_dec),
    // Exception inputs
    .is_ecall_in(id_is_ecall),
    .is_ebreak_in(id_is_ebreak),
    .is_mret_in(id_is_mret),
    .is_sret_in(id_is_sret),
    .is_sfence_vma_in(id_is_sfence_vma),
    .illegal_inst_in(id_illegal_inst),
    .instruction_in(ifid_instruction),
    // C extension input
    .is_compressed_in(ifid_is_compressed),
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
    .valid_out(idex_valid),
    // M extension outputs
    .is_mul_div_out(idex_is_mul_div),
    .mul_div_op_out(idex_mul_div_op),
    .is_word_op_out(idex_is_word_op),
    // A extension outputs
    .is_atomic_out(idex_is_atomic),
    .funct5_out(idex_funct5),
    .aq_out(idex_aq),
    .rl_out(idex_rl),
    // F/D extension outputs
    .fp_rs1_data_out(idex_fp_rs1_data),
    .fp_rs2_data_out(idex_fp_rs2_data),
    .fp_rs3_data_out(idex_fp_rs3_data),
    .fp_rs1_addr_out(idex_fp_rs1_addr),
    .fp_rs2_addr_out(idex_fp_rs2_addr),
    .fp_rs3_addr_out(idex_fp_rs3_addr),
    .fp_rd_addr_out(idex_fp_rd_addr),
    .fp_reg_write_out(idex_fp_reg_write),
    .int_reg_write_fp_out(idex_int_reg_write_fp),
    .fp_mem_op_out(idex_fp_mem_op),
    .fp_alu_en_out(idex_fp_alu_en),
    .fp_alu_op_out(idex_fp_alu_op),
    .fp_rm_out(idex_fp_rm),
    .fp_use_dynamic_rm_out(idex_fp_use_dynamic_rm),
    .fp_fmt_out(idex_fp_fmt),
    // CSR outputs
    .csr_addr_out(idex_csr_addr),
    .csr_we_out(idex_csr_we),
    .csr_src_out(idex_csr_src),
    .csr_wdata_out(idex_csr_wdata),
    .is_csr_out(idex_is_csr),
    // Exception outputs
    .is_ecall_out(idex_is_ecall),
    .is_ebreak_out(idex_is_ebreak),
    .is_mret_out(idex_is_mret),
    .is_sret_out(idex_is_sret),
    .is_sfence_vma_out(idex_is_sfence_vma),
    .illegal_inst_out(idex_illegal_inst),
    .instruction_out(idex_instruction),
    // C extension output
    .is_compressed_out(idex_is_compressed)
  );

  //==========================================================================
  // EX STAGE: Execute
  //==========================================================================

  // Bug #42: C.JAL and C.JALR must save PC+2, not PC+4
  assign ex_pc_plus_4 = idex_is_compressed ? (idex_pc + {{(XLEN-2){1'b0}}, 2'b10}) :
                                              (idex_pc + {{(XLEN-3){1'b0}}, 3'b100});

  // Forwarding Unit (centralized forwarding logic for all stages)
  forwarding_unit forward_unit (
    // ID stage integer forwarding (for branches)
    .id_rs1(id_rs1),
    .id_rs2(id_rs2),
    .id_forward_a(id_forward_a),
    .id_forward_b(id_forward_b),

    // EX stage integer forwarding (for ALU ops)
    .idex_rs1(idex_rs1_addr),
    .idex_rs2(idex_rs2_addr),
    .forward_a(forward_a),
    .forward_b(forward_b),

    // Pipeline stage write ports
    .idex_rd(idex_rd_addr),
    .idex_reg_write(idex_reg_write),
    .idex_is_atomic(idex_is_atomic),
    .exmem_rd(exmem_rd_addr),
    .exmem_reg_write(exmem_reg_write),
    .exmem_int_reg_write_fp(exmem_int_reg_write_fp),
    .memwb_rd(memwb_rd_addr),
    .memwb_reg_write(memwb_reg_write),
    .memwb_int_reg_write_fp(memwb_int_reg_write_fp),
    .memwb_valid(memwb_valid),

    // ID stage FP forwarding
    .id_fp_rs1(id_rs1),
    .id_fp_rs2(id_rs2),
    .id_fp_rs3(id_rs3),
    .id_fp_forward_a(id_fp_forward_a),
    .id_fp_forward_b(id_fp_forward_b),
    .id_fp_forward_c(id_fp_forward_c),

    // EX stage FP forwarding
    .idex_fp_rs1(idex_fp_rs1_addr),
    .idex_fp_rs2(idex_fp_rs2_addr),
    .idex_fp_rs3(idex_fp_rs3_addr),
    .fp_forward_a(fp_forward_a),
    .fp_forward_b(fp_forward_b),
    .fp_forward_c(fp_forward_c),

    // FP pipeline stage write ports
    .idex_fp_rd(idex_fp_rd_addr),
    .idex_fp_reg_write(idex_fp_reg_write),
    .exmem_fp_rd(exmem_fp_rd_addr),
    .exmem_fp_reg_write(exmem_fp_reg_write),
    .memwb_fp_rd(memwb_fp_rd_addr),
    .memwb_fp_reg_write(memwb_fp_reg_write)
  );

  // ALU Operand A selection (with forwarding)
  // AUIPC uses PC, LUI uses 0, others use rs1
  assign ex_alu_operand_a = (idex_opcode == 7'b0010111) ? idex_pc :          // AUIPC
                            (idex_opcode == 7'b0110111) ? {XLEN{1'b0}} :   // LUI
                            idex_rs1_data;                                    // Others

  // Disable forwarding for LUI and AUIPC (they don't use rs1, decoder extracts garbage)
  wire disable_forward_a = (idex_opcode == 7'b0110111) || (idex_opcode == 7'b0010111);  // LUI or AUIPC

  assign ex_alu_operand_a_forwarded = disable_forward_a ? ex_alu_operand_a :            // No forward for LUI/AUIPC
                                      (forward_a == 2'b10) ? exmem_forward_data :       // EX hazard (includes FP-to-INT)
                                      (forward_a == 2'b01) ? wb_data :                  // MEM hazard
                                      ex_alu_operand_a;                                  // No hazard

  `ifdef DEBUG_M_OPERANDS
  always @(*) begin
    if (idex_is_mul_div) begin
      $display("[M_OPERANDS] @%0t operand_a: idex_rs1_data=%h fwd_a=%b exmem=%h wb=%h → result=%h",
               $time, idex_rs1_data, forward_a, exmem_alu_result, wb_data, ex_alu_operand_a_forwarded);
    end
  end
  `endif

  // Forward data selection: use atomic_result for atomic instructions, int_result_fp for FP-to-INT, mul_div_result for M-extension, alu_result otherwise
  wire [XLEN-1:0] exmem_forward_data;
  assign exmem_forward_data = exmem_is_atomic ? exmem_atomic_result :
                              exmem_int_reg_write_fp ? exmem_int_result_fp :
                              (exmem_wb_sel == 3'b011) ? exmem_csr_rdata :  // CSR read result
                              (exmem_wb_sel == 3'b100) ? exmem_mul_div_result :  // M extension result
                              exmem_alu_result;

  // rs1 data forwarding (for SFENCE.VMA and other instructions that use rs1 data directly)
  wire [XLEN-1:0] ex_rs1_data_forwarded;
  assign ex_rs1_data_forwarded = (forward_a == 2'b10) ? exmem_forward_data :       // EX hazard
                                  (forward_a == 2'b01) ? wb_data :                  // MEM hazard
                                  idex_rs1_data;                                     // No hazard

  // ALU Operand B selection (with forwarding)
  wire [XLEN-1:0] ex_rs2_data_forwarded;
  assign ex_rs2_data_forwarded = (forward_b == 2'b10) ? exmem_forward_data :       // EX hazard
                                  (forward_b == 2'b01) ? wb_data :                  // MEM hazard
                                  idex_rs2_data;                                     // No hazard

  `ifdef DEBUG_ATOMIC
  always @(*) begin
    if (idex_is_atomic && a_unit_start) begin
      $display("[FORWARD_ATOMIC] @%0t SC/LR start: rs2=x%0d, forward_b=%b, idex_rs2=%h, exmem_fwd=%h, wb=%h → result=%h",
               $time, idex_rs2_addr, forward_b, idex_rs2_data, exmem_forward_data, wb_data, ex_rs2_data_forwarded);
      $display("[FORWARD_ATOMIC] exmem_is_atomic=%b, exmem_atomic_result=%h, exmem_alu_result=%h, exmem_rd=x%0d",
               exmem_is_atomic, exmem_atomic_result, exmem_alu_result, exmem_rd_addr);
    end
  end
  `endif

  `ifdef DEBUG_M_OPERANDS
  always @(*) begin
    if (idex_is_mul_div) begin
      $display("[M_OPERANDS] @%0t operand_b: idex_rs2_data=%h fwd_b=%b exmem=%h wb=%h → result=%h",
               $time, idex_rs2_data, forward_b, exmem_alu_result, wb_data, ex_rs2_data_forwarded);
    end
  end
  `endif

  assign ex_alu_operand_b = idex_alu_src ? idex_imm : ex_rs2_data_forwarded;

  // ALU
  alu #(
    .XLEN(XLEN)
  ) alu_inst (
    .operand_a(ex_alu_operand_a_forwarded),
    .operand_b(ex_alu_operand_b),
    .alu_control(idex_alu_control),
    .result(ex_alu_result),
    .zero(ex_alu_zero),
    .less_than(ex_alu_lt),
    .less_than_unsigned(ex_alu_ltu)
  );

  // Debug: ALU output
  `ifdef DEBUG_ALU
  always @(posedge clk) begin
    if (idex_valid && !idex_is_mul_div && !idex_fp_alu_en) begin
      $display("[ALU] @%0t pc=%h result=%h (opcode=%b rd=x%0d)",
               $time, idex_pc, ex_alu_result, idex_opcode, idex_rd_addr);
    end
  end
  `endif

  // M Extension: Latch operands when instruction first enters EX stage
  // This prevents corruption from forwarding paths changing during long M operations
  // IMPORTANT: Latch the FORWARDED values, not raw IDEX values, because forwarding
  // is needed when M instruction depends on recent instructions
  reg [XLEN-1:0] m_operand_a_latched;
  reg [XLEN-1:0] m_operand_b_latched;
  reg m_operands_valid;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      m_operand_a_latched <= {XLEN{1'b0}};
      m_operand_b_latched <= {XLEN{1'b0}};
      m_operands_valid <= 1'b0;
    end else if (idex_is_mul_div && !ex_mul_div_busy && !m_operands_valid) begin
      // Latch FORWARDED operands when M instruction first enters EX (before it starts execution)
      // This captures the correct forwarded values before they get polluted by subsequent instructions
      m_operand_a_latched <= ex_alu_operand_a_forwarded;
      m_operand_b_latched <= ex_rs2_data_forwarded;
      m_operands_valid <= 1'b1;
    end else if (!idex_is_mul_div) begin
      m_operands_valid <= 1'b0;
    end
  end

  // Select between latched operands (for M unit) and forwarded operands (for others)
  wire [XLEN-1:0] m_final_operand_a = m_operands_valid ? m_operand_a_latched : ex_alu_operand_a_forwarded;
  wire [XLEN-1:0] m_final_operand_b = m_operands_valid ? m_operand_b_latched : ex_rs2_data_forwarded;

  // M Extension Unit
  mul_div_unit #(
    .XLEN(XLEN)
  ) m_unit (
    .clk(clk),
    .reset_n(reset_n),
    .start(m_unit_start),
    .operation(idex_mul_div_op),
    .is_word_op(idex_is_word_op),
    .operand_a(m_final_operand_a),
    .operand_b(m_final_operand_b),
    .result(ex_mul_div_result),
    .busy(ex_mul_div_busy),
    .ready(ex_mul_div_ready)
  );

  // A Extension - Atomic Operations Unit
  wire [XLEN-1:0] ex_atomic_result;
  wire            ex_atomic_done;
  wire            ex_atomic_busy;
  wire            ex_atomic_mem_req;
  wire            ex_atomic_mem_we;
  wire [XLEN-1:0] ex_atomic_mem_addr;
  wire [XLEN-1:0] ex_atomic_mem_wdata;
  wire [2:0]      ex_atomic_mem_size;
  wire            ex_atomic_mem_ready;

  // A unit start signal: pulse once when A instruction first enters EX
  // Track if current atomic instruction in IDEX has already been executed
  reg atomic_already_started;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      atomic_already_started <= 1'b0;
    end else if (flush_idex) begin
      // Flush clears IDEX, reset flag
      atomic_already_started <= 1'b0;
    end else if (!hold_exmem && idex_valid) begin
      // Instruction moving from IDEX to EXMEM (new instruction will enter IDEX next cycle)
      atomic_already_started <= 1'b0;
    end else if (ex_atomic_done) begin
      // Atomic operation completed, set flag to prevent restart
      atomic_already_started <= 1'b1;
    end
  end

  wire            a_unit_start;
  assign a_unit_start = idex_is_atomic && idex_valid && !ex_atomic_busy && !ex_atomic_done && !atomic_already_started;

  // Reservation station signals
  wire            ex_lr_valid;
  wire [XLEN-1:0] ex_lr_addr;
  wire            ex_sc_valid;
  wire [XLEN-1:0] ex_sc_addr;
  wire            ex_sc_success;

  atomic_unit #(
    .XLEN(XLEN)
  ) atomic_unit_inst (
    .clk(clk),
    .reset(!reset_n),
    .start(a_unit_start),
    .funct5(idex_funct5),
    .funct3(idex_funct3),
    .aq(idex_aq),
    .rl(idex_rl),
    .addr(ex_alu_operand_a_forwarded),
    .src_data(ex_rs2_data_forwarded),
    // Memory interface (connects to data memory via MUX)
    .mem_req(ex_atomic_mem_req),
    .mem_we(ex_atomic_mem_we),
    .mem_addr(ex_atomic_mem_addr),
    .mem_wdata(ex_atomic_mem_wdata),
    .mem_size(ex_atomic_mem_size),
    .mem_rdata(mem_read_data),
    .mem_ready(ex_atomic_mem_ready),
    // Reservation station interface
    .lr_valid(ex_lr_valid),
    .lr_addr(ex_lr_addr),
    .sc_valid(ex_sc_valid),
    .sc_addr(ex_sc_addr),
    .sc_success(ex_sc_success),
    // Outputs
    .result(ex_atomic_result),
    .done(ex_atomic_done),
    .busy(ex_atomic_busy)
  );

  // Atomic reservation invalidation on stores
  // Invalidate LR reservation when any store writes to memory in MEM stage
  wire reservation_invalidate;
  wire [XLEN-1:0] reservation_inv_addr;

  // Only invalidate reservation when a NEW instruction enters MEM stage with a store
  // Track when EXMEM was held last cycle - if it was held, then releasing it means
  // the instruction that was in EX is NOW entering MEM for the first time
  reg hold_exmem_prev;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      hold_exmem_prev <= 1'b0;
    else
      hold_exmem_prev <= hold_exmem;
  end

  // Invalidate when: (1) EXMEM was held last cycle and is now released (instruction entering MEM)
  //               OR (2) EXMEM wasn't held last cycle (normal pipeline flow - instruction just entered MEM)
  // Basically: invalidate on the FIRST cycle an instruction is in MEM stage
  assign reservation_invalidate = exmem_mem_write && !exmem_is_atomic && !hold_exmem_prev && exmem_valid;
  assign reservation_inv_addr = exmem_alu_result;

  `ifdef DEBUG_ATOMIC
  always @(posedge clk) begin
    if (reservation_invalidate) begin
      $display("[CORE] Reservation invalidate: PC=0x%08h, mem_wr=%b, is_atomic=%b, hold=%b, valid=%b, addr=0x%08h",
               exmem_pc, exmem_mem_write, exmem_is_atomic, hold_exmem, exmem_valid, exmem_alu_result);
    end
    if (idex_is_atomic && idex_valid) begin
      $display("[CORE] Atomic in IDEX: PC=0x%08h, is_atomic=%b, hold_exmem=%b, done=%b, result=0x%08h",
               idex_pc, idex_is_atomic, hold_exmem, ex_atomic_done, ex_atomic_result);
    end
    if (exmem_is_atomic && exmem_valid) begin
      $display("[CORE] Atomic in EXMEM: PC=0x%08h, is_atomic=%b, mem_wr=%b, result=0x%08h",
               exmem_pc, exmem_is_atomic, exmem_mem_write, exmem_atomic_result);
    end
    if (idex_pc == 32'h20 && idex_valid) begin
      $display("[CORE] BNEZ in IDEX: PC=0x%08h, rs1(t3)=x%0d, rs1_data=0x%08h, id_forward_a=%b",
               idex_pc, idex_rs1_addr, idex_rs1_data, id_forward_a);
      $display("      exmem: rd=x%0d, reg_wr=%b, valid=%b, is_atomic=%b",
               exmem_rd_addr, exmem_reg_write, exmem_valid, exmem_is_atomic);
    end
  end
  `endif

  reservation_station #(
    .XLEN(XLEN)
  ) reservation_station_inst (
    .clk(clk),
    .reset(!reset_n),
    .lr_valid(ex_lr_valid),
    .lr_addr(ex_lr_addr),
    .sc_valid(ex_sc_valid),
    .sc_addr(ex_sc_addr),
    .sc_success(ex_sc_success),
    .invalidate(reservation_invalidate),
    .inv_addr(reservation_inv_addr),
    .exception(exception),
    .interrupt(1'b0)                // TODO: connect to interrupt signal when implemented
  );

  // Branch Unit
  branch_unit #(
    .XLEN(XLEN)
  ) branch_inst (
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
  // Clear LSB for JALR (always aligned to 2 bytes)
  assign ex_jump_target = (idex_opcode == 7'b1100111) ?
                          (ex_alu_operand_a_forwarded + idex_imm) & ~{{(XLEN-1){1'b0}}, 1'b1} :
                          idex_pc + idex_imm;

  //==========================================================================
  // CSR File (in EX stage for read/write)
  //==========================================================================

  // CSR Write Data Forwarding
  // CSR write data comes from rs1 (for register form CSR instructions)
  // Need to forward from EX/MEM or MEM/WB stages to handle RAW hazards
  // Only forward for register-form CSR instructions (funct3[2] = 0)
  wire ex_csr_uses_rs1;
  assign ex_csr_uses_rs1 = (idex_wb_sel == 3'b011) && !idex_csr_src;  // CSR instruction using rs1

  wire [XLEN-1:0] ex_csr_wdata_forwarded;
  assign ex_csr_wdata_forwarded = (ex_csr_uses_rs1 && forward_a == 2'b10) ? exmem_alu_result :  // EX-to-EX forward
                                  (ex_csr_uses_rs1 && forward_a == 2'b01) ? wb_data :           // MEM-to-EX forward
                                  idex_csr_wdata;                                                 // No hazard or imm form

  `ifdef DEBUG_PRIV
  reg [31:0] debug_cycle;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      debug_cycle <= 0;
    end else begin
      debug_cycle <= debug_cycle + 1;
      if (mret_flush || sret_flush) begin
        $display("[PIPE] Cycle %0d: xRET flush - PC=0x%08x->0x%08x ifid_valid=%b idex_valid=%b stall_pc=%b",
                 debug_cycle, pc_current, pc_next, ifid_valid, idex_valid, stall_pc);
      end
      if (debug_cycle > 0 && pc_current >= 32'h4c && pc_current <= 32'h60) begin
        $display("[PIPE] Cycle %0d: PC=0x%08x ifid_PC=0x%08x ifid_valid=%b idex_PC=0x%08x idex_valid=%b idex_is_csr=%b stall=%b",
                 debug_cycle, pc_current, ifid_pc, ifid_valid, idex_pc, idex_valid, idex_is_csr, stall_pc);
      end
    end
  end
  `endif

  `ifdef DEBUG_CSR
  reg [31:0] debug_cycle_csr;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      debug_cycle_csr <= 0;
    else
      debug_cycle_csr <= debug_cycle_csr + 1;
  end

  always @(posedge clk) begin
    if (idex_is_csr) begin
      $display("[CORE_CSR] Cycle %0d: CSR in EX: addr=0x%03x is_csr=%b valid=%b access=%b PC=0x%08x priv=%b",
               debug_cycle_csr, idex_csr_addr, idex_is_csr, idex_valid, idex_is_csr && idex_valid, idex_pc, current_priv);
    end
  end
  `endif

  csr_file #(
    .XLEN(XLEN)
  ) csr_file_inst (
    .clk(clk),
    .reset_n(reset_n),
    .csr_addr(idex_csr_addr),
    .csr_wdata(ex_csr_wdata_forwarded),  // Use forwarded value
    .csr_op(idex_funct3),           // funct3 encodes CSR operation
    .csr_we(idex_csr_we && idex_valid && !exception),  // Don't commit CSR writes on exceptions
    .csr_access(idex_is_csr && idex_valid),
    .csr_rdata(ex_csr_rdata),
    .trap_entry(exception_gated),  // Use gated signal for immediate trap (0-cycle latency)
    .trap_pc(exception_pc),        // Use current exception PC (not registered)
    .trap_cause(exception_code),   // Use current exception code (not registered)
    .trap_is_interrupt(combined_is_interrupt), // Indicate if this is an interrupt vs exception
    .trap_val(exception_val),      // Use current exception val (not registered)
    .trap_vector(trap_vector),
    .mret(exmem_is_mret && exmem_valid && !exception),
    .mepc_out(mepc),
    .sret(exmem_is_sret && exmem_valid && !exception),
    .sepc_out(sepc),
    .mstatus_mie(mstatus_mie),
    .mstatus_sie(mstatus_sie),
    .mstatus_mpie(mstatus_mpie),
    .mstatus_spie(mstatus_spie),
    .illegal_csr(ex_illegal_csr),
    // Privilege mode tracking (Phase 1)
    // Bug fix: Use effective_priv (with forwarding) for CSR access checks.
    // For trap delegation, use current_priv (WITHOUT forwarding) to ensure delegation
    // decisions are based on the actual privilege mode of the trapping instruction.
    .current_priv(effective_priv),      // For CSR privilege checks (with xRET forwarding)
    .actual_priv(current_priv),         // For trap delegation (WITHOUT xRET forwarding)
    .trap_target_priv(trap_target_priv),
    .mpp_out(mpp),
    .spp_out(spp),
    .medeleg_out(medeleg),              // For early trap target computation in core
    // MMU-related outputs (for Phase 3)
    .satp_out(satp),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr),
    // Floating-point CSR connections
    .frm_out(csr_frm),
    .fflags_out(csr_fflags),
    // Bug #7b fix: Only accumulate flags for FP ALU operations, not FP loads
    // FP loads have wb_sel=001 (memory data), FP ALU has other wb_sel values
    // Bug #14 fix: Include FP→INT operations (fcvt.w.s, fclass, etc.)
    .fflags_we((memwb_fp_reg_write || memwb_int_reg_write_fp) && memwb_valid && (memwb_wb_sel != 3'b001)),
    .fflags_in({memwb_fp_flag_nv, memwb_fp_flag_dz, memwb_fp_flag_of, memwb_fp_flag_uf, memwb_fp_flag_nx}),
    // External interrupt inputs (Phase 1.3: CLINT + PLIC integration)
    .mtip_in(mtip_in),
    .msip_in(msip_in),
    .meip_in(meip_in),
    .seip_in(seip_in),
    // Interrupt register outputs (Phase 1.5: Interrupt handling)
    .mip_out(mip),
    .mie_out(mie),
    .mideleg_out(mideleg)
  );

  // Alias for MMU integration
  assign csr_satp = satp;

  //==========================================================================
  // Interrupt Handling (Phase 1.5)
  //==========================================================================
  // Interrupts are treated as asynchronous exceptions that can occur at any time
  // Priority order (from highest to lowest, per RISC-V spec):
  //   MEI (11) > MSI (3) > MTI (7) > SEI (9) > SSI (1) > STI (5)

  // Compute pending and enabled interrupts
  wire [XLEN-1:0] pending_interrupts = mip & mie;

  // Check global interrupt enable based on current privilege mode
  wire interrupts_globally_enabled =
    (current_priv == 2'b11) ? mstatus_mie :  // M-mode: check MIE
    (current_priv == 2'b01) ? mstatus_sie :  // S-mode: check SIE
    1'b1;                                     // U-mode: always enabled

  // Priority encoding for interrupts (RISC-V spec priority order)
  wire interrupt_pending;
  wire [4:0] interrupt_cause;
  wire interrupt_is_s_mode;  // True if interrupt should trap to S-mode

  // Check each interrupt in priority order
  wire mei_pending = pending_interrupts[11];  // Machine External Interrupt
  wire msi_pending = pending_interrupts[3];   // Machine Software Interrupt
  wire mti_pending = pending_interrupts[7];   // Machine Timer Interrupt
  wire sei_pending = pending_interrupts[9];   // Supervisor External Interrupt
  wire ssi_pending = pending_interrupts[1];   // Supervisor Software Interrupt
  wire sti_pending = pending_interrupts[5];   // Supervisor Timer Interrupt

  // Mask interrupts during xRET execution to prevent race condition
  // When MRET/SRET is in the pipeline, we need to prevent new interrupts from firing
  // until the xRET completes and updates privilege mode. Otherwise, the interrupt
  // would use the old privilege mode and could cause incorrect delegation.
  wire xret_in_pipeline = (idex_is_mret || idex_is_sret) && idex_valid ||
                          (exmem_is_mret || exmem_is_sret) && exmem_valid;

  reg xret_completing;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      xret_completing <= 1'b0;
    else
      xret_completing <= xret_in_pipeline;
  end

  // Priority encoder (highest priority wins)
  // Mask interrupts while xRET is in pipeline or completing
  assign interrupt_pending = interrupts_globally_enabled && |pending_interrupts &&
                             !xret_in_pipeline && !xret_completing;
  assign interrupt_cause =
    mei_pending ? 5'd11 :  // MEI
    msi_pending ? 5'd3  :  // MSI
    mti_pending ? 5'd7  :  // MTI
    sei_pending ? 5'd9  :  // SEI
    ssi_pending ? 5'd1  :  // SSI
    sti_pending ? 5'd5  :  // STI
    5'd0;                   // No interrupt

  // Check if interrupt should be delegated to S-mode
  // Only delegate if: (1) interrupt is delegated via mideleg, AND (2) currently in S or U mode
  assign interrupt_is_s_mode = mideleg[interrupt_cause] && (current_priv <= 2'b01);

  // Debug interrupt handling
  `ifdef DEBUG_INTERRUPT
  reg [31:0] debug_cycle_intr;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      debug_cycle_intr <= 0;
    else
      debug_cycle_intr <= debug_cycle_intr + 1;
  end

  always @(posedge clk) begin
    // Debug every 100 cycles to show interrupt status
    if (debug_cycle_intr % 100 == 50) begin
      $display("[CORE_INTR] cycle=%0d mtip_in=%b msip_in=%b meip_in=%b seip_in=%b",
               debug_cycle_intr, mtip_in, msip_in, meip_in, seip_in);
    end
    if (mtip_in || msip_in) begin
      $display("[INTR_IN] cycle=%0d mtip_in=%b msip_in=%b meip_in=%b seip_in=%b",
               debug_cycle_intr, mtip_in, msip_in, meip_in, seip_in);
      $display("[INTR_VAL] mip=%h mie=%h pending=%h",
               mip, mie, pending_interrupts);
    end
    if (|pending_interrupts) begin
      $display("[INTR] mip=%h mie=%h pending=%h mti=%b mstatus_mie=%b globally_en=%b intr_pend=%b",
               mip, mie, pending_interrupts, mti_pending, mstatus_mie, interrupts_globally_enabled, interrupt_pending);
      $display("[INTR] current_priv=%b exception_gated=%b exception_taken_r=%b trap_flush=%b PC=%h",
               current_priv, exception_gated, exception_taken_r, trap_flush, pc_current);
    end
    // Track PC when trap occurs
    if (exception_gated) begin
      $display("[TRAP] cycle=%0d exception_gated=1 PC=%h trap_vector=%h mepc=%h",
               debug_cycle_intr, pc_current, trap_vector, mepc);
    end
    // Track PC after trap (next cycle)
    if (exception_taken_r) begin
      $display("[TRAP_PC] cycle=%0d exception_taken PC=%h mepc=%h", debug_cycle_intr, pc_current, mepc);
    end
    // Track MRET
    if (exmem_is_mret && exmem_valid) begin
      $display("[MRET_MEM] cycle=%0d exmem_PC=%h mepc=%h mret_flush=%b exception=%b interrupt_pending=%b xret_in_pipe=%b xret_completing=%b",
               debug_cycle_intr, exmem_pc, mepc, mret_flush, exception, interrupt_pending, xret_in_pipeline, xret_completing);
    end
    // Track PC jumps around cycle 520
    if (debug_cycle_intr >= 515 && debug_cycle_intr <= 545) begin
      $display("[PC_TRACE] cycle=%0d IF_PC=%h pc_next=%h trap_flush=%b mret_flush=%b",
               debug_cycle_intr, pc_current, pc_next, trap_flush, mret_flush);
    end
    // Track PC when execution hangs (after "Tasks created..." message)
    // Sample every 100 cycles to reduce output (extended range)
    if (debug_cycle_intr >= 25000 && debug_cycle_intr <= 150000 && (debug_cycle_intr % 100 == 0)) begin
      $display("[PC_SAMPLE] cycle=%0d PC=%h", debug_cycle_intr, pc_current);
    end
    // Debug memset function entry and loop
    if (pc_current == 32'h00002000) begin
      // Memset entry - trace arguments: a0=x10, a1=x11, a2=x12
      $display("[MEMSET_ENTRY] cycle=%0d addr(a0/x10)=%h value(a1/x11)=%h size(a2/x12)=%h",
               debug_cycle_intr, regfile.registers[10], regfile.registers[11], regfile.registers[12]);
    end
    // Sample memset loop every 1000 cycles to see progress
    if (pc_current >= 32'h2004 && pc_current <= 32'h200c && (debug_cycle_intr % 1000 == 0)) begin
      $display("[MEMSET_LOOP] cycle=%0d PC=%h counter(a2/x12)=%h",
               debug_cycle_intr, pc_current, regfile.registers[12]);
    end
    // Debug vPortSetupTimerInterrupt mtime read loop
    if (pc_current == 32'h1aec && (debug_cycle_intr % 100 == 0)) begin
      $display("[MTIME_LOOP] cycle=%0d PC=%h a5(x15)=%h a3(x13)=%h a4(x14)=%h",
               debug_cycle_intr, pc_current, regfile.registers[15], regfile.registers[13], regfile.registers[14]);
    end
    // Debug trap handler - check mcause when entering exception handler
    if (pc_current == 32'h000001c2 || pc_current == 32'h000001d0) begin
      $display("[TRAP_HANDLER] cycle=%0d PC=%h ENTERED - mcause will be in t0(x5) after csrr",
               debug_cycle_intr, pc_current);
    end
    if (pc_current == 32'h000001ce || pc_current == 32'h000001dc) begin
      $display("[TRAP_STUCK] cycle=%0d PC=%h INFINITE_LOOP - t0(mcause)=%h t1(mepc)=%h t2(mstatus)=%h",
               debug_cycle_intr, pc_current, regfile.registers[5], regfile.registers[6], regfile.registers[7]);
    end
  end
  `endif

  //==========================================================================
  // Combined Exception/Interrupt Handling
  //==========================================================================
  // Merge synchronous exceptions with asynchronous interrupts
  // Synchronous exceptions have priority over interrupts

  wire combined_exception;
  wire [4:0] combined_exception_code;
  wire [XLEN-1:0] combined_exception_pc;
  wire [XLEN-1:0] combined_exception_val;
  wire combined_is_interrupt;

  // Synchronous exception from exception_unit
  wire sync_exception;
  wire [4:0] sync_exception_code;
  wire [XLEN-1:0] sync_exception_pc;
  wire [XLEN-1:0] sync_exception_val;

  // Priority: Synchronous exceptions > Interrupts
  assign exception = sync_exception || interrupt_pending;
  assign exception_code = sync_exception ? sync_exception_code : interrupt_cause;
  assign exception_pc = sync_exception ? sync_exception_pc : pc_current;
  assign exception_val = sync_exception ? sync_exception_val : {XLEN{1'b0}};
  assign combined_is_interrupt = !sync_exception && interrupt_pending;

  //==========================================================================
  // Exception Unit (monitors all stages)
  //==========================================================================
  exception_unit #(
    .XLEN(XLEN)
  ) exception_unit_inst (
    // Privilege mode (Phase 1)
    // Note: Exception delegation is determined by CSR file's trap_target_priv output,
    // which uses actual current_priv. Exception unit just detects exceptions.
    .current_priv(current_priv),
    // IF stage - instruction fetch (check misaligned PC)
    // Note: IF exceptions are checked when instruction is in IFID register
    .if_pc(ifid_pc),
    .if_valid(ifid_valid),          // Use registered valid from IFID
    // ID stage - decode stage exceptions (in EX pipeline stage)
    // Note: Only consider illegal_csr if it's actually a CSR instruction
    .id_illegal_inst((idex_illegal_inst | (ex_illegal_csr && idex_is_csr)) && idex_valid),
    .id_ecall(idex_is_ecall && idex_valid),
    .id_ebreak(idex_is_ebreak && idex_valid),
    .id_mret(idex_is_mret && idex_valid),
    .id_sret(idex_is_sret && idex_valid),
    .id_pc(idex_pc),
    .id_instruction(idex_instruction),
    .id_valid(idex_valid),
    // MEM stage - memory access exceptions
    .mem_addr(exmem_alu_result),
    .mem_read(exmem_mem_read && exmem_valid),
    .mem_write(exmem_mem_write && exmem_valid),
    .mem_funct3(exmem_funct3),
    .mem_pc(exmem_pc),
    .mem_instruction(exmem_instruction),
    .mem_valid(exmem_valid),
    // Page fault inputs (Phase 3 - MMU integration)
    .mem_page_fault(mmu_req_page_fault),
    .mem_fault_vaddr(mmu_req_fault_vaddr),
    // Outputs (connect to sync_exception signals, will be merged with interrupts)
    .exception(sync_exception),
    .exception_code(sync_exception_code),
    .exception_pc(sync_exception_pc),
    .exception_val(sync_exception_val)
  );

  // Determine if exception is from MEM stage (for precise exception handling)
  // MEM-stage exceptions: Load/Store misaligned (4,6), Load/Store page faults (13,15)
  // Use gated exception to prevent spurious exception detection
  wire exception_from_mem = exception_gated && ((exception_code == 5'd4) ||  // Load misaligned
                                                 (exception_code == 5'd6) ||  // Store misaligned
                                                 (exception_code == 5'd13) || // Load page fault
                                                 (exception_code == 5'd15));  // Store page fault

  //==========================================================================
  // FPU (Floating-Point Unit) - F/D Extension
  //==========================================================================

  // FP Operand Forwarding Muxes
  // FP Forwarding: Use wb_fp_data for MEMWB forwarding to handle FP loads correctly
  // For FP loads, the data comes from memory (wb_fp_data), not from FPU (memwb_fp_result)
  assign ex_fp_operand_a = (fp_forward_a == 2'b10) ? exmem_fp_result :
                           (fp_forward_a == 2'b01) ? wb_fp_data :
                           idex_fp_rs1_data;

  assign ex_fp_operand_b = (fp_forward_b == 2'b10) ? exmem_fp_result :
                           (fp_forward_b == 2'b01) ? wb_fp_data :
                           idex_fp_rs2_data;

  assign ex_fp_operand_c = (fp_forward_c == 2'b10) ? exmem_fp_result :
                           (fp_forward_c == 2'b01) ? wb_fp_data :
                           idex_fp_rs3_data;

  // FP Rounding Mode Selection (dynamic from frm CSR or static from instruction)
  assign ex_fp_rounding_mode = idex_fp_use_dynamic_rm ? csr_frm : idex_fp_rm;

  // FPU Instantiation
  fpu #(
    .FLEN(`FLEN),
    .XLEN(XLEN)
  ) fpu_inst (
    .clk(clk),
    .reset_n(reset_n),
    .start(fpu_start),
    .fp_alu_op(idex_fp_alu_op),
    .funct3(idex_funct3),
    .rs2(idex_rs2_addr),
    .funct7(idex_funct7),
    .rounding_mode(ex_fp_rounding_mode),
    .busy(ex_fpu_busy),
    .done(ex_fpu_done),
    .operand_a(ex_fp_operand_a),
    .operand_b(ex_fp_operand_b),
    .operand_c(ex_fp_operand_c),
    .int_operand(ex_alu_operand_a_forwarded),  // For INT→FP conversions (use forwarded rs1)
    .fp_result(ex_fp_result),
    .int_result(ex_int_result_fp),
    .flag_nv(ex_fp_flag_nv),
    .flag_dz(ex_fp_flag_dz),
    .flag_of(ex_fp_flag_of),
    .flag_uf(ex_fp_flag_uf),
    .flag_nx(ex_fp_flag_nx)
  );

  // Debug: FPU output
  `ifdef DEBUG_FPU_CONVERTER
  always @(posedge clk) begin
    if (ex_fpu_done) begin
      $display("[%0t] [FPU] done=1, fp_result=0x%h, busy=%b", $time, ex_fp_result, ex_fpu_busy);
    end
  end
  `endif

  // Store data paths: Separate integer and FP paths for RV32D support
  // Integer stores (SB, SH, SW, SD on RV64): Use forwarded integer rs2
  // FP stores (FSW, FSD): Use FP register data
  wire [XLEN-1:0] ex_mem_write_data_mux;       // Integer store data
  wire [`FLEN-1:0] ex_fp_mem_write_data_mux;   // FP store data

  assign ex_mem_write_data_mux    = ex_rs2_data_forwarded;  // Integer stores always use integer rs2
  assign ex_fp_mem_write_data_mux = ex_fp_operand_b;        // FP stores use FP rs2

  //==========================================================================
  // CSR MRET/SRET Forwarding
  //==========================================================================
  // When MRET/SRET is in MEM stage, it updates mstatus at the end of the cycle.
  // If a CSR read of mstatus/sstatus is in EX stage, it needs the updated value.
  // Forward the "next" mstatus value to avoid reading stale data.
  // Note: MSTATUS bit positions and CSR addresses defined in rv_csr_defines.vh

  // Compute the "next" mstatus value after MRET
  function [XLEN-1:0] compute_mstatus_after_mret;
    input [XLEN-1:0] current_mstatus;
    input mpie_val;
    reg [XLEN-1:0] next_mstatus;
    begin
      next_mstatus = current_mstatus;
      // MIE ← MPIE
      next_mstatus[MSTATUS_MIE_BIT] = mpie_val;
      // MPIE ← 1
      next_mstatus[MSTATUS_MPIE_BIT] = 1'b1;
      // MPP ← U (2'b00)
      next_mstatus[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] = 2'b00;
      compute_mstatus_after_mret = next_mstatus;
    end
  endfunction

  // Compute the "next" mstatus value after SRET
  function [XLEN-1:0] compute_mstatus_after_sret;
    input [XLEN-1:0] current_mstatus;
    input spie_val;
    reg [XLEN-1:0] next_mstatus;
    begin
      next_mstatus = current_mstatus;
      // SIE ← SPIE
      next_mstatus[MSTATUS_SIE_BIT] = spie_val;
      // SPIE ← 1
      next_mstatus[MSTATUS_SPIE_BIT] = 1'b1;
      // SPP ← U (1'b0)
      next_mstatus[MSTATUS_SPP_BIT] = 1'b0;
      compute_mstatus_after_sret = next_mstatus;
    end
  endfunction

  // Construct current mstatus from individual bits (matching csr_file.v format)
  wire [XLEN-1:0] current_mstatus_reconstructed;
  assign current_mstatus_reconstructed = {
    {(XLEN-32){1'b0}},           // Upper bits (if XLEN > 32)
    12'b0,                        // Reserved bits [31:20]
    mstatus_mxr,                  // MXR [19]
    mstatus_sum,                  // SUM [18]
    5'b0,                         // Reserved bits [17:13]
    mpp,                          // MPP [12:11]
    2'b0,                         // Reserved [10:9]
    spp,                          // SPP [8]
    mstatus_mpie,                 // MPIE [7]
    1'b0,                         // Reserved [6]
    mstatus_spie,                 // SPIE [5]
    1'b0,                         // Reserved [4]
    mstatus_mie,                  // MIE [3]
    1'b0,                         // Reserved [2]
    mstatus_sie,                  // SIE [1]
    1'b0                          // Reserved [0]
  };

  // Track MRET/SRET from previous cycle (for forwarding after hazard stall)
  // These flags must stay set until the CSR read that caused the hazard actually executes
  reg exmem_is_mret_r;
  reg exmem_is_sret_r;
  reg exmem_valid_r;

  // Detect when a CSR instruction consumes the forwarding
  // Only consume if the CSR read will actually complete (not invalidated by exception)
  wire mret_forward_consumed = exmem_is_mret_r && idex_is_csr && idex_valid && !exception &&
                                ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));
  wire sret_forward_consumed = exmem_is_sret_r && idex_is_csr && idex_valid && !exception &&
                                ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      exmem_is_mret_r <= 1'b0;
      exmem_is_sret_r <= 1'b0;
      exmem_valid_r <= 1'b0;
    end else begin
      // Set when MRET/SRET is in MEM, clear when CSR read consumes it
      if (mret_forward_consumed) begin
        exmem_is_mret_r <= 1'b0;  // Clear when forwarding is consumed
      end else if (exmem_is_mret && exmem_valid && !exception) begin
        exmem_is_mret_r <= 1'b1;  // Set when MRET enters MEM
      end
      // Else: hold current value (stays set during stall)

      if (sret_forward_consumed) begin
        exmem_is_sret_r <= 1'b0;  // Clear when forwarding is consumed
      end else if (exmem_is_sret && exmem_valid && !exception) begin
        exmem_is_sret_r <= 1'b1;  // Set when SRET enters MEM
      end
      // Else: hold current value (stays set during stall)

      exmem_valid_r <= exmem_valid;

      `ifdef DEBUG_CSR_FORWARD
      if (exmem_is_mret && exmem_valid) begin
        $display("[CSR_FORWARD] MRET in MEM: setting mret_r");
      end
      if (mret_forward_consumed) begin
        $display("[CSR_FORWARD] CSR read consumed MRET forwarding: clearing mret_r");
      end
      if (exmem_is_mret_r && !mret_forward_consumed) begin
        $display("[CSR_FORWARD] Holding mret_r: waiting for CSR read in EX");
      end
      `endif
    end
  end

  // Forward mstatus if:
  // Case 1: MRET is in MEM stage NOW (same cycle - no stall occurred)
  // Case 2: MRET was in MEM stage LAST cycle (CSR stalled, now advancing)
  // CSR being read must be mstatus or sstatus
  wire forward_mret_mstatus = ((exmem_is_mret && exmem_valid && !exception) || exmem_is_mret_r) &&
                              (idex_is_csr && idex_valid) &&
                              ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));

  wire forward_sret_mstatus = ((exmem_is_sret && exmem_valid && !exception) || exmem_is_sret_r) &&
                              (idex_is_csr && idex_valid) &&
                              ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS));

  wire [XLEN-1:0] ex_csr_rdata_forwarded;
  // If MRET/SRET was last cycle, mstatus is already updated - just use current value
  // If MRET/SRET is this cycle, compute what it will be
  wire [XLEN-1:0] mstatus_after_mret = exmem_is_mret_r ? current_mstatus_reconstructed :
                                        compute_mstatus_after_mret(current_mstatus_reconstructed, mstatus_mpie);
  wire [XLEN-1:0] mstatus_after_sret = exmem_is_sret_r ? current_mstatus_reconstructed :
                                        compute_mstatus_after_sret(current_mstatus_reconstructed, mstatus_spie);

  assign ex_csr_rdata_forwarded = forward_mret_mstatus ? mstatus_after_mret :
                                  forward_sret_mstatus ? mstatus_after_sret :
                                  ex_csr_rdata;  // Normal case: no forwarding needed

  `ifdef DEBUG_CSR_FORWARD
  always @(posedge clk) begin
    if (forward_mret_mstatus || forward_sret_mstatus) begin
      $display("[CSR_FORWARD] Time=%0t forward_mret=%b forward_sret=%b", $time, forward_mret_mstatus, forward_sret_mstatus);
      $display("[CSR_FORWARD]   current_mstatus=%h forwarded_mstatus=%h", current_mstatus_reconstructed, ex_csr_rdata_forwarded);
      $display("[CSR_FORWARD]   exmem_is_mret=%b exmem_is_sret=%b exmem_valid=%b", exmem_is_mret, exmem_is_sret, exmem_valid);
      $display("[CSR_FORWARD]   idex_is_csr=%b idex_valid=%b idex_csr_addr=%h", idex_is_csr, idex_valid, idex_csr_addr);
    end
    if (idex_is_csr && idex_valid && ((idex_csr_addr == CSR_MSTATUS) || (idex_csr_addr == CSR_SSTATUS))) begin
      $display("[CSR_FORWARD] CSR read: addr=%h rdata=%h (forwarded=%h)", idex_csr_addr, ex_csr_rdata, ex_csr_rdata_forwarded);
      $display("[CSR_FORWARD]   Conditions: exmem_mret=%b exmem_mret_r=%b exmem_valid=%b exc=%b exc_code=%d",
               exmem_is_mret, exmem_is_mret_r, exmem_valid, exception, exception_code);
      $display("[CSR_FORWARD]   forward_mret=%b forward_sret=%b", forward_mret_mstatus, forward_sret_mstatus);
      $display("[CSR_FORWARD]   idex: PC=%h instr=%h is_ebreak=%b is_ecall=%b illegal=%b",
               idex_pc, idex_instruction, idex_is_ebreak, idex_is_ecall, idex_illegal_inst);
    end
  end
  `endif

  //==========================================================================
  // Privilege Mode Forwarding (Bug Fix: Phase 6)
  //==========================================================================
  // When MRET/SRET is in MEM stage, it updates current_priv at the end of the cycle.
  // However, instructions already in earlier pipeline stages (IF/ID/EX) use the OLD
  // current_priv for CSR privilege checks and exception delegation decisions.
  //
  // This causes incorrect behavior when a CSR access immediately follows MRET/SRET:
  // - Example: MRET changes M→S, next instruction accesses CSR
  // - CSR check sees old priv=M instead of new priv=S
  // - Delegation decision is wrong (M-mode traps never delegate)
  //
  // Solution: Forward the new privilege mode from MEM stage to earlier stages.
  //
  // Timeline:
  //   Cycle N:   MRET in MEM stage, next_instr in EX stage
  //              - MRET computes new_priv from MPP
  //              - Forward new_priv to EX stage
  //              - next_instr uses forwarded_priv for CSR checks
  //   Cycle N+1: MRET flush, current_priv updated
  //
  // Note: Similar to CSR data forwarding, but for privilege mode.

  // Compute new privilege mode from MRET/SRET in MEM stage
  wire [1:0] mret_new_priv = mpp;              // MRET restores from MPP
  wire [1:0] sret_new_priv = {1'b0, spp};      // SRET restores from SPP (0=U, 1=S)

  // Forward privilege mode when MRET/SRET is in MEM stage
  wire forward_priv_mode = (exmem_is_mret || exmem_is_sret) && exmem_valid && !exception;

  // Effective privilege mode for EX stage (used for CSR checks and delegation)
  wire [1:0] effective_priv = forward_priv_mode ?
                              (exmem_is_mret ? mret_new_priv : sret_new_priv) :
                              current_priv;

  `ifdef DEBUG_PRIV
  always @(posedge clk) begin
    if (forward_priv_mode) begin
      $display("[PRIV_FORWARD] Time=%0t Forwarding privilege: %s in MEM, current_priv=%b -> effective_priv=%b",
               $time, exmem_is_mret ? "MRET" : "SRET", current_priv, effective_priv);
      if (idex_is_csr && idex_valid) begin
        $display("[PRIV_FORWARD]   CSR access in EX: addr=0x%03x will use effective_priv=%b",
                 idex_csr_addr, effective_priv);
      end
    end
  end
  `endif

  //==========================================================================
  // EX/MEM Pipeline Register
  //==========================================================================
  exmem_register #(
    .XLEN(XLEN),
    .FLEN(`FLEN)
  ) exmem_reg (
    .clk(clk),
    .reset_n(reset_n),
    .hold(hold_exmem),
    .alu_result_in(ex_alu_result),
    .mem_write_data_in(ex_mem_write_data_mux),          // Integer store data
    .fp_mem_write_data_in(ex_fp_mem_write_data_mux),    // FP store data
    .rd_addr_in(idex_rd_addr),
    .pc_plus_4_in(ex_pc_plus_4),
    .funct3_in(idex_funct3),
    .mem_read_in(idex_mem_read),
    .mem_write_in(idex_mem_write),
    .reg_write_in(idex_reg_write),
    .wb_sel_in(idex_wb_sel),
    .valid_in(idex_valid && !exception_taken_r),  // Invalidate if exception occurred last cycle
    .mul_div_result_in(ex_mul_div_result),
    .atomic_result_in(ex_atomic_result),
    .is_atomic_in(idex_is_atomic),
    // CSR inputs
    .csr_addr_in(idex_csr_addr),
    .csr_we_in(idex_csr_we),
    .csr_rdata_in(ex_csr_rdata_forwarded),  // Use forwarded value for MRET/SRET
    // Exception inputs
    // Clear xRET signals only if the xRET itself caused an illegal instruction exception
    // (illegal due to insufficient privilege). This prevents the xRET from propagating
    // to MEM stage and changing the PC when it should trap instead.
    .is_mret_in(idex_is_mret && !(exception && (exception_code == 5'd2))),
    .is_sret_in(idex_is_sret && !(exception && (exception_code == 5'd2))),
    .is_sfence_vma_in(idex_is_sfence_vma),
    .rs1_addr_in(idex_rs1_addr),
    .rs2_addr_in(idex_rs2_addr),
    .rs1_data_in(ex_rs1_data_forwarded),  // Forwarded rs1 data
    .instruction_in(idex_instruction),
    .pc_in(idex_pc),
    // Outputs
    .alu_result_out(exmem_alu_result),
    .mem_write_data_out(exmem_mem_write_data),          // Integer store data
    .fp_mem_write_data_out(exmem_fp_mem_write_data),    // FP store data
    .rd_addr_out(exmem_rd_addr),
    .pc_plus_4_out(exmem_pc_plus_4),
    .funct3_out(exmem_funct3),
    .mem_read_out(exmem_mem_read),
    .mem_write_out(exmem_mem_write),
    .reg_write_out(exmem_reg_write),
    .wb_sel_out(exmem_wb_sel),
    .valid_out(exmem_valid),
    .mul_div_result_out(exmem_mul_div_result),
    .atomic_result_out(exmem_atomic_result),
    .is_atomic_out(exmem_is_atomic),
    // FP inputs
    .fp_result_in(ex_fp_result),
    .int_result_fp_in(ex_int_result_fp),
    .fp_rd_addr_in(idex_fp_rd_addr),
    .fp_reg_write_in(idex_fp_reg_write),
    .int_reg_write_fp_in(idex_int_reg_write_fp),
    .fp_mem_op_in(idex_fp_mem_op),
    .fp_fmt_in(idex_fp_fmt),
    .fp_flag_nv_in(ex_fp_flag_nv),
    .fp_flag_dz_in(ex_fp_flag_dz),
    .fp_flag_of_in(ex_fp_flag_of),
    .fp_flag_uf_in(ex_fp_flag_uf),
    .fp_flag_nx_in(ex_fp_flag_nx),
    // FP outputs
    .fp_result_out(exmem_fp_result),
    .int_result_fp_out(exmem_int_result_fp),
    .fp_rd_addr_out(exmem_fp_rd_addr),
    .fp_reg_write_out(exmem_fp_reg_write),
    .int_reg_write_fp_out(exmem_int_reg_write_fp),
    .fp_mem_op_out(exmem_fp_mem_op),
    .fp_fmt_out(exmem_fp_fmt),
    .fp_flag_nv_out(exmem_fp_flag_nv),
    .fp_flag_dz_out(exmem_fp_flag_dz),
    .fp_flag_of_out(exmem_fp_flag_of),
    .fp_flag_uf_out(exmem_fp_flag_uf),
    .fp_flag_nx_out(exmem_fp_flag_nx),
    // CSR outputs
    .csr_addr_out(exmem_csr_addr),
    .csr_we_out(exmem_csr_we),
    .csr_rdata_out(exmem_csr_rdata),
    // Exception outputs
    .is_mret_out(exmem_is_mret),
    .is_sret_out(exmem_is_sret),
    .is_sfence_vma_out(exmem_is_sfence_vma),
    .rs1_addr_out(exmem_rs1_addr),
    .rs2_addr_out(exmem_rs2_addr),
    .rs1_data_out(exmem_rs1_data),
    .instruction_out(exmem_instruction),
    .pc_out(exmem_pc)
  );

  // Debug: EX/MEM FP register transfers
  `ifdef DEBUG_FPU_CONVERTER
  always @(posedge clk) begin
    if (exmem_fp_reg_write) begin
      $display("[%0t] [EXMEM] FP transfer: f%0d <= 0x%h (fp_result)",
               $time, exmem_fp_rd_addr, exmem_fp_result);
    end
  end
  `endif

  // Debug: EX/MEM register transfers
  `ifdef DEBUG_EXMEM
  always @(posedge clk) begin
    if (exmem_valid && exmem_reg_write && exmem_rd_addr != 5'b0) begin
      $display("[EXMEM] @%0t pc=%h alu_result=%h rd=x%0d wb_sel=%b",
               $time, exmem_pc, exmem_alu_result, exmem_rd_addr, exmem_wb_sel);
    end
  end
  `endif

  //==========================================================================
  // MEM STAGE: Memory Access
  //==========================================================================

  // Exception prevention: Don't write memory or registers if exception is active
  // Gate memory and register writes only for MEM-stage exceptions (preserve precise exceptions)
  // EX-stage exceptions (EBREAK, ECALL, illegal inst) should not prevent MEM stage from completing
  wire mem_write_gated = exmem_mem_write && !exception_from_mem;
  wire reg_write_gated = exmem_reg_write && !exception_from_mem;

  // Memory Arbitration: Atomic unit gets priority when it's active
  // When atomic operation is executing, atomic unit controls memory
  // Otherwise, normal load/store path from MEM stage controls memory
  wire [XLEN-1:0] dmem_addr;
  wire [63:0]     dmem_write_data;  // 64-bit for RV32D/RV64D support
  wire            dmem_mem_read;
  wire            dmem_mem_write;
  wire [2:0]      dmem_funct3;

  // Determine if this is an FP store operation (FSW or FSD)
  // FP stores are memory write operations with fp_mem_op active
  wire is_fp_store = exmem_mem_write && exmem_fp_mem_op;

  // Use atomic unit's memory interface when atomic unit is busy
  // Otherwise, choose between integer and FP write data for stores
  assign dmem_addr       = ex_atomic_busy ? ex_atomic_mem_addr : exmem_alu_result;
  assign dmem_write_data = ex_atomic_busy ? {{(64-XLEN){1'b0}}, ex_atomic_mem_wdata} :  // Zero-extend atomic data
                           is_fp_store    ? exmem_fp_mem_write_data :                    // FP store: use full FLEN bits
                                            {{(64-XLEN){1'b0}}, exmem_mem_write_data};   // INT store: zero-extend to 64 bits
  assign dmem_mem_read   = ex_atomic_busy ? ex_atomic_mem_req && !ex_atomic_mem_we : exmem_mem_read;
  assign dmem_mem_write  = ex_atomic_busy ? ex_atomic_mem_req && ex_atomic_mem_we : mem_write_gated;
  assign dmem_funct3     = ex_atomic_busy ? ex_atomic_mem_size : exmem_funct3;

  // Atomic unit sees memory as always ready (synchronous memory, 1-cycle latency)
  assign ex_atomic_mem_ready = 1'b1;

  //--------------------------------------------------------------------------
  // MMU: Virtual Memory Translation
  //--------------------------------------------------------------------------

  // MMU translation request signals
  // For data accesses: translate virtual address from MEM stage
  // For instruction fetches: translation happens in IF stage (future enhancement)
  assign mmu_req_valid   = exmem_valid && (exmem_mem_read || exmem_mem_write);
  assign mmu_req_vaddr   = exmem_alu_result;  // ALU result is the virtual address
  assign mmu_req_is_store = exmem_mem_write;
  assign mmu_req_is_fetch = 1'b0;  // Data access (instruction fetch MMU in IF stage)
  assign mmu_req_size    = exmem_funct3;  // funct3 encodes access size

  // TLB flush control from SFENCE.VMA instruction
  // SFENCE.VMA in MEM stage: rs1 specifies vaddr, rs2 specifies ASID
  // For now, implement simple flush: rs1=x0 && rs2=x0 => flush all
  wire sfence_flush_all = exmem_is_sfence_vma && (exmem_rs1_addr == 5'h0) && (exmem_rs2_addr == 5'h0);
  wire sfence_flush_vaddr = exmem_is_sfence_vma && (exmem_rs1_addr != 5'h0);
  wire [XLEN-1:0] sfence_vaddr = exmem_rs1_data;  // rs1 data contains virtual address

  assign tlb_flush_all = sfence_flush_all;
  assign tlb_flush_vaddr = sfence_flush_vaddr;
  assign tlb_flush_addr = sfence_vaddr;

  // MMU busy signal: translation in progress (req_valid && !req_ready)
  assign mmu_busy = mmu_req_valid && !mmu_req_ready;

  // Instantiate MMU
  mmu #(
    .XLEN(XLEN),
    .TLB_ENTRIES(16)  // 16-entry TLB
  ) mmu_inst (
    .clk(clk),
    .reset_n(reset_n),
    // Translation request
    .req_valid(mmu_req_valid),
    .req_vaddr(mmu_req_vaddr),
    .req_is_store(mmu_req_is_store),
    .req_is_fetch(mmu_req_is_fetch),
    .req_size(mmu_req_size),
    .req_ready(mmu_req_ready),
    .req_paddr(mmu_req_paddr),
    .req_page_fault(mmu_req_page_fault),
    .req_fault_vaddr(mmu_req_fault_vaddr),
    // Page table walk memory interface
    .ptw_req_valid(mmu_ptw_req_valid),
    .ptw_req_addr(mmu_ptw_req_addr),
    .ptw_req_ready(mmu_ptw_req_ready),
    .ptw_resp_data(mmu_ptw_resp_data),
    .ptw_resp_valid(mmu_ptw_resp_valid),
    // CSR interface
    .satp(csr_satp),
    .privilege_mode(current_priv),
    .mstatus_sum(mstatus_sum),
    .mstatus_mxr(mstatus_mxr),
    // TLB flush control
    .tlb_flush_all(tlb_flush_all),
    .tlb_flush_vaddr(tlb_flush_vaddr),
    .tlb_flush_addr(tlb_flush_addr)
  );

  // Memory Arbiter: Multiplex between CPU data access and MMU PTW
  // Priority: PTW gets priority when active (MMU needs memory for page table walk)
  // Otherwise, normal data memory access
  wire [XLEN-1:0] arb_mem_addr;
  wire [63:0]     arb_mem_write_data;  // 64-bit for RV32D/RV64D support
  wire            arb_mem_read;
  wire            arb_mem_write;
  wire [2:0]      arb_mem_funct3;
  wire [63:0]     arb_mem_read_data;   // 64-bit for RV32D/RV64D support

  // When PTW is active, it gets priority
  // When PTW is not active, use translated address from MMU (or bypass if no MMU)
  // Check if translation is enabled: satp.MODE != 0
  // RV32: satp[31] (1-bit mode), RV64: satp[63:60] (4-bit mode)
  wire translation_enabled = (XLEN == 32) ? csr_satp[31] : (csr_satp[63:60] != 4'b0000);
  wire use_mmu_translation = translation_enabled && mmu_req_ready && !mmu_req_page_fault;
  wire [XLEN-1:0] translated_addr = use_mmu_translation ? mmu_req_paddr : dmem_addr;

  assign arb_mem_addr       = mmu_ptw_req_valid ? mmu_ptw_req_addr : translated_addr;
  assign arb_mem_write_data = dmem_write_data;  // PTW never writes
  assign arb_mem_read       = mmu_ptw_req_valid ? 1'b1 : dmem_mem_read;
  assign arb_mem_write      = mmu_ptw_req_valid ? 1'b0 : dmem_mem_write;
  assign arb_mem_funct3     = mmu_ptw_req_valid ? 3'b010 : dmem_funct3;  // PTW uses word access

  // PTW ready when memory is not busy (synchronous memory, always ready)
  assign mmu_ptw_req_ready = 1'b1;
  // PTW response valid one cycle after request (synchronous memory)
  reg ptw_req_valid_r;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      ptw_req_valid_r <= 1'b0;
    else
      ptw_req_valid_r <= mmu_ptw_req_valid;
  end
  assign mmu_ptw_resp_valid = ptw_req_valid_r;
  assign mmu_ptw_resp_data = arb_mem_read_data;

  //--------------------------------------------------------------------------
  // Bus Master Interface
  //--------------------------------------------------------------------------
  // Connect arbiter signals to bus master port
  // The bus will route requests to DMEM or memory-mapped peripherals
  // Note: funct3 encodes access size: 0=byte, 1=half, 2=word, 3=double
  //
  // CRITICAL FIX (Session 34): Generate bus requests as ONE-SHOT pulses
  // Problem: If MEM stage is held for multiple cycles, the same store would
  //          execute multiple times (e.g., UART character duplication bug)
  // Solution: Track previous MEM stage PC and only assert req_valid when
  //           a NEW instruction enters MEM (detect PC change)
  reg [XLEN-1:0] exmem_pc_prev;
  reg            exmem_valid_prev;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      exmem_pc_prev    <= {XLEN{1'b0}};
      exmem_valid_prev <= 1'b0;
    end else begin
      exmem_pc_prev    <= exmem_pc;
      exmem_valid_prev <= exmem_valid;
    end
  end

  // Generate bus request only on FIRST cycle of an instruction in MEM stage
  // This prevents duplicate requests if the same instruction stays in MEM for multiple cycles
  // New instruction detected when: (PC changed) OR (valid transitions from 0→1)
  wire mem_stage_new_instr = exmem_valid && ((exmem_pc != exmem_pc_prev) || !exmem_valid_prev);

  // Session 40: Track whether we've already issued a bus request for the current instruction
  // This prevents duplicate requests when bus isn't ready (peripherals with FIFOs, busy states)
  // Strategy: Set flag when request issued AND not ready, clear when ready OR new instruction
  reg bus_req_issued;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      bus_req_issued <= 1'b0;
    end else begin
      // Set: When we issue a write pulse (first time)
      if (arb_mem_write_pulse && !bus_req_ready) begin
        bus_req_issued <= 1'b1;
      end
      // Clear: When bus becomes ready OR instruction leaves MEM stage
      else if (bus_req_ready || !exmem_valid) begin
        bus_req_issued <= 1'b0;
      end
    end
  end

  // CRITICAL: Only WRITES need to be one-shot pulses to prevent duplicate side effects
  // READS can be level signals (needed for multi-cycle operations, atomics, etc.)
  // EXCEPTION: Atomic operations (LR/SC, AMO) need LEVEL signals for multi-cycle read-modify-write
  //            The atomic unit controls writes via ex_atomic_busy, so allow continuous writes
  // Session 40: Also check !bus_req_issued to prevent duplicate requests when bus not ready
  wire arb_mem_write_pulse = mmu_ptw_req_valid ? 1'b0 :
                             ex_atomic_busy ? dmem_mem_write :                       // Atomic: level signal
                             (dmem_mem_write && mem_stage_new_instr && !bus_req_issued);  // Normal: one-shot pulse, not already issued

  assign bus_req_valid = arb_mem_read || arb_mem_write_pulse;
  assign bus_req_addr  = arb_mem_addr;
  assign bus_req_wdata = arb_mem_write_data;
  assign bus_req_we    = arb_mem_write_pulse;
  assign bus_req_size  = arb_mem_funct3;

  // Bus read data feeds back to arbiter
  assign arb_mem_read_data = bus_req_rdata;

  //===========================================================================
  // Debug: Bus Transaction Tracing (Session 50 - MTIMECMP write bug)
  //===========================================================================
  `ifdef DEBUG_BUS
  always @(posedge clk) begin
    // Trace ALL bus transactions
    if (bus_req_valid) begin
      if (bus_req_we) begin
        $display("[CORE-BUS-WR] Cycle %0d: addr=0x%08h wdata=0x%016h size=%0d valid=%b ready=%b | PC=%h",
                 $time/10, bus_req_addr, bus_req_wdata, bus_req_size,
                 bus_req_valid, bus_req_ready, exmem_pc);
      end else begin
        $display("[CORE-BUS-RD] Cycle %0d: addr=0x%08h size=%0d valid=%b ready=%b rdata=0x%016h | PC=%h",
                 $time/10, bus_req_addr, bus_req_size,
                 bus_req_valid, bus_req_ready, bus_req_rdata, exmem_pc);
      end

      // Specifically highlight CLINT range accesses (0x0200_0000 - 0x0200_FFFF)
      if (bus_req_addr >= 32'h0200_0000 && bus_req_addr <= 32'h0200_FFFF) begin
        $display("       *** CLINT ACCESS DETECTED *** offset=0x%04h", bus_req_addr[15:0]);
        if (bus_req_addr >= 32'h0200_4000 && bus_req_addr <= 32'h0200_BFF7) begin
          $display("       *** MTIMECMP RANGE *** (should be 0x4000-0xBFF7)");
        end
        if (bus_req_addr == 32'h0200_4000) begin
          $display("       *** MTIMECMP[0] LOWER 32-bit WRITE ***");
        end
        if (bus_req_addr == 32'h0200_4004) begin
          $display("       *** MTIMECMP[0] UPPER 32-bit WRITE ***");
        end
      end

      // Show MEM stage state for debugging
      $display("       MEM: exmem_valid=%b mem_write=%b mem_read=%b new_instr=%b issued=%b",
               exmem_valid, dmem_mem_write, dmem_mem_read, mem_stage_new_instr, bus_req_issued);
    end
  end
  `endif

  // Connect arbiter read data to both integer and FP paths
  // For integer loads, use lower XLEN bits (with sign/zero extension handled by bus slaves)
  // For FP loads, use full FLEN bits
  assign mem_read_data    = arb_mem_read_data[XLEN-1:0];  // Integer loads: lower bits
  assign fp_mem_read_data = arb_mem_read_data;             // FP loads: full 64 bits

  // MEM/WB Pipeline Register
  memwb_register #(
    .XLEN(XLEN),
    .FLEN(`FLEN)
  ) memwb_reg (
    .clk(clk),
    .reset_n(reset_n),
    .alu_result_in(exmem_alu_result),
    .mem_read_data_in(mem_read_data),       // Integer load data
    .fp_mem_read_data_in(fp_mem_read_data), // FP load data
    .rd_addr_in(exmem_rd_addr),
    .pc_plus_4_in(exmem_pc_plus_4),
    .reg_write_in(reg_write_gated),     // Gated to prevent write on exception
    .wb_sel_in(exmem_wb_sel),
    .valid_in(exmem_valid && !exception_from_mem && !hold_exmem),  // Mark invalid only on MEM-stage exception (preserve precise exceptions)
    .mul_div_result_in(exmem_mul_div_result),
    .atomic_result_in(exmem_atomic_result),
    // F/D extension inputs
    .fp_result_in(exmem_fp_result),
    .int_result_fp_in(exmem_int_result_fp),
    .fp_rd_addr_in(exmem_fp_rd_addr),
    .fp_reg_write_in(exmem_fp_reg_write),
    .int_reg_write_fp_in(exmem_int_reg_write_fp),
    .fp_fmt_in(exmem_fp_fmt),
    .fp_flag_nv_in(exmem_fp_flag_nv),
    .fp_flag_dz_in(exmem_fp_flag_dz),
    .fp_flag_of_in(exmem_fp_flag_of),
    .fp_flag_uf_in(exmem_fp_flag_uf),
    .fp_flag_nx_in(exmem_fp_flag_nx),
    // CSR input
    .csr_rdata_in(exmem_csr_rdata),
    .csr_we_in(exmem_csr_we),
    // Outputs
    .alu_result_out(memwb_alu_result),
    .mem_read_data_out(memwb_mem_read_data),       // Integer load data
    .fp_mem_read_data_out(memwb_fp_mem_read_data), // FP load data
    .rd_addr_out(memwb_rd_addr),
    .pc_plus_4_out(memwb_pc_plus_4),
    .reg_write_out(memwb_reg_write),
    .wb_sel_out(memwb_wb_sel),
    .valid_out(memwb_valid),
    .mul_div_result_out(memwb_mul_div_result),
    .atomic_result_out(memwb_atomic_result),
    // F/D extension outputs
    .fp_result_out(memwb_fp_result),
    .int_result_fp_out(memwb_int_result_fp),
    .fp_rd_addr_out(memwb_fp_rd_addr),
    .fp_reg_write_out(memwb_fp_reg_write),
    .int_reg_write_fp_out(memwb_int_reg_write_fp),
    .fp_fmt_out(memwb_fp_fmt),
    .fp_flag_nv_out(memwb_fp_flag_nv),
    .fp_flag_dz_out(memwb_fp_flag_dz),
    .fp_flag_of_out(memwb_fp_flag_of),
    .fp_flag_uf_out(memwb_fp_flag_uf),
    .fp_flag_nx_out(memwb_fp_flag_nx),
    // CSR output
    .csr_rdata_out(memwb_csr_rdata),
    .csr_we_out(memwb_csr_we)
  );

  // Debug: MEM/WB FP register transfers
  `ifdef DEBUG_FPU_CONVERTER
  always @(posedge clk) begin
    if (memwb_fp_reg_write) begin
      $display("[%0t] [MEMWB] FP transfer: f%0d <= 0x%h (wb_sel=%b)",
               $time, memwb_fp_rd_addr, memwb_fp_result, memwb_wb_sel);
    end
  end
  `endif

  // Debug: FCVT Pipeline Tracing
  `ifdef DEBUG_FCVT_PIPELINE
  always @(posedge clk) begin
    // Track FCVT in ID/EX stage
    if (idex_fp_alu_en && idex_fp_alu_op == 5'b01010 && idex_valid) begin
      $display("[%0t] [IDEX] FCVT: fp_reg_write=%b, fp_rd_addr=f%0d, valid=%b, pc=%h",
               $time, idex_fp_reg_write, idex_fp_rd_addr, idex_valid, idex_pc);
    end
    // Track FCVT in EX/MEM stage
    if (exmem_fp_reg_write && exmem_valid) begin
      $display("[%0t] [EXMEM] FCVT: fp_reg_write=%b, fp_rd_addr=f%0d, valid=%b, pc=%h, fp_result=%h",
               $time, exmem_fp_reg_write, exmem_fp_rd_addr, exmem_valid, exmem_pc, exmem_fp_result);
    end
    // Track FCVT in MEM/WB stage
    if (memwb_fp_reg_write && memwb_valid) begin
      $display("[%0t] [MEMWB] FCVT: fp_reg_write=%b, fp_rd_addr=f%0d, valid=%b, fp_result=%h",
               $time, memwb_fp_reg_write, memwb_fp_rd_addr, memwb_valid, memwb_fp_result);
    end
  end
  `endif

  // Debug: MEM/WB register transfers
  `ifdef DEBUG_MEMWB
  always @(posedge clk) begin
    if (memwb_valid && memwb_reg_write && memwb_rd_addr != 5'b0) begin
      $display("[MEMWB] @%0t alu_result=%h rd=x%0d wb_sel=%b",
               $time, memwb_alu_result, memwb_rd_addr, memwb_wb_sel);
    end
  end
  `endif

  //==========================================================================
  // WB STAGE: Write Back
  //==========================================================================

  // Write-Back Data Selection (Integer Register File)
  assign wb_data = (memwb_wb_sel == 3'b000) ? memwb_alu_result :      // ALU result
                   (memwb_wb_sel == 3'b001) ? memwb_mem_read_data :   // Memory data
                   (memwb_wb_sel == 3'b010) ? memwb_pc_plus_4 :       // PC + 4 (JAL/JALR)
                   (memwb_wb_sel == 3'b011) ? memwb_csr_rdata :       // CSR data
                   (memwb_wb_sel == 3'b100) ? memwb_mul_div_result :  // M extension result
                   (memwb_wb_sel == 3'b101) ? memwb_atomic_result :   // A extension result
                   (memwb_wb_sel == 3'b110) ? memwb_int_result_fp :   // FPU integer result (FP compare, FCLASS, FMV.X.W, FCVT.W.S)
                   {XLEN{1'b0}};

  // Debug: WB stage register file writes
  `ifdef DEBUG_REGFILE_WB
  always @(posedge clk) begin
    // Show both gated and non-gated writes for debugging
    if ((memwb_reg_write || memwb_int_reg_write_fp) && memwb_rd_addr != 5'b0) begin
      if (memwb_valid) begin
        $display("[REGFILE_WB] @%0t Writing rd=x%0d data=%h (wb_sel=%b valid=1 alu=%h mem=%h mul_div=%h)",
                 $time, memwb_rd_addr, wb_data, memwb_wb_sel,
                 memwb_alu_result, memwb_mem_read_data, memwb_mul_div_result);
      end else begin
        $display("[REGFILE_WB] @%0t BLOCKED rd=x%0d data=%h (wb_sel=%b valid=0 GATED BY WRITEBACK LOGIC)",
                 $time, memwb_rd_addr, wb_data, memwb_wb_sel);
      end
    end
  end
  `endif

  // F/D Extension: FP Write-Back Data Selection
  // FP results go to FP register file, INT-to-FP conversions also go to FP register file
  // FP loads (FLW/FLD) also write to FP register file through fp_mem_read_data
  // Detect FP load by checking wb_sel == 001 (memory data) and fp_reg_write is set
  // For FLW (single-precision load when FLEN=64), NaN-box the loaded value
  wire [`FLEN-1:0] fp_load_data_boxed;
  assign fp_load_data_boxed = (`FLEN == 64 && !memwb_fp_fmt) ? {32'hFFFFFFFF, memwb_fp_mem_read_data[31:0]} : memwb_fp_mem_read_data;

  assign wb_fp_data = (memwb_wb_sel == 3'b001) ? fp_load_data_boxed :  // FP load (NaN-boxed for FLW)
                      memwb_fp_result;                                   // FP ALU result

  // FP-to-INT operations write to integer register file via memwb_int_result_fp:
  // - FP compare (FEQ, FLT, FLE): wb_sel = 3'b110
  // - FP classify (FCLASS): wb_sel = 3'b110
  // - FP move to int (FMV.X.W): wb_sel = 3'b110
  // - FP to int convert (FCVT.W.S, FCVT.WU.S): wb_sel = 3'b110

  //==========================================================================
  // DEBUG: PC Trace for MRET/SRET to Compressed Instructions (Bug #41)
  //==========================================================================
  `ifdef DEBUG_MRET_RVC
  reg [31:0] cycle_count;
  reg prev_mret_flush, prev_sret_flush;
  reg [31:0] prev_pc;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      cycle_count <= 0;
      prev_mret_flush <= 0;
      prev_sret_flush <= 0;
      prev_pc <= 0;
    end else begin
      cycle_count <= cycle_count + 1;

      // Display PC trace every cycle
      $display("[CYC %0d] PC=%h PC_next=%h PC_inc=%h | instr_raw=%h is_comp=%b | mret_fl=%b sret_fl=%b trap_fl=%b exc_code=%h | stall=%b flush_if=%b",
               cycle_count, pc_current, pc_next, pc_increment,
               if_instruction_raw, if_is_compressed,
               mret_flush, sret_flush, trap_flush, exception_code,
               stall_pc, flush_ifid);

      // Detailed trace when exception occurs
      if (trap_flush) begin
        $display("  [TRAP] exc_pc=%h exc_val=%h exc_code=%h vector=%h",
                 exception_pc, exception_val, exception_code, trap_vector);
      end

      // Detailed trace when MRET/SRET occurs
      if (mret_flush || sret_flush) begin
        $display("  [%s_FLUSH] Target PC=%h (from %s)",
                 mret_flush ? "MRET" : "SRET",
                 mret_flush ? mepc : sepc,
                 mret_flush ? "MEPC" : "SEPC");
      end

      // Track instruction fetch after xRET
      if (cycle_count > 0 && (prev_mret_flush || prev_sret_flush)) begin
        $display("  [POST_xRET] Fetched instr_raw=%h at PC=%h | is_compressed=%b pc_inc=%h",
                 if_instruction_raw, pc_current, if_is_compressed, pc_increment);
      end

      // Detect potential infinite loop (PC not changing)
      if (cycle_count > 2 && pc_current == prev_pc && !stall_pc) begin
        $display("  [WARNING] PC stuck at %h (not stalling!)", pc_current);
      end

      // Update previous values
      prev_mret_flush <= mret_flush;
      prev_sret_flush <= sret_flush;
      prev_pc <= pc_current;
    end
  end
  `endif

  //==========================================================================
  // DEBUG: Track writes to a0 (x10) to debug Bug #48
  //==========================================================================
  `ifdef DEBUG_A0_TRACKING
  integer cycle_count_a0;

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      cycle_count_a0 <= 0;
    else
      cycle_count_a0 <= cycle_count_a0 + 1;
  end

  // Also track when instructions that write to a0 are in earlier stages
  always @(posedge clk) begin
    // Track writeback
    if (memwb_valid && memwb_reg_write && memwb_rd_addr == 5'd10) begin
      $display("[A0_WRITE] cycle=%0d x10 <= 0x%08h (wb_sel=%b source=%s alu=0x%08h mem=0x%08h)",
               cycle_count_a0, wb_data, memwb_wb_sel,
               (memwb_wb_sel == 3'b000) ? "ALU    " :
               (memwb_wb_sel == 3'b001) ? "MEM    " :
               (memwb_wb_sel == 3'b010) ? "PC+4   " :
               (memwb_wb_sel == 3'b110) ? "FP2INT " : "OTHER  ",
               memwb_alu_result, memwb_mem_read_data);
    end

    // Track EX stage to see PC and instruction
    if (idex_valid && idex_reg_write && idex_rd_addr == 5'd10) begin
      $display("[A0_EX   ] cycle=%0d PC=0x%08h instr=0x%08h opcode=%b rd=x10",
               cycle_count_a0, idex_pc, idex_instruction, idex_instruction[6:0]);
    end
  end
  `endif

endmodule
