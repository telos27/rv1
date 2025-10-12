// instruction_memory.v - Instruction memory for RISC-V
// Memory for program storage (writable for FENCE.I self-modifying code support)
// Author: RV1 Project
// Date: 2025-10-09
// Updated: 2025-10-10 - Parameterized for XLEN (32/64-bit address support)
// Updated: 2025-10-11 - Added write capability for FENCE.I compliance
// Updated: 2025-10-11 - Added support for C extension (16-bit aligned access)

`include "config/rv_config.vh"

module instruction_memory #(
  parameter XLEN     = `XLEN,     // Address width: 32 or 64 bits
  parameter MEM_SIZE = 65536,     // Memory size in bytes (64KB default)
  parameter MEM_FILE = ""         // Hex file to initialize memory
) (
  input  wire             clk,          // Clock for writes
  input  wire [XLEN-1:0]  addr,         // Byte address for reads
  output wire [31:0]      instruction,  // Instruction output (always 32-bit in base ISA)

  // Write interface for FENCE.I support (self-modifying code)
  input  wire             mem_write,    // Write enable
  input  wire [XLEN-1:0]  write_addr,   // Write address
  input  wire [XLEN-1:0]  write_data,   // Data to write
  input  wire [2:0]       funct3        // Store operation type (SB/SH/SW/SD)
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
    // Hex file format from "objcopy -O verilog" contains space-separated hex bytes
    // $readmemh treats each space-separated value as one byte
    if (MEM_FILE != "") begin
      $readmemh(MEM_FILE, mem);

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

  // Read instruction (supports both 16-bit and 32-bit alignment for C extension)
  // Fetches 32 bits starting at the given address (which can be 2-byte aligned)
  // This allows fetching compressed (16-bit) instructions at any half-word boundary
  // Mask address to fit within memory size (handles different base addresses)
  wire [XLEN-1:0] masked_addr = addr & (MEM_SIZE - 1);  // Mask to memory size
  wire [XLEN-1:0] halfword_addr = {masked_addr[XLEN-1:1], 1'b0};  // Align to halfword boundary

  // Fetch 32 bits (4 bytes) starting at the half-word aligned address
  // This enables reading a full 32-bit instruction or two 16-bit compressed instructions
  assign instruction = {mem[halfword_addr+3], mem[halfword_addr+2],
                        mem[halfword_addr+1], mem[halfword_addr]};

  // Write operation (for self-modifying code via FENCE.I)
  // This allows data stores to modify instruction memory
  wire [XLEN-1:0] write_masked_addr;
  wire [XLEN-1:0] write_word_addr;
  wire [XLEN-1:0] write_dword_addr;

  assign write_masked_addr = write_addr & (MEM_SIZE - 1);  // Mask write address
  assign write_word_addr = {write_masked_addr[XLEN-1:2], 2'b00};
  assign write_dword_addr = {write_masked_addr[XLEN-1:3], 3'b000};

  always @(posedge clk) begin
    if (mem_write) begin
      case (funct3)
        3'b000: begin  // SB (store byte)
          mem[write_masked_addr] <= write_data[7:0];
        end
        3'b001: begin  // SH (store halfword)
          mem[write_masked_addr]     <= write_data[7:0];
          mem[write_masked_addr + 1] <= write_data[15:8];
        end
        3'b010: begin  // SW (store word)
          mem[write_word_addr]     <= write_data[7:0];
          mem[write_word_addr + 1] <= write_data[15:8];
          mem[write_word_addr + 2] <= write_data[23:16];
          mem[write_word_addr + 3] <= write_data[31:24];
        end
        3'b011: begin  // SD (store doubleword - RV64 only)
          if (XLEN == 64) begin
            mem[write_dword_addr]     <= write_data[7:0];
            mem[write_dword_addr + 1] <= write_data[15:8];
            mem[write_dword_addr + 2] <= write_data[23:16];
            mem[write_dword_addr + 3] <= write_data[31:24];
            mem[write_dword_addr + 4] <= write_data[39:32];
            mem[write_dword_addr + 5] <= write_data[47:40];
            mem[write_dword_addr + 6] <= write_data[55:48];
            mem[write_dword_addr + 7] <= write_data[63:56];
          end
        end
      endcase
    end
  end

endmodule
