// tb_rvc_minimal.v - Testbench for minimal RVC test with proper ebreak handling
// Tests basic compressed instruction functionality
`timescale 1ns / 1ps

module tb_rvc_minimal;
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
    .MEM_FILE("tests/asm/test_rvc_minimal.hex")
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

  // Reset stimulus
  initial begin
    reset_n = 0;
    #20;
    reset_n = 1;
  end

  // Test execution
  integer cycle_count;
  initial cycle_count = 0;

  always @(posedge clk) begin
    if (reset_n) begin
      cycle_count = cycle_count + 1;

      // After 12 cycles, the c.add result should be written
      // Based on pipeline analysis: instruction at cycle 5 writes back at cycle 9
      if (cycle_count == 12) begin
        $display("\n========================================");
        $display("  test_rvc_minimal - Results");
        $display("========================================");
        $display("x10 (a0) = %d (expected 15)", dut.regfile.registers[10]);
        $display("x11 (a1) = %d (expected 5)", dut.regfile.registers[11]);
        $display("========================================");

        if (dut.regfile.registers[10] == 15 && dut.regfile.registers[11] == 5) begin
          $display("✓✓✓ TEST PASSED ✓✓✓");
          $display("All compressed instructions executed correctly!");
        end else begin
          $display("✗ TEST FAILED");
          $display("Cycle count: %0d", cycle_count);
        end
        $display("========================================\n");

        $finish;
      end
    end
  end

  // Safety timeout
  initial begin
    #1000;
    $display("\nTIMEOUT: Test did not complete in expected time");
    $display("x10 = %d, x11 = %d", dut.regfile.registers[10], dut.regfile.registers[11]);
    $finish;
  end

  // Optional: Monitor for debugging
  initial begin
    if ($test$plusargs("debug")) begin
      $dumpfile("sim/waves/tb_rvc_minimal.vcd");
      $dumpvars(0, tb_rvc_minimal);
    end
  end

endmodule
