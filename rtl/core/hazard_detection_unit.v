// Hazard Detection Unit
// Detects load-use hazards and generates stall/bubble control signals
// A load-use hazard occurs when a load instruction in EX stage
// produces data needed by the instruction in ID stage

module hazard_detection_unit (
  // Inputs from ID/EX register (instruction in EX stage)
  input  wire        idex_mem_read,    // Load instruction in EX stage
  input  wire [4:0]  idex_rd,          // Destination register of load

  // Inputs from IF/ID register (instruction in ID stage)
  input  wire [4:0]  ifid_rs1,         // Source register 1
  input  wire [4:0]  ifid_rs2,         // Source register 2

  // M extension signals
  input  wire        mul_div_busy,     // M unit is busy
  input  wire        idex_is_mul_div,  // M instruction in EX stage

  // A extension signals
  input  wire        atomic_busy,      // A unit is busy
  input  wire        atomic_done,      // A unit operation complete
  input  wire        idex_is_atomic,   // A instruction in EX stage

  // F/D extension signals
  input  wire        fpu_busy,         // FPU is busy (multi-cycle operation in progress)
  input  wire        idex_fp_alu_en,   // FP instruction in EX stage

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

  // FP extension hazard: stall IF/ID stages when FPU is busy OR when FP instruction just entered EX
  // FP multi-cycle operations (FDIV, FSQRT, FMA, etc.) hold the pipeline.
  // Similar to M extension, the FP instruction is held in EX stage using hold signals.
  wire fp_extension_stall;
  assign fp_extension_stall = fpu_busy || idex_fp_alu_en;

  // Generate control signals
  // Stall if load-use hazard, M extension dependency, A extension dependency, or FP extension dependency
  assign stall_pc    = load_use_hazard || m_extension_stall || a_extension_stall || fp_extension_stall;
  assign stall_ifid  = load_use_hazard || m_extension_stall || a_extension_stall || fp_extension_stall;
  // Note: Only bubble for load-use hazard, NOT for M/A/FP stall
  // (M/A/FP stall uses hold signals on IDEX and EXMEM to keep instruction in place)
  assign bubble_idex = load_use_hazard;

endmodule
