// instruction_memory.v - Instruction memory for RISC-V
// Read-only memory for program storage
// Author: RV1 Project
// Date: 2025-10-09
// Updated: 2025-10-10 - Parameterized for XLEN (32/64-bit address support)

`include "config/rv_config.vh"

module instruction_memory #(
  parameter XLEN     = `XLEN,     // Address width: 32 or 64 bits
  parameter MEM_SIZE = 65536,     // Memory size in bytes (64KB default)
  parameter MEM_FILE = ""         // Hex file to initialize memory
) (
  input  wire [XLEN-1:0] addr,        // Byte address
  output wire [31:0]     instruction  // Instruction output (always 32-bit in base ISA)
);

  // Memory array (byte-addressed for easier hex file loading)
  reg [7:0] mem [0:MEM_SIZE-1];

  // Initialize memory
  initial begin
    integer i;
    reg [31:0] temp_mem [0:(MEM_SIZE/4)-1];  // Temporary word array for loading

    // Initialize to NOP (ADDI x0, x0, 0) = 0x00000013 in little-endian bytes
    for (i = 0; i < MEM_SIZE; i = i + 4) begin
      mem[i]   = 8'h13;  // NOP byte 0
      mem[i+1] = 8'h00;  // NOP byte 1
      mem[i+2] = 8'h00;  // NOP byte 2
      mem[i+3] = 8'h00;  // NOP byte 3
    end

    // Load from file if specified
    // Hex file contains 32-bit words, need to convert to byte array
    if (MEM_FILE != "") begin
      $readmemh(MEM_FILE, temp_mem);

      // Convert word array to byte array (little-endian)
      for (i = 0; i < MEM_SIZE/4; i = i + 1) begin
        mem[i*4]   = temp_mem[i][7:0];    // Byte 0 (LSB)
        mem[i*4+1] = temp_mem[i][15:8];   // Byte 1
        mem[i*4+2] = temp_mem[i][23:16];  // Byte 2
        mem[i*4+3] = temp_mem[i][31:24];  // Byte 3 (MSB)
      end

      // Debug: Display first few instructions loaded
      $display("=== Instruction Memory Loaded ===");
      $display("MEM_FILE: %s", MEM_FILE);
      $display("First 4 instructions:");
      $display("  [0x00] = 0x%02h%02h%02h%02h", mem[3], mem[2], mem[1], mem[0]);
      $display("  [0x04] = 0x%02h%02h%02h%02h", mem[7], mem[6], mem[5], mem[4]);
      $display("  [0x08] = 0x%02h%02h%02h%02h", mem[11], mem[10], mem[9], mem[8]);
      $display("  [0x0C] = 0x%02h%02h%02h%02h", mem[15], mem[14], mem[13], mem[12]);
      $display("=================================");
    end
  end

  // Word-aligned read (assemble 4 bytes into 32-bit instruction, little-endian)
  // Mask address to fit within memory size (handles different base addresses)
  wire [XLEN-1:0] masked_addr = addr & (MEM_SIZE - 1);  // Mask to memory size
  wire [XLEN-1:0] word_addr = {masked_addr[XLEN-1:2], 2'b00};  // Align to word boundary
  assign instruction = {mem[word_addr+3], mem[word_addr+2], mem[word_addr+1], mem[word_addr]};

endmodule
