// tb_core_pipelined_rv64.v - Integration testbench for pipelined RV64I core
// Tests the complete 5-stage pipelined processor in 64-bit mode
// Author: RV1 Project
// Date: 2025-10-10

`timescale 1ns/1ps

module tb_core_pipelined_rv64;

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
  wire [63:0] pc;
  wire [31:0] instruction;

  // Cycle counter
  integer cycle_count;

  // Reset vector
  parameter RESET_VEC = 64'h0000000000000000;

  // Instantiate DUT (pipelined core with XLEN=64)
  rv_core_pipelined #(
    .XLEN(64),
    .RESET_VECTOR(RESET_VEC),
    .IMEM_SIZE(16384),  // 16KB instruction memory
    .DMEM_SIZE(16384),  // 16KB data memory
    .MEM_FILE(MEM_INIT_FILE)
  ) DUT (
    .clk(clk),
    .reset_n(reset_n),
    .mtip_in(1'b0),      // No timer interrupt for basic tests
    .msip_in(1'b0),      // No software interrupt for basic tests
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
    $display("RV64I Pipelined Core Integration Test");
    $display("========================================");
    if (MEM_INIT_FILE != "") begin
      $display("Loading program from: %s", MEM_INIT_FILE);
    end else begin
      $display("No program loaded (using NOPs)");
    end
    $display("");

    // Dump waveforms
    $dumpfile("sim/waves/core_pipelined_rv64.vcd");
    $dumpvars(0, tb_core_pipelined_rv64);

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
      // $display("[%0d] PC=0x%016h, Instr=0x%08h", cycle_count, pc, instruction);

      // Check for EBREAK (0x00100073) or ECALL (0x00000073)
      if (instruction == 32'h00100073) begin
        // Wait for pipeline to flush (5 cycles)
        repeat(5) @(posedge clk);
        cycle_count = cycle_count + 5;

        $display("EBREAK encountered at cycle %0d", cycle_count);
        $display("Final PC: 0x%016h", pc);
        $display("");
        print_results();
        $display("");

        // Check return value in x10 (a0)
        if (DUT.regfile.registers[10] == 64'h000000000000600D) begin
          $display("========================================");
          $display("✓ TEST PASSED - RV64I Basic Test");
          $display("========================================");
          $display("  Return value (x10): 0x%016h", DUT.regfile.registers[10]);
          $display("  Expected:           0x000000000000600D (GOOD)");
        end else if (DUT.regfile.registers[10] == 64'h000000000000600D) begin
          $display("========================================");
          $display("✓ TEST PASSED - RV64I Arithmetic Test");
          $display("========================================");
          $display("  Return value (x10): 0x%016h", DUT.regfile.registers[10]);
          $display("  Expected:           0x000000000000600D (GOOD)");
        end else if (DUT.regfile.registers[10] == 64'hFFFFFFFFFFFFFFFF) begin
          $display("========================================");
          $display("✗ TEST FAILED");
          $display("========================================");
          $display("  Return value (x10): 0x%016h", DUT.regfile.registers[10]);
          $display("  Failure code detected!");
        end else begin
          $display("========================================");
          $display("Test Complete");
          $display("========================================");
          $display("  Return value (x10): 0x%016h", DUT.regfile.registers[10]);
        end

        $display("  Cycles: %0d", cycle_count);
        $finish;
      end

      // Timeout check
      if (cycle_count >= TIMEOUT - 1) begin
        $display("WARNING: Timeout reached (%0d cycles)", TIMEOUT);
        $display("Final PC: 0x%016h", pc);
        $display("Last instruction: 0x%08h", instruction);
        print_results();
        $display("");
        $display("Test TIMEOUT (may need more cycles or infinite loop)");
        $finish;
      end
    end
  end

  // Task to print register file contents (64-bit format)
  task print_results;
    integer i;
    begin
      $display("=== Final Register File Contents (64-bit) ===");
      $display("x0  (zero) = 0x%016h", DUT.regfile.registers[0]);
      $display("x1  (ra)   = 0x%016h", DUT.regfile.registers[1]);
      $display("x2  (sp)   = 0x%016h", DUT.regfile.registers[2]);
      $display("x3  (gp)   = 0x%016h", DUT.regfile.registers[3]);
      $display("x4  (tp)   = 0x%016h", DUT.regfile.registers[4]);
      $display("x5  (t0)   = 0x%016h", DUT.regfile.registers[5]);
      $display("x6  (t1)   = 0x%016h", DUT.regfile.registers[6]);
      $display("x7  (t2)   = 0x%016h", DUT.regfile.registers[7]);
      $display("x8  (s0)   = 0x%016h", DUT.regfile.registers[8]);
      $display("x9  (s1)   = 0x%016h", DUT.regfile.registers[9]);
      $display("x10 (a0)   = 0x%016h (return value)", DUT.regfile.registers[10]);
      $display("x11 (a1)   = 0x%016h", DUT.regfile.registers[11]);
      $display("x12 (a2)   = 0x%016h", DUT.regfile.registers[12]);
      $display("x13 (a3)   = 0x%016h", DUT.regfile.registers[13]);
      $display("x14 (a4)   = 0x%016h", DUT.regfile.registers[14]);
      $display("x15 (a5)   = 0x%016h", DUT.regfile.registers[15]);
      $display("x16 (a6)   = 0x%016h", DUT.regfile.registers[16]);
      $display("x17 (a7)   = 0x%016h", DUT.regfile.registers[17]);
      $display("x18 (s2)   = 0x%016h", DUT.regfile.registers[18]);
      $display("x19 (s3)   = 0x%016h", DUT.regfile.registers[19]);
      $display("x20 (s4)   = 0x%016h", DUT.regfile.registers[20]);
      $display("x21 (s5)   = 0x%016h", DUT.regfile.registers[21]);
      $display("x22 (s6)   = 0x%016h", DUT.regfile.registers[22]);
      $display("x23 (s7)   = 0x%016h", DUT.regfile.registers[23]);
      $display("x24 (s8)   = 0x%016h", DUT.regfile.registers[24]);
      $display("x25 (s9)   = 0x%016h", DUT.regfile.registers[25]);
      $display("x26 (s10)  = 0x%016h", DUT.regfile.registers[26]);
      $display("x27 (s11)  = 0x%016h", DUT.regfile.registers[27]);
      $display("x28 (t3)   = 0x%016h", DUT.regfile.registers[28]);
      $display("x29 (t4)   = 0x%016h", DUT.regfile.registers[29]);
      $display("x30 (t5)   = 0x%016h", DUT.regfile.registers[30]);
      $display("x31 (t6)   = 0x%016h", DUT.regfile.registers[31]);
      $display("");
      $display("Total cycles: %0d", cycle_count);
    end
  endtask

  // Pipeline stage monitoring (optional - enable for debug)
  /*
  always @(posedge clk) begin
    if (reset_n) begin
      $display("[%0d] IF: PC=0x%016h | ID: PC=0x%016h | EX: PC=0x%016h",
        cycle_count,
        pc,
        DUT.ifid_pc,
        DUT.idex_pc
      );
    end
  end
  */

endmodule
