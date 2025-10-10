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

  // Generate control signals
  assign stall_pc    = load_use_hazard;
  assign stall_ifid  = load_use_hazard;
  assign bubble_idex = load_use_hazard;

endmodule
