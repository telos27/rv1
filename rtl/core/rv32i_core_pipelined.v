// rv_core_pipelined.v - 5-Stage Pipelined RISC-V Processor Core
// Implements classic RISC pipeline: IF -> ID -> EX -> MEM -> WB
// Includes data forwarding and hazard detection
// Parameterized for RV32/RV64 support
// Author: RV1 Project
// Date: 2025-10-10

`include "config/rv_config.vh"

module rv_core_pipelined #(
  parameter XLEN = `XLEN,
  parameter RESET_VECTOR = {XLEN{1'b0}},
  parameter IMEM_SIZE = 4096,
  parameter DMEM_SIZE = 16384,
  parameter MEM_FILE = ""
) (
  input  wire             clk,
  input  wire             reset_n,
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
  wire [1:0] forward_a;    // Forwarding select for ALU operand A
  wire [1:0] forward_b;    // Forwarding select for ALU operand B

  // Trap/exception control
  wire trap_flush;         // Flush pipeline on trap
  wire mret_flush;         // Flush pipeline on MRET

  //==========================================================================
  // IF Stage Signals
  //==========================================================================
  wire [XLEN-1:0] pc_current;
  wire [XLEN-1:0] pc_next;
  wire [XLEN-1:0] pc_plus_4;
  wire [31:0]     if_instruction;  // Instructions always 32-bit

  //==========================================================================
  // IF/ID Pipeline Register Outputs
  //==========================================================================
  wire [XLEN-1:0] ifid_pc;
  wire [31:0]     ifid_instruction;  // Instructions always 32-bit
  wire            ifid_valid;

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
  wire            id_csr_we;
  wire            id_csr_src;
  wire [XLEN-1:0] id_csr_wdata;

  // Exception signals
  wire            id_is_ecall;
  wire            id_is_ebreak;
  wire            id_is_mret;
  wire            id_illegal_inst;

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
  wire [XLEN-1:0] id_fp_rs1_data;
  wire [XLEN-1:0] id_fp_rs2_data;
  wire [XLEN-1:0] id_fp_rs3_data;
  wire [XLEN-1:0] id_fp_rs1_data_raw; // Raw FP register file output
  wire [XLEN-1:0] id_fp_rs2_data_raw;
  wire [XLEN-1:0] id_fp_rs3_data_raw;

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
  wire [XLEN-1:0] idex_fp_rs1_data;
  wire [XLEN-1:0] idex_fp_rs2_data;
  wire [XLEN-1:0] idex_fp_rs3_data;
  wire [4:0]      idex_fp_rs1_addr;
  wire [4:0]      idex_fp_rs2_addr;
  wire [4:0]      idex_fp_rs3_addr;
  wire [4:0]      idex_fp_rd_addr;
  wire            idex_fp_reg_write;
  wire            idex_int_reg_write_fp;
  wire            idex_fp_alu_en;
  wire [4:0]      idex_fp_alu_op;
  wire [2:0]      idex_fp_rm;
  wire            idex_fp_use_dynamic_rm;
  wire [11:0]     idex_csr_addr;
  wire            idex_csr_we;
  wire            idex_csr_src;
  wire [XLEN-1:0] idex_csr_wdata;
  wire            idex_is_ecall;
  wire            idex_is_ebreak;
  wire            idex_is_mret;
  wire            idex_illegal_inst;
  wire [31:0]     idex_instruction;  // Instructions always 32-bit

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
  wire [XLEN-1:0] ex_fp_operand_a;        // FP operand A (potentially forwarded)
  wire [XLEN-1:0] ex_fp_operand_b;        // FP operand B (potentially forwarded)
  wire [XLEN-1:0] ex_fp_operand_c;        // FP operand C (potentially forwarded, for FMA)
  wire [XLEN-1:0] ex_fp_result;           // FP result from FPU
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

  // Hold EX/MEM register when M instruction or A instruction or FP instruction is executing
  wire            hold_exmem;
  assign hold_exmem = (idex_is_mul_div && idex_valid && !ex_mul_div_ready) ||
                      (idex_is_atomic && idex_valid && !ex_atomic_done) ||
                      (idex_fp_alu_en && idex_valid && !ex_fpu_done);

  // M unit start signal: pulse once when M instruction first enters EX
  // Only start if not already busy or ready (prevents restarting)
  wire            m_unit_start;
  assign m_unit_start = idex_is_mul_div && idex_valid && !ex_mul_div_busy && !ex_mul_div_ready;

  // FPU start signal: pulse once when FP instruction first enters EX
  wire            fpu_start;
  assign fpu_start = idex_fp_alu_en && idex_valid && !ex_fpu_busy && !ex_fpu_done;

  //==========================================================================
  // EX/MEM Pipeline Register Outputs
  //==========================================================================
  wire [XLEN-1:0] exmem_alu_result;
  wire [XLEN-1:0] exmem_mem_write_data;
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
  wire [XLEN-1:0] exmem_fp_result;
  wire [XLEN-1:0] exmem_int_result_fp;
  wire [4:0]      exmem_fp_rd_addr;
  wire            exmem_fp_reg_write;
  wire            exmem_int_reg_write_fp;
  wire            exmem_fp_flag_nv;
  wire            exmem_fp_flag_dz;
  wire            exmem_fp_flag_of;
  wire            exmem_fp_flag_uf;
  wire            exmem_fp_flag_nx;
  wire [11:0]     exmem_csr_addr;
  wire            exmem_csr_we;
  wire [XLEN-1:0] exmem_csr_rdata;
  wire            exmem_is_mret;
  wire [31:0]     exmem_instruction;  // Instructions always 32-bit
  wire [XLEN-1:0] exmem_pc;

  //==========================================================================
  // MEM Stage Signals
  //==========================================================================
  wire [XLEN-1:0] mem_read_data;

  //==========================================================================
  // MEM/WB Pipeline Register Outputs
  //==========================================================================
  wire [XLEN-1:0] memwb_alu_result;
  wire [XLEN-1:0] memwb_mem_read_data;
  wire [4:0]      memwb_rd_addr;
  wire [XLEN-1:0] memwb_pc_plus_4;
  wire            memwb_reg_write;
  wire [2:0]      memwb_wb_sel;
  wire            memwb_valid;
  wire [XLEN-1:0] memwb_mul_div_result;
  wire [XLEN-1:0] memwb_atomic_result;
  wire [XLEN-1:0] memwb_fp_result;
  wire [XLEN-1:0] memwb_int_result_fp;
  wire [4:0]      memwb_fp_rd_addr;
  wire            memwb_fp_reg_write;
  wire            memwb_int_reg_write_fp;
  wire            memwb_fp_flag_nv;
  wire            memwb_fp_flag_dz;
  wire            memwb_fp_flag_of;
  wire            memwb_fp_flag_uf;
  wire            memwb_fp_flag_nx;
  wire [XLEN-1:0] memwb_csr_rdata;

  //==========================================================================
  // CSR and Exception Signals
  //==========================================================================
  wire            exception;
  wire [4:0]      exception_code;     // 5-bit exception code for mcause
  wire [XLEN-1:0] exception_pc;
  wire [XLEN-1:0] exception_val;
  wire [XLEN-1:0] trap_vector;
  wire [XLEN-1:0] mepc;
  wire            mstatus_mie;
  wire [2:0]      csr_frm;            // FP rounding mode from frm CSR
  wire [4:0]      csr_fflags;         // FP exception flags from fflags CSR

  //==========================================================================
  // WB Stage Signals
  //==========================================================================
  wire [XLEN-1:0] wb_data;
  wire [XLEN-1:0] wb_fp_data;         // FP write-back data

  //==========================================================================
  // Debug outputs
  //==========================================================================
  assign pc_out = pc_current;
  assign instr_out = if_instruction;

  //==========================================================================
  // IF STAGE: Instruction Fetch
  //==========================================================================

  // PC calculation
  assign pc_plus_4 = pc_current + {{(XLEN-3){1'b0}}, 3'b100};  // PC + 4

  // Trap and MRET handling
  assign trap_flush = exception;  // Exception occurred
  assign mret_flush = exmem_is_mret && exmem_valid;  // MRET in MEM stage

  // Track exception from previous cycle to prevent re-triggering
  reg exception_taken_r;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n)
      exception_taken_r <= 1'b0;
    else
      exception_taken_r <= exception;
  end

  // PC selection: priority order - trap > mret > branch/jump > PC+4
  assign pc_next = trap_flush ? trap_vector :
                   mret_flush ? mepc :
                   ex_take_branch ? (idex_jump ? ex_jump_target : ex_branch_target) :
                   pc_plus_4;

  // Pipeline flush: trap/MRET flushes all stages, branch flushes IF/ID and ID/EX
  assign flush_ifid = trap_flush | mret_flush | ex_take_branch;
  assign flush_idex = trap_flush | mret_flush | flush_idex_hazard | ex_take_branch;

  // Program Counter
  pc #(
    .XLEN(XLEN),
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
    .XLEN(XLEN),
    .MEM_SIZE(IMEM_SIZE),
    .MEM_FILE(MEM_FILE)
  ) imem (
    .addr(pc_current),
    .instruction(if_instruction)
  );

  // IF/ID Pipeline Register
  ifid_register #(
    .XLEN(XLEN)
  ) ifid_reg (
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
    .is_csr(id_is_csr_dec),
    .is_ecall(id_is_ecall_dec),
    .is_ebreak(id_is_ebreak_dec),
    .is_mret(id_is_mret_dec),
    .is_mul_div(id_is_mul_div_dec),
    .mul_div_op(id_mul_div_op_dec),
    .is_word_op(id_is_word_op_dec),
    // A extension outputs
    .is_atomic(id_is_atomic_dec),
    .funct5(id_funct5_dec),
    .aq(id_aq_dec),
    .rl(id_rl_dec)
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
    .is_mul_div(id_is_mul_div_dec),
    .mul_div_op(id_mul_div_op_dec),
    .is_word_op(id_is_word_op_dec),
    .is_atomic(id_is_atomic_dec),
    .funct5(id_funct5_dec),
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
    .illegal_inst(id_illegal_inst)
  );

  // Pass through decoder flags for pipeline
  assign id_is_ecall = id_is_ecall_dec;
  assign id_is_ebreak = id_is_ebreak_dec;
  assign id_is_mret = id_is_mret_dec;

  // Register File
  wire [XLEN-1:0] id_rs1_data_raw;  // Raw register file output
  wire [XLEN-1:0] id_rs2_data_raw;  // Raw register file output

  register_file #(
    .XLEN(XLEN)
  ) regfile (
    .clk(clk),
    .reset_n(reset_n),
    .rs1_addr(id_rs1),
    .rs2_addr(id_rs2),
    .rd_addr(memwb_rd_addr),          // Write from WB stage
    .rd_data(wb_data),                // Write data from WB stage
    .rd_wen(memwb_reg_write),         // Write enable from WB stage
    .rs1_data(id_rs1_data_raw),
    .rs2_data(id_rs2_data_raw)
  );

  // WB-to-ID Forwarding (Register File Bypass)
  // Forward from WB stage if reading the same register being written
  assign id_rs1_data = (memwb_reg_write && (memwb_rd_addr != 5'h0) && (memwb_rd_addr == id_rs1))
                       ? wb_data : id_rs1_data_raw;

  assign id_rs2_data = (memwb_reg_write && (memwb_rd_addr != 5'h0) && (memwb_rd_addr == id_rs2))
                       ? wb_data : id_rs2_data_raw;

  // Immediate Selection
  assign id_immediate = (id_imm_sel == 3'b000) ? id_imm_i :
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
    .idex_mem_read(idex_mem_read),
    .idex_rd(idex_rd_addr),
    .ifid_rs1(id_rs1),
    .ifid_rs2(id_rs2),
    .mul_div_busy(ex_mul_div_busy),
    .idex_is_mul_div(idex_is_mul_div),
    .atomic_busy(ex_atomic_busy),
    .atomic_done(ex_atomic_done),
    .idex_is_atomic(idex_is_atomic),
    .stall_pc(stall_pc),
    .stall_ifid(stall_ifid),
    .bubble_idex(flush_idex_hazard)
  );

  // ID/EX Pipeline Register
  idex_register #(
    .XLEN(XLEN)
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
    // CSR inputs
    .csr_addr_in(id_csr_addr),
    .csr_we_in(id_csr_we_actual),
    .csr_src_in(id_csr_src),
    .csr_wdata_in(id_csr_wdata),
    // Exception inputs
    .is_ecall_in(id_is_ecall),
    .is_ebreak_in(id_is_ebreak),
    .is_mret_in(id_is_mret),
    .illegal_inst_in(id_illegal_inst),
    .instruction_in(ifid_instruction),
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
    // CSR outputs
    .csr_addr_out(idex_csr_addr),
    .csr_we_out(idex_csr_we),
    .csr_src_out(idex_csr_src),
    .csr_wdata_out(idex_csr_wdata),
    // Exception outputs
    .is_ecall_out(idex_is_ecall),
    .is_ebreak_out(idex_is_ebreak),
    .is_mret_out(idex_is_mret),
    .illegal_inst_out(idex_illegal_inst),
    .instruction_out(idex_instruction)
  );

  //==========================================================================
  // EX STAGE: Execute
  //==========================================================================

  assign ex_pc_plus_4 = idex_pc + {{(XLEN-3){1'b0}}, 3'b100};  // PC + 4

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
  // AUIPC uses PC, LUI uses 0, others use rs1
  assign ex_alu_operand_a = (idex_opcode == 7'b0010111) ? idex_pc :          // AUIPC
                            (idex_opcode == 7'b0110111) ? {XLEN{1'b0}} :   // LUI
                            idex_rs1_data;                                    // Others

  // Disable forwarding for LUI and AUIPC (they don't use rs1, decoder extracts garbage)
  wire disable_forward_a = (idex_opcode == 7'b0110111) || (idex_opcode == 7'b0010111);  // LUI or AUIPC

  assign ex_alu_operand_a_forwarded = disable_forward_a ? ex_alu_operand_a :            // No forward for LUI/AUIPC
                                      (forward_a == 2'b10) ? exmem_alu_result :         // EX hazard
                                      (forward_a == 2'b01) ? wb_data :                  // MEM hazard
                                      ex_alu_operand_a;                                  // No hazard

  // ALU Operand B selection (with forwarding)
  wire [XLEN-1:0] ex_rs2_data_forwarded;
  assign ex_rs2_data_forwarded = (forward_b == 2'b10) ? exmem_alu_result :         // EX hazard
                                  (forward_b == 2'b01) ? wb_data :                  // MEM hazard
                                  idex_rs2_data;                                     // No hazard

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

  // M Extension Unit
  mul_div_unit #(
    .XLEN(XLEN)
  ) m_unit (
    .clk(clk),
    .reset_n(reset_n),
    .start(m_unit_start),
    .operation(idex_mul_div_op),
    .is_word_op(idex_is_word_op),
    .operand_a(ex_alu_operand_a_forwarded),
    .operand_b(ex_rs2_data_forwarded),
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
  wire            a_unit_start;
  assign a_unit_start = idex_is_atomic && idex_valid && !ex_atomic_busy && !ex_atomic_done;

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
    .invalidate(1'b0),              // TODO: invalidation on intervening writes
    .inv_addr({XLEN{1'b0}}),
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
  assign ex_csr_uses_rs1 = (idex_wb_sel == 2'b11) && !idex_csr_src;  // CSR instruction using rs1

  wire [XLEN-1:0] ex_csr_wdata_forwarded;
  assign ex_csr_wdata_forwarded = (ex_csr_uses_rs1 && forward_a == 2'b10) ? exmem_alu_result :  // EX-to-EX forward
                                  (ex_csr_uses_rs1 && forward_a == 2'b01) ? wb_data :           // MEM-to-EX forward
                                  idex_csr_wdata;                                                 // No hazard or imm form

  csr_file #(
    .XLEN(XLEN)
  ) csr_file_inst (
    .clk(clk),
    .reset_n(reset_n),
    .csr_addr(idex_csr_addr),
    .csr_wdata(ex_csr_wdata_forwarded),  // Use forwarded value
    .csr_op(idex_funct3),           // funct3 encodes CSR operation
    .csr_we(idex_csr_we && idex_valid),
    .csr_rdata(ex_csr_rdata),
    .trap_entry(exception),
    .trap_pc(exception_pc),
    .trap_cause(exception_code),
    .trap_val(exception_val),
    .trap_vector(trap_vector),
    .mret(idex_is_mret && idex_valid),
    .mepc_out(mepc),
    .mstatus_mie(mstatus_mie),
    .illegal_csr(ex_illegal_csr)
  );

  //==========================================================================
  // Exception Unit (monitors all stages)
  //==========================================================================
  // Note: Exception unit needs valid flags to be properly connected
  // For now, using conservative approach: exceptions in EX stage for ECALL/EBREAK/illegal
  exception_unit #(
    .XLEN(XLEN)
  ) exception_unit_inst (
    // IF stage - instruction fetch (check misaligned PC)
    .if_pc(pc_current),
    .if_valid(!flush_ifid),         // IF invalid when flushing
    // ID stage - decode stage exceptions (in EX pipeline stage)
    // Note: Only consider illegal_csr if it's actually a CSR instruction
    .id_illegal_inst((idex_illegal_inst | (ex_illegal_csr && idex_csr_we)) && idex_valid),
    .id_ecall(idex_is_ecall && idex_valid),
    .id_ebreak(idex_is_ebreak && idex_valid),
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
    // Outputs
    .exception(exception),
    .exception_code(exception_code),
    .exception_pc(exception_pc),
    .exception_val(exception_val)
  );

  // EX/MEM Pipeline Register
  exmem_register #(
    .XLEN(XLEN)
  ) exmem_reg (
    .clk(clk),
    .reset_n(reset_n),
    .hold(hold_exmem),
    .alu_result_in(ex_alu_result),
    .mem_write_data_in(ex_rs2_data_forwarded),
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
    // CSR inputs
    .csr_addr_in(idex_csr_addr),
    .csr_we_in(idex_csr_we),
    .csr_rdata_in(ex_csr_rdata),
    // Exception inputs
    .is_mret_in(idex_is_mret),
    .instruction_in(idex_instruction),
    .pc_in(idex_pc),
    // Outputs
    .alu_result_out(exmem_alu_result),
    .mem_write_data_out(exmem_mem_write_data),
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
    // CSR outputs
    .csr_addr_out(exmem_csr_addr),
    .csr_we_out(exmem_csr_we),
    .csr_rdata_out(exmem_csr_rdata),
    // Exception outputs
    .is_mret_out(exmem_is_mret),
    .instruction_out(exmem_instruction),
    .pc_out(exmem_pc)
  );

  //==========================================================================
  // MEM STAGE: Memory Access
  //==========================================================================

  // Exception prevention: Don't write memory or registers if exception is active
  wire mem_write_gated = exmem_mem_write && !exception;
  wire reg_write_gated = exmem_reg_write && !exception;

  // Memory Arbitration: Atomic unit gets priority when it's active
  // When atomic operation is executing, atomic unit controls memory
  // Otherwise, normal load/store path from MEM stage controls memory
  wire [XLEN-1:0] dmem_addr;
  wire [XLEN-1:0] dmem_write_data;
  wire            dmem_mem_read;
  wire            dmem_mem_write;
  wire [2:0]      dmem_funct3;

  // Use atomic unit's memory interface when atomic unit is busy
  assign dmem_addr       = ex_atomic_busy ? ex_atomic_mem_addr : exmem_alu_result;
  assign dmem_write_data = ex_atomic_busy ? ex_atomic_mem_wdata : exmem_mem_write_data;
  assign dmem_mem_read   = ex_atomic_busy ? ex_atomic_mem_req && !ex_atomic_mem_we : exmem_mem_read;
  assign dmem_mem_write  = ex_atomic_busy ? ex_atomic_mem_req && ex_atomic_mem_we : mem_write_gated;
  assign dmem_funct3     = ex_atomic_busy ? ex_atomic_mem_size : exmem_funct3;

  // Atomic unit sees memory as always ready (synchronous memory, 1-cycle latency)
  assign ex_atomic_mem_ready = 1'b1;

  // Data Memory
  data_memory #(
    .XLEN(XLEN),
    .MEM_SIZE(DMEM_SIZE),
    .MEM_FILE(MEM_FILE)  // Load same file as instruction memory (for compliance tests)
  ) dmem (
    .clk(clk),
    .addr(dmem_addr),
    .write_data(dmem_write_data),
    .mem_read(dmem_mem_read),
    .mem_write(dmem_mem_write),
    .funct3(dmem_funct3),
    .read_data(mem_read_data)
  );

  // MEM/WB Pipeline Register
  memwb_register #(
    .XLEN(XLEN)
  ) memwb_reg (
    .clk(clk),
    .reset_n(reset_n),
    .alu_result_in(exmem_alu_result),
    .mem_read_data_in(mem_read_data),
    .rd_addr_in(exmem_rd_addr),
    .pc_plus_4_in(exmem_pc_plus_4),
    .reg_write_in(reg_write_gated),     // Gated to prevent write on exception
    .wb_sel_in(exmem_wb_sel),
    .valid_in(exmem_valid && !exception),  // Mark invalid on exception
    .mul_div_result_in(exmem_mul_div_result),
    .atomic_result_in(exmem_atomic_result),
    // CSR input
    .csr_rdata_in(exmem_csr_rdata),
    // Outputs
    .alu_result_out(memwb_alu_result),
    .mem_read_data_out(memwb_mem_read_data),
    .rd_addr_out(memwb_rd_addr),
    .pc_plus_4_out(memwb_pc_plus_4),
    .reg_write_out(memwb_reg_write),
    .wb_sel_out(memwb_wb_sel),
    .valid_out(memwb_valid),
    .mul_div_result_out(memwb_mul_div_result),
    .atomic_result_out(memwb_atomic_result),
    // CSR output
    .csr_rdata_out(memwb_csr_rdata)
  );

  //==========================================================================
  // WB STAGE: Write Back
  //==========================================================================

  // Write-Back Data Selection
  assign wb_data = (memwb_wb_sel == 3'b000) ? memwb_alu_result :      // ALU result
                   (memwb_wb_sel == 3'b001) ? memwb_mem_read_data :   // Memory data
                   (memwb_wb_sel == 3'b010) ? memwb_pc_plus_4 :       // PC + 4 (JAL/JALR)
                   (memwb_wb_sel == 3'b011) ? memwb_csr_rdata :       // CSR data
                   (memwb_wb_sel == 3'b100) ? memwb_mul_div_result :  // M extension result
                   (memwb_wb_sel == 3'b101) ? memwb_atomic_result :   // A extension result
                   {XLEN{1'b0}};

endmodule
