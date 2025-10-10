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

  // Memory array (byte-addressed for easier hex file loading)
  reg [7:0] mem [0:MEM_SIZE-1];

  // Initialize memory
  initial begin
    integer i;
    // Initialize to NOP (ADDI x0, x0, 0) = 0x00000013 in little-endian bytes
    for (i = 0; i < MEM_SIZE; i = i + 4) begin
      mem[i]   = 8'h13;  // NOP byte 0
      mem[i+1] = 8'h00;  // NOP byte 1
      mem[i+2] = 8'h00;  // NOP byte 2
      mem[i+3] = 8'h00;  // NOP byte 3
    end

    // Load from file if specified
    if (MEM_FILE != "") begin
      $readmemh(MEM_FILE, mem);
    end
  end

  // Word-aligned read (assemble 4 bytes into 32-bit instruction, little-endian)
  // addr[31:2] gives the word index, we read 4 bytes starting at that address
  wire [31:0] word_addr = {addr[31:2], 2'b00};  // Align to word boundary
  assign instruction = {mem[word_addr+3], mem[word_addr+2], mem[word_addr+1], mem[word_addr]};

endmodule
