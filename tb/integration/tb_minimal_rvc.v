// Minimal testbench - no event waiting, just time delays
`timescale 1ns / 1ps

module tb_minimal_rvc;
  reg clk;
  reg reset_n;

  rv_core_pipelined #(
    .XLEN(32),
    .RESET_VECTOR(32'h0),
    .IMEM_SIZE(1024),
    .DMEM_SIZE(1024),
    .MEM_FILE("tests/asm/test_rvc_simple.hex")
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(),
    .instr_out()
  );

  initial begin
    $display("Starting minimal test...");
    clk = 0;
    reset_n = 0;

    #10 reset_n = 1;
    $display("Reset released at time %0t", $time);

    #10 clk = 1;
    $display("Clock high at time %0t", $time);

    #10 clk = 0;
    $display("Clock low at time %0t", $time);

    #10 clk = 1;
    $display("Clock high at time %0t", $time);

    #10 clk = 0;
    $display("Clock low at time %0t", $time);

    $display("Test completed successfully!");
    $finish;
  end

endmodule
