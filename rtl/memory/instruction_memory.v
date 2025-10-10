// instruction_memory.v - Instruction memory for RV32I
// Read-only memory for program storage
// Author: RV1 Project
// Date: 2025-10-09

module instruction_memory #(
  parameter MEM_SIZE = 4096,      // Memory size in bytes (4KB default)
  parameter MEM_FILE = ""         // Hex file to initialize memory
) (
  input  wire [31:0] addr,        // Byte address
  output wire [31:0] instruction  // Instruction output
);

  // Calculate number of words
  localparam NUM_WORDS = MEM_SIZE / 4;

  // Memory array (word-addressed)
  reg [31:0] mem [0:NUM_WORDS-1];

  // Initialize memory
  initial begin
    integer i;
    // Initialize to NOP (ADDI x0, x0, 0)
    for (i = 0; i < NUM_WORDS; i = i + 1) begin
      mem[i] = 32'h00000013;  // NOP
    end

    // Load from file if specified
    if (MEM_FILE != "") begin
      $readmemh(MEM_FILE, mem);
    end
  end

  // Word-aligned read (ignore lower 2 bits)
  // addr[31:2] gives the word index
  assign instruction = mem[addr[31:2]];

endmodule
