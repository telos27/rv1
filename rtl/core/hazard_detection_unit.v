// Hazard Detection Unit
// Detects load-use hazards and generates stall/bubble control signals
// A load-use hazard occurs when a load instruction in EX stage
// produces data needed by the instruction in ID stage
//
// ⚠️ KNOWN ISSUE: Atomic forwarding stall is overly conservative (~6% overhead)
// See line ~126 for detailed explanation and proper fix (requires adding clk/reset_n)

module hazard_detection_unit (
  // Inputs from ID/EX register (instruction in EX stage)
  input  wire        idex_mem_read,    // Load instruction in EX stage
  input  wire [4:0]  idex_rd,          // Destination register of load (integer)
  input  wire [4:0]  idex_fp_rd,       // Destination register of FP load
  input  wire        idex_fp_mem_op,   // FP memory operation (FP load/store)

  // Inputs from IF/ID register (instruction in ID stage)
  input  wire [4:0]  ifid_rs1,         // Source register 1 (integer)
  input  wire [4:0]  ifid_rs2,         // Source register 2 (integer)
  input  wire [4:0]  ifid_fp_rs1,      // Source register 1 (FP)
  input  wire [4:0]  ifid_fp_rs2,      // Source register 2 (FP)
  input  wire [4:0]  ifid_fp_rs3,      // Source register 3 (FP, for FMA)

  // M extension signals
  input  wire        mul_div_busy,     // M unit is busy
  input  wire        idex_is_mul_div,  // M instruction in EX stage

  // A extension signals
  input  wire        atomic_busy,      // A unit is busy
  input  wire        atomic_done,      // A unit operation complete
  input  wire        idex_is_atomic,   // A instruction in EX stage
  input  wire        exmem_is_atomic,  // A instruction in MEM stage
  input  wire [4:0]  exmem_rd,         // MEM stage destination register

  // F/D extension signals
  input  wire        fpu_busy,         // FPU is busy (multi-cycle operation in progress)
  input  wire        fpu_done,         // FPU operation complete (1 cycle pulse)
  input  wire        idex_fp_alu_en,   // FP instruction in EX stage

  // CSR signals (for FFLAGS/FCSR dependency checking)
  input  wire [11:0] id_csr_addr,      // CSR address in ID stage
  input  wire        id_csr_we,        // CSR write enable in ID stage

  // MMU signals
  input  wire        mmu_busy,         // MMU is busy (page table walk in progress)

  // Hazard control outputs
  output wire        stall_pc,         // Stall program counter
  output wire        stall_ifid,       // Stall IF/ID register
  output wire        bubble_idex       // Insert bubble (NOP) into ID/EX
);

  // Load-use hazard detection logic
  // Hazard exists if:
  //   1. Instruction in EX stage is a load (mem_read = 1)
  //   2. Load's destination register matches either source register in ID stage
  //   3. Destination register is not x0 (zero register)
  //
  // When hazard detected:
  //   - Stall PC (don't fetch next instruction)
  //   - Stall IF/ID (keep current instruction in ID stage)
  //   - Insert bubble into ID/EX (convert ID stage to NOP)
  //
  // This creates a 1-cycle stall, allowing the load to complete
  // and then forwarding can provide the data in the next cycle

  wire rs1_hazard;
  wire rs2_hazard;
  wire load_use_hazard;

  // Check if rs1 has a hazard
  assign rs1_hazard = (idex_rd == ifid_rs1) && (idex_rd != 5'h0);

  // Check if rs2 has a hazard
  assign rs2_hazard = (idex_rd == ifid_rs2) && (idex_rd != 5'h0);

  // Load-use hazard exists if there's a load and either source has a hazard
  assign load_use_hazard = idex_mem_read && (rs1_hazard || rs2_hazard);

  // FP load-use hazard detection
  // Similar to integer load-use, but checks FP registers
  // Hazard exists if:
  //   1. Instruction in EX stage is an FP load (mem_read && fp_mem_op)
  //   2. FP load's destination register matches any FP source register in ID stage
  // Note: FP registers don't have a hardwired-zero register like x0
  wire fp_rs1_hazard;
  wire fp_rs2_hazard;
  wire fp_rs3_hazard;
  wire fp_load_use_hazard;

  assign fp_rs1_hazard = (idex_fp_rd == ifid_fp_rs1);
  assign fp_rs2_hazard = (idex_fp_rd == ifid_fp_rs2);
  assign fp_rs3_hazard = (idex_fp_rd == ifid_fp_rs3);

  // FP load-use hazard: FP load in EX writing to a register needed by FP instruction in ID
  assign fp_load_use_hazard = idex_mem_read && idex_fp_mem_op &&
                               (fp_rs1_hazard || fp_rs2_hazard || fp_rs3_hazard);

  // M extension hazard: stall IF/ID stages when M unit is busy OR when M instruction just entered EX
  // The M instruction is held in EX stage by hold signals on IDEX and EXMEM registers.
  // We also need to stall IF/ID to prevent new instructions from entering the pipeline.
  // We check idex_is_mul_div to catch the M instruction on the first cycle it enters EX,
  // before the busy signal has a chance to go high.
  wire m_extension_stall;
  assign m_extension_stall = mul_div_busy || idex_is_mul_div;

  // A extension hazard: stall IF/ID stages when A unit is busy OR when A instruction just entered EX
  // Similar to M extension, atomic operations are multi-cycle and hold the pipeline.
  // BUT: Do not stall when operation is done - this allows the atomic instruction to leave ID/EX
  // and prevents infinite stall loop on back-to-back atomic operations.
  wire a_extension_stall;
  assign a_extension_stall = (atomic_busy || idex_is_atomic) && !atomic_done;

  // A extension forwarding hazard: stall when ID stage has dependency on in-progress atomic
  // This prevents forwarding atomic results before they're ready.
  // Similar to load-use hazard, check register dependencies directly
  // Stall if:
  //   1. Atomic in EX AND (rd matches rs1 or rs2) AND not done, OR
  //   2. Atomic in MEM AND (rd matches rs1 or rs2) but exmem_is_atomic not set yet
  wire atomic_rs1_hazard_ex;
  wire atomic_rs2_hazard_ex;
  wire atomic_rs1_hazard_mem;
  wire atomic_rs2_hazard_mem;
  wire atomic_forward_hazard;

  // Check EX stage dependencies
  assign atomic_rs1_hazard_ex = (idex_rd == ifid_rs1) && (idex_rd != 5'h0);
  assign atomic_rs2_hazard_ex = (idex_rd == ifid_rs2) && (idex_rd != 5'h0);

  // Check MEM stage dependencies (for transition cycle when atomic just moved from EX to MEM)
  assign atomic_rs1_hazard_mem = (exmem_rd == ifid_rs1) && (exmem_rd != 5'h0);
  assign atomic_rs2_hazard_mem = (exmem_rd == ifid_rs2) && (exmem_rd != 5'h0);

  // ============================================================================
  // FIXME: PERFORMANCE ISSUE - Overly Conservative Stalling (~6% overhead)
  // ============================================================================
  // Current implementation: Stall entire atomic execution when dependency exists
  // Problem: This stalls even when atomic hasn't completed yet AND during completion cycle
  // Overhead: ~1,049 extra cycles (18,616 vs 17,567 expected) = 6% performance loss
  //
  // ROOT CAUSE: Transition cycle bug - when atomic_done=1, dependent instructions
  // slip through before result propagates to EXMEM where MEM→ID forwarding works.
  //
  // BETTER SOLUTION (TODO):
  //   1. Keep original logic: stall only when (!atomic_done && hazard)
  //   2. Add ONE extra stall cycle when (atomic_done && hazard) using state register
  //   3. This covers transition cycle without stalling entire atomic execution
  //
  // Example fix:
  //   reg atomic_done_prev;
  //   always @(posedge clk) atomic_done_prev <= atomic_done && idex_is_atomic;
  //   assign atomic_forward_hazard =
  //     (idex_is_atomic && !atomic_done && hazard) ||  // During execution
  //     (atomic_done_prev && hazard);                   // Transition cycle only
  //
  // Why not implemented: Requires clk/reset_n ports, adds sequential logic complexity
  // Trade-off: Accepted 6% overhead for simpler combinational-only design
  // ============================================================================

  // Stall if atomic in EX with dependency (including the completion cycle)
  // This ensures dependent instructions wait until result is in EXMEM where MEM→ID forwarding works
  assign atomic_forward_hazard =
    (idex_is_atomic && (atomic_rs1_hazard_ex || atomic_rs2_hazard_ex));

  // FP extension hazard: stall IF/ID stages when FPU is busy with multi-cycle operations
  // FP multi-cycle operations (FDIV, FSQRT, FMA, etc.) hold the pipeline.
  // Similar to A extension, stall while FPU is busy but NOT when operation completes.
  // This allows single-cycle FP operations (FSGNJ, FMV.X.W, etc.) to complete without stalling.
  wire fp_extension_stall;
  assign fp_extension_stall = (fpu_busy || idex_fp_alu_en) && !fpu_done;

  // MMU hazard: stall IF/ID stages when MMU is busy with page table walk
  // Page table walks are multi-cycle operations that must complete before proceeding.
  // This prevents IF/ID from advancing while EX/MEM stages are held waiting for MMU.
  wire mmu_stall;
  assign mmu_stall = mmu_busy;

  // CSR-FPU dependency hazard: stall when CSR instruction accesses FFLAGS/FCSR while FPU is busy
  // Bug Fix #6: FSFLAGS/FCSR instructions must wait for all pending FP operations to complete.
  // Problem: If fsflags executes while FP operation is in pipeline, it reads stale flags,
  //          then the FP operation completes and accumulates its flags, overwriting the CSR write.
  // Solution: Stall CSR reads/writes to FFLAGS/FRM/FCSR when FPU has pending operations.
  //
  // CSR addresses:
  //   0x001 = FFLAGS (exception flags)
  //   0x002 = FRM (rounding mode)
  //   0x003 = FCSR (full FP CSR = FRM[7:5] | FFLAGS[4:0])
  //
  // Note: We stall for ANY access (read or write) to these CSRs, and we check both
  //       fpu_busy (operation in progress) and idex_fp_alu_en (FP op just started).
  //       We don't stall when fpu_done=1 because that means the operation has completed
  //       and flags are ready.
  localparam CSR_FFLAGS = 12'h001;
  localparam CSR_FRM    = 12'h002;
  localparam CSR_FCSR   = 12'h003;

  wire csr_accesses_fp_flags;
  wire csr_fpu_dependency_stall;

  // Check if ID stage CSR instruction accesses FP-related CSRs
  // Note: FRM technically doesn't have a dependency on FPU operations, but for simplicity
  //       and to avoid complexity, we conservatively stall for all three CSRs
  assign csr_accesses_fp_flags = (id_csr_addr == CSR_FFLAGS) ||
                                   (id_csr_addr == CSR_FRM) ||
                                   (id_csr_addr == CSR_FCSR);

  // Stall if CSR instruction in ID accesses FP flags AND FPU is busy or just started
  // NOTE: We DO stall even when fpu_done=1 because flags are being written in that cycle
  //       and won't be visible until the next cycle. Only after fpu_done goes low (next cycle)
  //       are the flags safe to read.
  assign csr_fpu_dependency_stall = csr_accesses_fp_flags &&
                                     (fpu_busy || idex_fp_alu_en);

  // Generate control signals
  // Stall if load-use hazard (integer or FP), M extension dependency, A extension dependency,
  // A extension forwarding hazard, FP extension dependency, CSR-FPU dependency, or MMU dependency
  assign stall_pc    = load_use_hazard || fp_load_use_hazard || m_extension_stall || a_extension_stall || atomic_forward_hazard || fp_extension_stall || csr_fpu_dependency_stall || mmu_stall;
  assign stall_ifid  = load_use_hazard || fp_load_use_hazard || m_extension_stall || a_extension_stall || atomic_forward_hazard || fp_extension_stall || csr_fpu_dependency_stall || mmu_stall;
  // Note: Bubble for load-use hazards, atomic forwarding hazards, AND CSR-FPU dependency stalls
  // (M/A/FP/MMU stalls use hold signals on IDEX and EXMEM to keep instruction in place)
  // CSR-FPU stall needs bubble because it's a RAW hazard between FP op in EX and CSR in ID
  assign bubble_idex = load_use_hazard || fp_load_use_hazard || atomic_forward_hazard || csr_fpu_dependency_stall;

endmodule
