// data_memory.v - Data memory for RISC-V
// Byte-addressable memory with byte/halfword/word/doubleword access
// Author: RV1 Project
// Date: 2025-10-09
// Updated: 2025-10-10 - Parameterized for XLEN (32/64-bit support)
// Updated: 2025-10-22 - Added FLEN parameter for RV32D support (64-bit FP on 32-bit CPU)

`include "config/rv_config.vh"

module data_memory #(
  parameter XLEN     = `XLEN,     // Integer data width: 32 or 64 bits
  parameter FLEN     = `FLEN,     // FP data width: 0 (no FPU), 32 (F-only), or 64 (F+D)
  parameter MEM_SIZE = 65536,     // Memory size in bytes (64KB default)
  parameter MEM_FILE = ""         // Hex file to initialize memory (for compliance tests)
) (
  input  wire             clk,         // Clock
  input  wire [XLEN-1:0]  addr,        // Byte address
  input  wire [63:0]      write_data,  // Data to write (max 64-bit for RV32D/RV64D)
  input  wire             mem_read,    // Read enable
  input  wire             mem_write,   // Write enable
  input  wire [2:0]       funct3,      // Function3 for size/sign
  output reg  [63:0]      read_data    // Data read from memory (max 64-bit for RV32D/RV64D)
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
      `ifdef DEBUG_ATOMIC
      if (addr >= 32'h80002000 && addr < 32'h80002010)
        $display("[DMEM] WRITE @ 0x%08h = 0x%08h (funct3=%b)", addr, write_data, funct3);
      `endif
      // DEBUG: Show writes to 0x80003000 range
      // if (addr >= 32'h80003000 && addr < 32'h80003010)
      //   $display("[DMEM] WRITE @ 0x%08h (masked=0x%04h) = 0x%08h", addr, masked_addr, write_data[31:0]);
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
        3'b011: begin  // SD/FSD (store doubleword) - supports RV64 and RV32D (FSD)
          // Write full 64 bits - supports both RV64 SD and RV32D FSD
          mem[masked_addr]     <= write_data[7:0];
          mem[masked_addr + 1] <= write_data[15:8];
          mem[masked_addr + 2] <= write_data[23:16];
          mem[masked_addr + 3] <= write_data[31:24];
          mem[masked_addr + 4] <= write_data[39:32];
          mem[masked_addr + 5] <= write_data[47:40];
          mem[masked_addr + 6] <= write_data[55:48];
          mem[masked_addr + 7] <= write_data[63:56];
        end
      endcase
    end
  end

  // Read operation
  always @(*) begin
    if (mem_read) begin
      // DEBUG: Show reads from 0x80003000 range
      // if (addr >= 32'h80003000 && addr < 32'h80003010)
      //   $display("[DMEM] READ  @ 0x%08h (masked=0x%04h) = mem[0x%04h]=0x%02h mem[0x%04h]=0x%02h mem[0x%04h]=0x%02h mem[0x%04h]=0x%02h",
      //            addr, masked_addr, masked_addr, mem[masked_addr], masked_addr+1, mem[masked_addr+1],
      //            masked_addr+2, mem[masked_addr+2], masked_addr+3, mem[masked_addr+3]);
      case (funct3)
        3'b000: begin  // LB (load byte, sign-extended)
          read_data = {{56{byte_data[7]}}, byte_data};
        end
        3'b001: begin  // LH (load halfword, sign-extended)
          read_data = {{48{halfword_data[15]}}, halfword_data};
        end
        3'b010: begin  // LW (load word, sign-extended for RV64, zero-extended for FLW)
          // Sign-extend for RV64 LD, but upper bits will be ignored for FLW
          read_data = {{32{word_data[31]}}, word_data};
        end
        3'b011: begin  // LD/FLD (load doubleword) - supports RV64 and RV32D
          // Return full 64 bits - works for both RV64 LD and RV32D FLD
          read_data = dword_data;
        end
        3'b100: begin  // LBU (load byte unsigned)
          read_data = {56'h0, byte_data};
        end
        3'b101: begin  // LHU (load halfword unsigned)
          read_data = {48'h0, halfword_data};
        end
        3'b110: begin  // LWU (load word unsigned - RV64 only)
          read_data = {32'h0, word_data};
        end
        default: begin
          read_data = 64'h0;
        end
      endcase
    end else begin
      read_data = 64'h0;
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
