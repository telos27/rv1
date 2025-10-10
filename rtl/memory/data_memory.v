// data_memory.v - Data memory for RV32I
// Byte-addressable memory with byte/halfword/word access
// Author: RV1 Project
// Date: 2025-10-09

module data_memory #(
  parameter MEM_SIZE = 4096       // Memory size in bytes (4KB default)
) (
  input  wire        clk,         // Clock
  input  wire [31:0] addr,        // Byte address
  input  wire [31:0] write_data,  // Data to write
  input  wire        mem_read,    // Read enable
  input  wire        mem_write,   // Write enable
  input  wire [2:0]  funct3,      // Function3 for size/sign
  output reg  [31:0] read_data    // Data read from memory
);

  // Memory array (byte-addressable)
  reg [7:0] mem [0:MEM_SIZE-1];

  // Internal signals
  wire [31:0] masked_addr;
  wire [31:0] word_addr;
  wire [1:0]  byte_offset;
  wire [7:0]  byte_data;
  wire [15:0] halfword_data;
  wire [31:0] word_data;

  // Mask address to fit within memory size (handles different base addresses)
  assign masked_addr = addr & (MEM_SIZE - 1);
  assign word_addr = {masked_addr[31:2], 2'b00};  // Word-aligned address
  assign byte_offset = masked_addr[1:0];

  // Read data from memory
  assign byte_data = mem[masked_addr];
  assign halfword_data = {mem[word_addr + 1], mem[word_addr]};
  assign word_data = {mem[word_addr + 3], mem[word_addr + 2],
                      mem[word_addr + 1], mem[word_addr]};

  // Write operation
  always @(posedge clk) begin
    if (mem_write) begin
      case (funct3)
        3'b000: begin  // SB (store byte)
          mem[masked_addr] <= write_data[7:0];
        end
        3'b001: begin  // SH (store halfword)
          mem[word_addr]     <= write_data[7:0];
          mem[word_addr + 1] <= write_data[15:8];
        end
        3'b010: begin  // SW (store word)
          mem[word_addr]     <= write_data[7:0];
          mem[word_addr + 1] <= write_data[15:8];
          mem[word_addr + 2] <= write_data[23:16];
          mem[word_addr + 3] <= write_data[31:24];
        end
      endcase
    end
  end

  // Read operation
  always @(*) begin
    if (mem_read) begin
      case (funct3)
        3'b000: begin  // LB (load byte, sign-extended)
          read_data = {{24{byte_data[7]}}, byte_data};
        end
        3'b001: begin  // LH (load halfword, sign-extended)
          read_data = {{16{halfword_data[15]}}, halfword_data};
        end
        3'b010: begin  // LW (load word)
          read_data = word_data;
        end
        3'b100: begin  // LBU (load byte unsigned)
          read_data = {24'h0, byte_data};
        end
        3'b101: begin  // LHU (load halfword unsigned)
          read_data = {16'h0, halfword_data};
        end
        default: begin
          read_data = 32'h0;
        end
      endcase
    end else begin
      read_data = 32'h0;
    end
  end

  // Initialize memory to zero
  integer i;
  initial begin
    for (i = 0; i < MEM_SIZE; i = i + 1) begin
      mem[i] = 8'h0;
    end
  end

endmodule
