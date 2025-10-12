// tb_simple_test.v - Simple testbench for basic instruction execution
// Tests a few basic instructions and generates waveform

`timescale 1ns / 1ps

module tb_simple_test;

  reg clk;
  reg reset_n;
  wire [31:0] pc_out;
  wire [31:0] instr_out;

  // Clock generation
  always #5 clk = ~clk;

  // DUT instantiation
  rv32i_core dut (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(pc_out),
    .instr_out(instr_out)
  );

  // Test program monitor
  integer cycle_count;

  initial begin
    // Initialize
    clk = 0;
    reset_n = 0;
    cycle_count = 0;

    // Dump waveform
    $dumpfile("simple_test.vcd");
    $dumpvars(0, tb_simple_test);

    // Reset
    #10 reset_n = 1;

    $display("\n=== Simple Instruction Test ===\n");
    $display("Time | Cycle | PC   | Instruction");
    $display("-----|-------|------|------------");

    // Monitor execution
    repeat(20) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
      $display("%4t | %5d | %04h | %08h", $time, cycle_count, pc_out, instr_out);
    end

    // Check register file values (if accessible)
    $display("\n=== Execution Complete ===");

    $display("\n=== Test Complete ===");
    $display("Waveform saved to: simple_test.vcd");
    $display("View with: gtkwave simple_test.vcd\n");

    $finish;
  end

endmodule
