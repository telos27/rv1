// Wrapper for Verilator testing with C extension
module rv_core_pipelined_wrapper (
  input  wire        clk,
  input  wire        reset_n,
  output wire [31:0] pc_out,
  output wire [31:0] instr_out
);

  rv_core_pipelined #(
    .XLEN(32),
    .RESET_VECTOR(32'h0),
    .IMEM_SIZE(1024),
    .DMEM_SIZE(1024),
    .MEM_FILE("tests/asm/test_rvc_simple.hex")
  ) core (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(pc_out),
    .instr_out(instr_out)
  );

endmodule
