// tb_core.v - Integration testbench for RV32I core
// Tests the complete processor with test programs
// Author: RV1 Project
// Date: 2025-10-09

`timescale 1ns/1ps

module tb_core;

  // Clock parameters
  parameter CLK_PERIOD = 10;          // 100MHz
  parameter TIMEOUT = 10000;          // Maximum cycles

  // Memory file (can be overridden with -D)
  `ifdef MEM_FILE
    parameter MEM_INIT_FILE = `MEM_FILE;
  `else
    parameter MEM_INIT_FILE = "";
  `endif

  // Testbench signals
  reg         clk;
  reg         reset_n;
  wire [31:0] pc;
  wire [31:0] instruction;

  // Cycle counter
  integer cycle_count;

  // RISC-V compliance tests start at 0x80000000
  `ifdef COMPLIANCE_TEST
    parameter RESET_VEC = 32'h80000000;
  `else
    parameter RESET_VEC = 32'h00000000;
  `endif

  // Instantiate DUT
  // Use larger memory for compliance tests (16KB each)
  rv32i_core #(
    .RESET_VECTOR(RESET_VEC),
    .IMEM_SIZE(16384),  // 16KB instruction memory
    .DMEM_SIZE(16384),  // 16KB data memory
    .MEM_FILE(MEM_INIT_FILE)
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
    $display("========================================");
    $display("RV32I Core Integration Test");
    $display("========================================");
    if (MEM_INIT_FILE != "") begin
      $display("Loading program from: %s", MEM_INIT_FILE);
    end else begin
      $display("No program loaded (using NOPs)");
    end
    $display("");

    // Dump waveforms
    $dumpfile("sim/waves/core.vcd");
    $dumpvars(0, tb_core);

    // Initialize
    reset_n = 0;
    cycle_count = 0;

    // Hold reset for a few cycles
    repeat(5) @(posedge clk);
    reset_n = 1;
    $display("Reset released at time %0t", $time);
    $display("");

    // Run for specified cycles or until EBREAK/ECALL
    repeat(TIMEOUT) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;

      // Debug: print PC and instruction every cycle (can be commented out)
      // $display("[%0d] PC=0x%08h, Instr=0x%08h", cycle_count, pc, instruction);

      // Check for EBREAK (0x00100073) or ECALL (0x00000073)
      if (instruction == 32'h00100073) begin
        $display("EBREAK encountered at cycle %0d", cycle_count);
        $display("Final PC: 0x%08h", pc);
        $display("");
        print_results();
        $display("");
        $display("Test PASSED");
        $finish;
      end

      `ifdef COMPLIANCE_TEST
      // Check for ECALL (0x00000073) - used by RISC-V compliance tests
      if (instruction == 32'h00000073) begin
        $display("ECALL encountered at cycle %0d", cycle_count);
        $display("Final PC: 0x%08h", pc);
        $display("");

        // Check gp (x3) register for pass/fail
        if (DUT.regfile.registers[3] == 1) begin
          $display("========================================");
          $display("RISC-V COMPLIANCE TEST PASSED");
          $display("========================================");
          $display("  Test result (gp/x3): %0d", DUT.regfile.registers[3]);
          $display("  Cycles: %0d", cycle_count);
          $finish;
        end else begin
          $display("========================================");
          $display("RISC-V COMPLIANCE TEST FAILED");
          $display("========================================");
          $display("  Failed at test number: %0d", DUT.regfile.registers[3]);
          $display("  Final PC: 0x%08h", pc);
          $display("  Cycles: %0d", cycle_count);
          print_results();
          $finish;
        end
      end
      `endif
    end

    // Timeout
    $display("ERROR: Timeout after %0d cycles", TIMEOUT);
    $display("Final PC: 0x%08h", pc);
    $finish;
  end

  // Print interesting register values
  task print_results;
    begin
      $display("Final Register Values:");
      $display("  x0  (zero) = 0x%08h", DUT.regfile.registers[0]);
      $display("  x1  (ra)   = 0x%08h", DUT.regfile.registers[1]);
      $display("  x2  (sp)   = 0x%08h", DUT.regfile.registers[2]);
      $display("  x10 (a0)   = 0x%08h (decimal: %0d)",
               DUT.regfile.registers[10], DUT.regfile.registers[10]);
      $display("  x11 (a1)   = 0x%08h (decimal: %0d)",
               DUT.regfile.registers[11], DUT.regfile.registers[11]);
      $display("  x12 (a2)   = 0x%08h (decimal: %0d)",
               DUT.regfile.registers[12], DUT.regfile.registers[12]);
      $display("Cycles executed: %0d", cycle_count);
    end
  endtask

  // Monitor (optional - can be commented out for cleaner output)
  // initial begin
  //   $monitor("Time=%0t Cycle=%0d PC=0x%08h Instr=0x%08h",
  //            $time, cycle_count, pc, instruction);
  // end

endmodule
