// EX/MEM Pipeline Register
// Latches outputs from Execute stage for use in Memory stage
// No stall or flush needed (hazards handled in earlier stages)
// Updated: 2025-10-10 - Parameterized for XLEN (32/64-bit support)

`include "config/rv_config.vh"

module exmem_register #(
  parameter XLEN = `XLEN,  // Data/address width: 32 or 64 bits
  parameter FLEN = `FLEN   // FP register width: 32 or 64 bits
) (
  input  wire             clk,
  input  wire             reset_n,
  input  wire             hold,           // Hold register (don't update)
  input  wire             flush,          // Clear to NOP (for exceptions/traps)

  // Inputs from EX stage
  input  wire [XLEN-1:0]  alu_result_in,
  input  wire [XLEN-1:0]  mem_write_data_in,      // Integer store data (forwarded rs2)
  input  wire [FLEN-1:0]  fp_mem_write_data_in,   // FP store data (for FSD)
  input  wire [4:0]       rd_addr_in,
  input  wire [XLEN-1:0]  pc_plus_4_in,           // For JAL/JALR write-back
  input  wire [2:0]       funct3_in,              // For memory access size/signedness

  // Control signals from EX stage
  input  wire        mem_read_in,
  input  wire        mem_write_in,
  input  wire        reg_write_in,
  input  wire [2:0]  wb_sel_in,
  input  wire        valid_in,

  // M extension result from EX stage
  input  wire [XLEN-1:0] mul_div_result_in,

  // A extension result from EX stage
  input  wire [XLEN-1:0] atomic_result_in,
  input  wire            is_atomic_in,       // Atomic instruction flag

  // F/D extension signals from EX stage
  input  wire [FLEN-1:0]  fp_result_in,          // FP result
  input  wire [XLEN-1:0]  int_result_fp_in,      // Integer result (FP compare/classify/FMV.X.W)
  input  wire [4:0]       fp_rd_addr_in,         // FP destination register
  input  wire             fp_reg_write_in,       // FP register write enable
  input  wire             int_reg_write_fp_in,   // Integer register write (from FP op)
  input  wire             fp_mem_op_in,          // FP load/store operation flag
  input  wire             fp_flag_nv_in,         // FP exception flags
  input  wire             fp_flag_dz_in,
  input  wire             fp_flag_of_in,
  input  wire             fp_flag_uf_in,
  input  wire             fp_flag_nx_in,
  input  wire             fp_fmt_in,             // FP format: 0=single, 1=double

  // CSR signals from EX stage
  input  wire [11:0]      csr_addr_in,
  input  wire             csr_we_in,
  input  wire [XLEN-1:0]  csr_rdata_in,    // CSR read data from CSR file

  // Exception signals from EX stage
  input  wire        is_mret_in,
  input  wire        is_sret_in,
  input  wire        is_sfence_vma_in,
  input  wire [4:0]  rs1_addr_in,
  input  wire [4:0]  rs2_addr_in,
  input  wire [XLEN-1:0] rs1_data_in,
  input  wire [31:0] instruction_in,
  input  wire [XLEN-1:0] pc_in,           // For exception handling

  // MMU translation results from EX stage
  input  wire [XLEN-1:0] mmu_paddr_in,         // Translated physical address
  input  wire            mmu_ready_in,         // Translation complete
  input  wire            mmu_page_fault_in,    // Page fault detected
  input  wire [XLEN-1:0] mmu_fault_vaddr_in,   // Faulting virtual address

  // Outputs to MEM stage
  output reg  [XLEN-1:0]  alu_result_out,
  output reg  [XLEN-1:0]  mem_write_data_out,      // Integer store data
  output reg  [FLEN-1:0]  fp_mem_write_data_out,   // FP store data
  output reg  [4:0]       rd_addr_out,
  output reg  [XLEN-1:0]  pc_plus_4_out,
  output reg  [2:0]       funct3_out,

  // Control signals to MEM stage
  output reg         mem_read_out,
  output reg         mem_write_out,
  output reg         reg_write_out,
  output reg  [2:0]  wb_sel_out,
  output reg         valid_out,

  // M extension result to MEM stage
  output reg  [XLEN-1:0] mul_div_result_out,

  // A extension result to MEM stage
  output reg  [XLEN-1:0] atomic_result_out,
  output reg             is_atomic_out,       // Atomic instruction flag

  // F/D extension signals to MEM stage
  output reg  [FLEN-1:0]  fp_result_out,
  output reg  [XLEN-1:0]  int_result_fp_out,
  output reg  [4:0]       fp_rd_addr_out,
  output reg              fp_reg_write_out,
  output reg              int_reg_write_fp_out,
  output reg              fp_mem_op_out,         // FP load/store operation flag
  output reg              fp_flag_nv_out,
  output reg              fp_flag_dz_out,
  output reg              fp_flag_of_out,
  output reg              fp_flag_uf_out,
  output reg              fp_flag_nx_out,
  output reg              fp_fmt_out,            // FP format: 0=single, 1=double

  // CSR signals to MEM stage
  output reg  [11:0]      csr_addr_out,
  output reg              csr_we_out,
  output reg  [XLEN-1:0]  csr_rdata_out,

  // Exception signals to MEM stage
  output reg         is_mret_out,
  output reg         is_sret_out,
  output reg         is_sfence_vma_out,
  output reg  [4:0]  rs1_addr_out,
  output reg  [4:0]  rs2_addr_out,
  output reg  [XLEN-1:0] rs1_data_out,
  output reg  [31:0] instruction_out,
  output reg  [XLEN-1:0] pc_out,

  // MMU translation results to MEM stage
  output reg  [XLEN-1:0] mmu_paddr_out,        // Translated physical address
  output reg             mmu_ready_out,        // Translation complete
  output reg             mmu_page_fault_out,   // Page fault detected
  output reg  [XLEN-1:0] mmu_fault_vaddr_out   // Faulting virtual address
);

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset: clear all outputs
      alu_result_out        <= {XLEN{1'b0}};
      mem_write_data_out    <= {XLEN{1'b0}};
      fp_mem_write_data_out <= {FLEN{1'b0}};
      rd_addr_out           <= 5'h0;
      pc_plus_4_out         <= {XLEN{1'b0}};
      funct3_out            <= 3'h0;

      mem_read_out       <= 1'b0;
      mem_write_out      <= 1'b0;
      reg_write_out      <= 1'b0;
      wb_sel_out         <= 3'b0;
      valid_out          <= 1'b0;

      mul_div_result_out <= {XLEN{1'b0}};

      atomic_result_out  <= {XLEN{1'b0}};
      is_atomic_out      <= 1'b0;

      fp_result_out      <= {FLEN{1'b0}};
      int_result_fp_out  <= {XLEN{1'b0}};
      fp_rd_addr_out     <= 5'h0;
      fp_reg_write_out   <= 1'b0;
      int_reg_write_fp_out <= 1'b0;
      fp_mem_op_out      <= 1'b0;
      fp_flag_nv_out     <= 1'b0;
      fp_flag_dz_out     <= 1'b0;
      fp_flag_of_out     <= 1'b0;
      fp_flag_uf_out     <= 1'b0;
      fp_flag_nx_out     <= 1'b0;
      fp_fmt_out         <= 1'b0;

      csr_addr_out       <= 12'h0;
      csr_we_out         <= 1'b0;
      csr_rdata_out      <= {XLEN{1'b0}};

      is_mret_out        <= 1'b0;
      is_sret_out        <= 1'b0;
      is_sfence_vma_out  <= 1'b0;
      rs1_addr_out       <= 5'h0;
      rs2_addr_out       <= 5'h0;
      rs1_data_out       <= {XLEN{1'b0}};
      instruction_out    <= 32'h0;
      pc_out             <= {XLEN{1'b0}};

      mmu_paddr_out      <= {XLEN{1'b0}};
      mmu_ready_out      <= 1'b0;
      mmu_page_fault_out <= 1'b0;
      mmu_fault_vaddr_out <= {XLEN{1'b0}};
    end else if (flush && !hold) begin
      // Flush: insert NOP bubble (clear control signals, keep data)
      // Critical fix: Clear page fault signals to prevent exception re-triggering!
      // Note: hold takes priority over flush
      alu_result_out        <= alu_result_in;  // Keep for debugging
      mem_write_data_out    <= mem_write_data_in;
      fp_mem_write_data_out <= fp_mem_write_data_in;
      rd_addr_out           <= 5'h0;           // Clear destination
      pc_plus_4_out         <= pc_plus_4_in;
      funct3_out            <= 3'h0;

      mem_read_out       <= 1'b0;              // Clear control signals
      mem_write_out      <= 1'b0;
      reg_write_out      <= 1'b0;
      wb_sel_out         <= 3'b0;
      valid_out          <= 1'b0;              // Mark as invalid

      mul_div_result_out <= {XLEN{1'b0}};

      atomic_result_out  <= {XLEN{1'b0}};
      is_atomic_out      <= 1'b0;

      fp_result_out      <= {FLEN{1'b0}};
      int_result_fp_out  <= {XLEN{1'b0}};
      fp_rd_addr_out     <= 5'h0;
      fp_reg_write_out   <= 1'b0;
      int_reg_write_fp_out <= 1'b0;
      fp_mem_op_out      <= 1'b0;
      fp_flag_nv_out     <= 1'b0;
      fp_flag_dz_out     <= 1'b0;
      fp_flag_of_out     <= 1'b0;
      fp_flag_uf_out     <= 1'b0;
      fp_flag_nx_out     <= 1'b0;
      fp_fmt_out         <= 1'b0;

      csr_addr_out       <= 12'h0;
      csr_we_out         <= 1'b0;
      csr_rdata_out      <= {XLEN{1'b0}};

      is_mret_out        <= 1'b0;
      is_sret_out        <= 1'b0;
      is_sfence_vma_out  <= 1'b0;
      rs1_addr_out       <= 5'h0;
      rs2_addr_out       <= 5'h0;
      rs1_data_out       <= {XLEN{1'b0}};
      instruction_out    <= 32'h0;
      pc_out             <= pc_in;             // Keep PC for debugging

      // CRITICAL: Clear page fault signals to prevent exception loop!
      mmu_paddr_out      <= {XLEN{1'b0}};
      mmu_ready_out      <= 1'b0;
      mmu_page_fault_out <= 1'b0;              // This is the key fix!
      mmu_fault_vaddr_out <= {XLEN{1'b0}};
    end else if (!hold) begin
      // Only update if not held (M extension may need to hold instruction in EX)
      alu_result_out        <= alu_result_in;
      mem_write_data_out    <= mem_write_data_in;
      fp_mem_write_data_out <= fp_mem_write_data_in;
      rd_addr_out           <= rd_addr_in;
      pc_plus_4_out         <= pc_plus_4_in;
      funct3_out            <= funct3_in;

      mem_read_out       <= mem_read_in;
      mem_write_out      <= mem_write_in;
      reg_write_out      <= reg_write_in;
      wb_sel_out         <= wb_sel_in;
      valid_out          <= valid_in;

      mul_div_result_out <= mul_div_result_in;

      atomic_result_out  <= atomic_result_in;
      is_atomic_out      <= is_atomic_in;

      fp_result_out      <= fp_result_in;
      int_result_fp_out  <= int_result_fp_in;
      fp_rd_addr_out     <= fp_rd_addr_in;
      fp_reg_write_out   <= fp_reg_write_in;
      int_reg_write_fp_out <= int_reg_write_fp_in;
      fp_mem_op_out      <= fp_mem_op_in;
      fp_flag_nv_out     <= fp_flag_nv_in;
      fp_flag_dz_out     <= fp_flag_dz_in;
      fp_flag_of_out     <= fp_flag_of_in;
      fp_flag_uf_out     <= fp_flag_uf_in;
      fp_flag_nx_out     <= fp_flag_nx_in;
      fp_fmt_out         <= fp_fmt_in;

      csr_addr_out       <= csr_addr_in;
      csr_we_out         <= csr_we_in;
      csr_rdata_out      <= csr_rdata_in;

      is_mret_out        <= is_mret_in;
      is_sret_out        <= is_sret_in;
      is_sfence_vma_out  <= is_sfence_vma_in;
      rs1_addr_out       <= rs1_addr_in;
      rs2_addr_out       <= rs2_addr_in;
      rs1_data_out       <= rs1_data_in;
      instruction_out    <= instruction_in;
      pc_out             <= pc_in;

      mmu_paddr_out      <= mmu_paddr_in;
      mmu_ready_out      <= mmu_ready_in;
      mmu_page_fault_out <= mmu_page_fault_in;
      mmu_fault_vaddr_out <= mmu_fault_vaddr_in;
    end
    // If hold is asserted, keep previous values (register holds in place)
  end

endmodule
