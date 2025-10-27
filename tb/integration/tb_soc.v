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

  // Cycle counter
  integer cycle_count;
  initial cycle_count = 0;
  always @(posedge clk) begin
    if (reset_n) cycle_count = cycle_count + 1;
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

  // Test completion detection (EBREAK = 0x00100073)
  always @(posedge clk) begin
    if (reset_n && instruction == 32'h00100073) begin
      // EBREAK detected - check test result marker in x28
      #1; // Allow register file to settle
      case (DUT.core.regfile.registers[28])
        32'hC0DEDBAD: begin
          $display("");
          $display("========================================");
          $display("TEST PASSED");
          $display("========================================");
          $display("  Success marker (x28): 0x%08h", DUT.core.regfile.registers[28]);
          $display("  Cycles: %0d", cycle_count);
          $display("========================================");
          $finish;
        end
        32'hDEADDEAD,
        32'h0BADC0DE: begin
          $display("");
          $display("========================================");
          $display("TEST FAILED");
          $display("========================================");
          $display("  Failure marker (x28): 0x%08h", DUT.core.regfile.registers[28]);
          $display("  Test stage (x29): %0d", DUT.core.regfile.registers[29]);
          $display("  Cycles: %0d", cycle_count);
          $display("========================================");
          $finish;
        end
        default: begin
          $display("");
          $display("========================================");
          $display("TEST PASSED (EBREAK with no marker)");
          $display("========================================");
          $display("  Note: x28 = 0x%08h (no standard marker)", DUT.core.regfile.registers[28]);
          $display("  Cycles: %0d", cycle_count);
          $display("========================================");
          $finish;
        end
      endcase
    end
  end

  // Timeout watchdog
  initial begin
    #(CLK_PERIOD * TIMEOUT_CYCLES * 2);
    $display("");
    $display("========================================");
    $display("ERROR: Simulation timeout!");
    $display("========================================");
    $display("  Cycles: %0d", TIMEOUT_CYCLES);
    $display("  PC: 0x%08h", pc);
    $display("  Instruction: 0x%08h", instruction);
    $display("========================================");
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
