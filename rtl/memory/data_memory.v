// data_memory.v - Data memory for RISC-V
// Byte-addressable memory with byte/halfword/word/doubleword access
// Author: RV1 Project
// Date: 2025-10-09
// Updated: 2025-10-10 - Parameterized for XLEN (32/64-bit support)

`include "config/rv_config.vh"

module data_memory #(
  parameter XLEN     = `XLEN,     // Data width: 32 or 64 bits
  parameter MEM_SIZE = 65536,     // Memory size in bytes (64KB default)
  parameter MEM_FILE = ""         // Hex file to initialize memory (for compliance tests)
) (
  input  wire             clk,         // Clock
  input  wire [XLEN-1:0]  addr,        // Byte address
  input  wire [XLEN-1:0]  write_data,  // Data to write
  input  wire             mem_read,    // Read enable
  input  wire             mem_write,   // Write enable
  input  wire [2:0]       funct3,      // Function3 for size/sign
  output reg  [XLEN-1:0]  read_data    // Data read from memory
);

  // Memory array (byte-addressable)
  reg [7:0] mem [0:MEM_SIZE-1];

  // Internal signals
  wire [XLEN-1:0] masked_addr;
  wire [XLEN-1:0] word_addr;
  wire [XLEN-1:0] dword_addr;  // For RV64 doubleword access
  wire [2:0]      byte_offset;
  wire [7:0]      byte_data;
  wire [15:0]     halfword_data;
  wire [31:0]     word_data;
  wire [63:0]     dword_data;  // For RV64

  // Mask address to fit within memory size (handles different base addresses)
  assign masked_addr = addr & (MEM_SIZE - 1);
  assign word_addr = {masked_addr[XLEN-1:2], 2'b00};    // Word-aligned address
  assign dword_addr = {masked_addr[XLEN-1:3], 3'b000}; // Doubleword-aligned (RV64)
  assign byte_offset = masked_addr[2:0];

  // Read data from memory (little-endian)
  // Using masked_addr directly to support misaligned access
  assign byte_data = mem[masked_addr];
  assign halfword_data = {mem[masked_addr + 1], mem[masked_addr]};
  assign word_data = {mem[masked_addr + 3], mem[masked_addr + 2],
                      mem[masked_addr + 1], mem[masked_addr]};

  // Doubleword data for RV64
  assign dword_data = {mem[masked_addr + 7], mem[masked_addr + 6],
                       mem[masked_addr + 5], mem[masked_addr + 4],
                       mem[masked_addr + 3], mem[masked_addr + 2],
                       mem[masked_addr + 1], mem[masked_addr]};

  // Write operation
  always @(posedge clk) begin
    if (mem_write) begin
      case (funct3)
        3'b000: begin  // SB (store byte)
          mem[masked_addr] <= write_data[7:0];
        end
        3'b001: begin  // SH (store halfword)
          mem[masked_addr]     <= write_data[7:0];
          mem[masked_addr + 1] <= write_data[15:8];
        end
        3'b010: begin  // SW (store word) - supports misaligned access
          mem[masked_addr]     <= write_data[7:0];
          mem[masked_addr + 1] <= write_data[15:8];
          mem[masked_addr + 2] <= write_data[23:16];
          mem[masked_addr + 3] <= write_data[31:24];
        end
        3'b011: begin  // SD (store doubleword - RV64 only) - supports misaligned access
          if (XLEN == 64) begin
            mem[masked_addr]     <= write_data[7:0];
            mem[masked_addr + 1] <= write_data[15:8];
            mem[masked_addr + 2] <= write_data[23:16];
            mem[masked_addr + 3] <= write_data[31:24];
            mem[masked_addr + 4] <= write_data[39:32];
            mem[masked_addr + 5] <= write_data[47:40];
            mem[masked_addr + 6] <= write_data[55:48];
            mem[masked_addr + 7] <= write_data[63:56];
          end
        end
      endcase
    end
  end

  // Read operation
  always @(*) begin
    if (mem_read) begin
      case (funct3)
        3'b000: begin  // LB (load byte, sign-extended)
          read_data = {{(XLEN-8){byte_data[7]}}, byte_data};
        end
        3'b001: begin  // LH (load halfword, sign-extended)
          read_data = {{(XLEN-16){halfword_data[15]}}, halfword_data};
        end
        3'b010: begin  // LW (load word, sign-extended for RV64)
          if (XLEN == 64)
            read_data = {{32{word_data[31]}}, word_data};  // Sign-extend for RV64
          else
            read_data = word_data;
        end
        3'b011: begin  // LD (load doubleword - RV64 only)
          if (XLEN == 64)
            read_data = dword_data;
          else
            read_data = {XLEN{1'b0}};
        end
        3'b100: begin  // LBU (load byte unsigned)
          read_data = {{(XLEN-8){1'b0}}, byte_data};
        end
        3'b101: begin  // LHU (load halfword unsigned)
          read_data = {{(XLEN-16){1'b0}}, halfword_data};
        end
        3'b110: begin  // LWU (load word unsigned - RV64 only)
          if (XLEN == 64)
            read_data = {32'h0, word_data};  // Zero-extend for RV64
          else
            read_data = {XLEN{1'b0}};
        end
        default: begin
          read_data = {XLEN{1'b0}};
        end
      endcase
    end else begin
      read_data = {XLEN{1'b0}};
    end
  end

  // Initialize memory
  initial begin
    integer i;

    // Initialize to zero
    for (i = 0; i < MEM_SIZE; i = i + 1) begin
      mem[i] = 8'h0;
    end

    // Load from file if specified (for compliance tests with embedded data)
    // Hex file format from "objcopy -O verilog" contains space-separated hex bytes
    // $readmemh treats each space-separated value as one byte
    // Note: Memory addresses in hex file may be outside our address range, which is OK
    // since we use address masking to wrap addresses into our memory space
    if (MEM_FILE != "") begin
      $readmemh(MEM_FILE, mem);
    end
  end

endmodule
