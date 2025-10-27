// tb_soc.v - Testbench for RV1 SoC
// Tests SoC integration with CLINT
// Author: RV1 Project
// Date: 2025-10-26

`timescale 1ns/1ps

module tb_soc;

  // Parameters
  parameter CLK_PERIOD = 10;        // 100 MHz clock
  parameter TIMEOUT_CYCLES = 10000; // Maximum cycles before timeout

  // DUT signals
  reg  clk;
  reg  reset_n;
  wire [31:0] pc;
  wire [31:0] instruction;

  // Test memory file (can be overridden)
  `ifdef MEM_INIT_FILE
    parameter MEM_FILE = `MEM_INIT_FILE;
  `else
    parameter MEM_FILE = "";
  `endif

  // Instantiate SoC
  rv_soc #(
    .XLEN(32),
    .RESET_VECTOR(32'h00000000),
    .IMEM_SIZE(16384),
    .DMEM_SIZE(16384),
    .MEM_FILE(MEM_FILE),
    .NUM_HARTS(1)
  ) DUT (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(pc),
    .instr_out(instruction)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // Test sequence
  initial begin
    // Initialize
    reset_n = 0;

    // Hold reset for a few cycles
    repeat (5) @(posedge clk);
    reset_n = 1;

    // Let the program run
    repeat (TIMEOUT_CYCLES) @(posedge clk);

    $display("Simulation completed after %0d cycles", TIMEOUT_CYCLES);
    $finish;
  end

  // Monitor execution
  initial begin
    $display("========================================");
    $display("RV1 SoC Testbench");
    $display("========================================");
    $display("Clock Period: %0d ns", CLK_PERIOD);
    $display("Memory File: %s", MEM_FILE);
    $display("========================================");
  end

  // Timeout watchdog
  initial begin
    #(CLK_PERIOD * TIMEOUT_CYCLES * 2);
    $display("ERROR: Simulation timeout!");
    $finish;
  end

  // Optional: Dump waveforms
  initial begin
    `ifdef VCD_FILE
      $dumpfile(`VCD_FILE);
      $dumpvars(0, tb_soc);
    `endif
  end

endmodule
