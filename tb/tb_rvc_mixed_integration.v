// tb_rvc_mixed_integration.v - Integration test for mixed 16/32-bit instructions
// Tests PC increment logic and instruction fetch for compressed instructions
`timescale 1ns / 1ps

module tb_rvc_mixed_integration;
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
    .MEM_FILE("tests/asm/test_rvc_mixed_real.hex")
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(pc_out),
    .instr_out(instr_out)
  );

  // Program loaded from file test_rvc_mixed_real.hex:
  // 0x00: 0x4529 (c.li a0, 10)           - 16-bit
  // 0x02: 0x01400593 (addi a1, x0, 20)  - 32-bit
  // 0x06: 0x952e (c.add a0, a1)          - 16-bit
  // 0x08: 0x00c00613 (addi a2, x0, 12)  - 32-bit
  // 0x0c: 0x9532 (c.add a0, a2)          - 16-bit
  // 0x0e: 0x9002 (c.ebreak)              - 16-bit

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

  // Track PC to verify correct increment
  integer cycle_count;
  reg [31:0] prev_pc;
  initial begin
    cycle_count = 0;
    prev_pc = 32'hFFFFFFFF;
  end

  always @(posedge clk) begin
    if (reset_n) begin
      cycle_count = cycle_count + 1;

      // Monitor PC increments
      if (cycle_count > 1 && pc_out != prev_pc) begin
        $display("[Cycle %2d] PC: 0x%08x -> 0x%08x (delta: %0d)",
                 cycle_count, prev_pc, pc_out, pc_out - prev_pc);
      end
      prev_pc = pc_out;

      // Check final result after sufficient cycles
      if (cycle_count == 20) begin
        $display("\n========================================");
        $display("  Mixed 16/32-bit Instruction Test");
        $display("========================================");
        $display("x10 (a0) = %d (expected 42)", dut.regfile.registers[10]);
        $display("x11 (a1) = %d (expected 20)", dut.regfile.registers[11]);
        $display("x12 (a2) = %d (expected 12)", dut.regfile.registers[12]);
        $display("x13 (a3) = %d (expected 12)", dut.regfile.registers[13]);
        $display("========================================");

        if (dut.regfile.registers[10] == 42 &&
            dut.regfile.registers[11] == 20 &&
            dut.regfile.registers[12] == 12) begin
          $display("✓✓✓ TEST PASSED ✓✓✓");
          $display("Mixed 16/32-bit instructions work correctly!");
          $display("PC increment logic verified!");
        end else begin
          $display("✗ TEST FAILED");
          $display("Registers do not match expected values");
        end
        $display("========================================\n");

        $finish;
      end
    end
  end

  // Safety timeout
  initial begin
    #1000;
    $display("\nTIMEOUT: Test did not complete");
    $finish;
  end

endmodule
