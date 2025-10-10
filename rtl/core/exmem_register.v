// EX/MEM Pipeline Register
// Latches outputs from Execute stage for use in Memory stage
// No stall or flush needed (hazards handled in earlier stages)

module exmem_register (
  input  wire        clk,
  input  wire        reset_n,

  // Inputs from EX stage
  input  wire [31:0] alu_result_in,
  input  wire [31:0] mem_write_data_in,  // Potentially forwarded rs2
  input  wire [4:0]  rd_addr_in,
  input  wire [31:0] pc_plus_4_in,       // For JAL/JALR write-back
  input  wire [2:0]  funct3_in,          // For memory access size/signedness

  // Control signals from EX stage
  input  wire        mem_read_in,
  input  wire        mem_write_in,
  input  wire        reg_write_in,
  input  wire [1:0]  wb_sel_in,
  input  wire        valid_in,

  // CSR signals from EX stage
  input  wire [11:0] csr_addr_in,
  input  wire        csr_we_in,
  input  wire [31:0] csr_rdata_in,    // CSR read data from CSR file

  // Exception signals from EX stage
  input  wire        is_mret_in,
  input  wire [31:0] instruction_in,
  input  wire [31:0] pc_in,           // For exception handling

  // Outputs to MEM stage
  output reg  [31:0] alu_result_out,
  output reg  [31:0] mem_write_data_out,
  output reg  [4:0]  rd_addr_out,
  output reg  [31:0] pc_plus_4_out,
  output reg  [2:0]  funct3_out,

  // Control signals to MEM stage
  output reg         mem_read_out,
  output reg         mem_write_out,
  output reg         reg_write_out,
  output reg  [1:0]  wb_sel_out,
  output reg         valid_out,

  // CSR signals to MEM stage
  output reg  [11:0] csr_addr_out,
  output reg         csr_we_out,
  output reg  [31:0] csr_rdata_out,

  // Exception signals to MEM stage
  output reg         is_mret_out,
  output reg  [31:0] instruction_out,
  output reg  [31:0] pc_out
);

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset: clear all outputs
      alu_result_out     <= 32'h0;
      mem_write_data_out <= 32'h0;
      rd_addr_out        <= 5'h0;
      pc_plus_4_out      <= 32'h0;
      funct3_out         <= 3'h0;

      mem_read_out       <= 1'b0;
      mem_write_out      <= 1'b0;
      reg_write_out      <= 1'b0;
      wb_sel_out         <= 2'b0;
      valid_out          <= 1'b0;

      csr_addr_out       <= 12'h0;
      csr_we_out         <= 1'b0;
      csr_rdata_out      <= 32'h0;

      is_mret_out        <= 1'b0;
      instruction_out    <= 32'h0;
      pc_out             <= 32'h0;
    end else begin
      // Normal operation: latch all values
      alu_result_out     <= alu_result_in;
      mem_write_data_out <= mem_write_data_in;
      rd_addr_out        <= rd_addr_in;
      pc_plus_4_out      <= pc_plus_4_in;
      funct3_out         <= funct3_in;

      mem_read_out       <= mem_read_in;
      mem_write_out      <= mem_write_in;
      reg_write_out      <= reg_write_in;
      wb_sel_out         <= wb_sel_in;
      valid_out          <= valid_in;

      csr_addr_out       <= csr_addr_in;
      csr_we_out         <= csr_we_in;
      csr_rdata_out      <= csr_rdata_in;

      is_mret_out        <= is_mret_in;
      instruction_out    <= instruction_in;
      pc_out             <= pc_in;
    end
  end

endmodule
