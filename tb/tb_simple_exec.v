// tb_simple_exec.v - Simple testbench for program execution
// Loads and executes test_simple.hex

`timescale 1ns / 1ps

module tb_simple_exec;

  reg clk;
  reg reset_n;
  wire [31:0] pc_out;
  wire [31:0] instr_out;

  // Clock generation (10ns period = 100MHz)
  always #5 clk = ~clk;

  // DUT instantiation
  rv32i_core #(
    .IMEM_SIZE(4096),
    .DMEM_SIZE(4096),
    .MEM_FILE("tests/asm/test_simple.hex")
  ) dut (
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
    $dumpfile("simple_program.vcd");
    $dumpvars(0, tb_simple_exec);

    // Reset
    #10 reset_n = 1;
    #5;

    $display("\n=== Simple Program Execution Test ===\n");
    $display("Program: tests/asm/test_simple.hex");
    $display("\nCycle | PC       | Instruction");
    $display("------|----------|------------");

    // Monitor execution for 30 cycles
    repeat(30) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
      $display("%5d | %08h | %08h", cycle_count, pc_out, instr_out);
    end

    $display("\n=== Test Complete ===");
    $display("Waveform saved to: simple_program.vcd");
    $display("\nTo view waveform:");
    $display("  gtkwave simple_program.vcd");
    $display("\nKey signals to observe:");
    $display("  - clk, reset_n");
    $display("  - pc_out (Program Counter)");
    $display("  - instr_out (Current Instruction)");
    $display("  - dut.regfile.registers[10:15] (Registers x10-x15)\n");

    $finish;
  end

endmodule
