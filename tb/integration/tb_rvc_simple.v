// tb_rvc_simple.v - Simple testbench for RVC integration testing
// Tests compressed instruction execution in the pipeline

`timescale 1ns / 1ps

module tb_rvc_simple;
  reg clk;
  reg reset_n;
  wire [31:0] pc_out;
  wire [31:0] instr_out;

  // Instantiate the pipelined core
  rv_core_pipelined #(
    .XLEN(32),
    .RESET_VECTOR(32'h0),
    .IMEM_SIZE(1024),
    .DMEM_SIZE(1024),
    .MEM_FILE("tests/asm/test_rvc_simple.hex")
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(pc_out),
    .instr_out(instr_out)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Test stimulus with proper ebreak handling
  reg test_complete;
  initial test_complete = 0;

  // Test control
  initial begin
    // Optional VCD dump for debugging
    if ($test$plusargs("debug")) begin
      $dumpfile("sim/waves/tb_rvc_simple.vcd");
      $dumpvars(0, tb_rvc_simple);
    end

    // Reset
    reset_n = 0;
    #20;
    reset_n = 1;
  end

  // Use cycle counting to check results
  integer cycle_count;
  initial cycle_count = 0;

  always @(posedge clk) begin
    if (reset_n) begin
      cycle_count = cycle_count + 1;

      // After 30 cycles, all instructions should have completed
      if (cycle_count == 30 && !test_complete) begin
        test_complete = 1;

        $display("\n========================================");
        $display("  test_rvc_simple - Results");
        $display("========================================");
        $display("x10 (a0) = %d (expected 42)", dut.regfile.registers[10]);
        $display("x11 (a1) = %d (expected 5)", dut.regfile.registers[11]);
        $display("x12 (a2) = %d (expected 15)", dut.regfile.registers[12]);
        $display("========================================");

        if (dut.regfile.registers[10] == 42 &&
            dut.regfile.registers[11] == 5 &&
            dut.regfile.registers[12] == 15) begin
          $display("✓✓✓ TEST PASSED ✓✓✓");
          $display("Mixed compressed and normal instructions work correctly!");
        end else begin
          $display("✗ TEST FAILED");
        end
        $display("========================================\n");

        $finish;
      end
    end
  end

  // Optional monitoring for debugging
  always @(posedge clk) begin
    if (reset_n && $test$plusargs("verbose")) begin
      $display("Cycle %0d: PC=0x%h, Instr=0x%h, is_c=%b",
               $time/10, pc_out, instr_out, dut.if_is_compressed);
    end
  end

  // Safety timeout
  initial begin
    #2000;
    if (!test_complete) begin
      $display("\nTIMEOUT - Test did not complete");
      $display("x10 = %d (expected 42)", dut.regfile.registers[10]);
      $display("x11 = %d (expected 5)", dut.regfile.registers[11]);
      $display("x12 = %d (expected 15)", dut.regfile.registers[12]);
      $finish;
    end
  end

endmodule
