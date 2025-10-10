// tb_alu.v - Testbench for ALU module
// Tests all ALU operations and flag generation
// Author: RV1 Project
// Date: 2025-10-09

`timescale 1ns/1ps

module tb_alu;

  // Testbench signals
  reg  [31:0] operand_a;
  reg  [31:0] operand_b;
  reg  [3:0]  alu_control;
  wire [31:0] result;
  wire        zero;
  wire        less_than;
  wire        less_than_unsigned;

  // Error counter
  integer errors = 0;
  integer tests = 0;

  // Instantiate DUT
  alu DUT (
    .operand_a(operand_a),
    .operand_b(operand_b),
    .alu_control(alu_control),
    .result(result),
    .zero(zero),
    .less_than(less_than),
    .less_than_unsigned(less_than_unsigned)
  );

  // Test task
  task test_operation;
    input [31:0] a;
    input [31:0] b;
    input [3:0]  ctrl;
    input [31:0] expected;
    input [80*8:1] op_name;
    begin
      tests = tests + 1;
      operand_a = a;
      operand_b = b;
      alu_control = ctrl;
      #1;  // Wait for combinational logic

      if (result !== expected) begin
        $display("FAIL: %s", op_name);
        $display("  A=0x%08h, B=0x%08h, Expected=0x%08h, Got=0x%08h",
                 a, b, expected, result);
        errors = errors + 1;
      end else begin
        $display("PASS: %s (A=0x%08h, B=0x%08h, Result=0x%08h)",
                 op_name, a, b, result);
      end
    end
  endtask

  // Main test sequence
  initial begin
    $display("========================================");
    $display("ALU Testbench");
    $display("========================================");
    $display("");

    // Initialize
    operand_a = 32'h0;
    operand_b = 32'h0;
    alu_control = 4'h0;
    #10;

    // Test ADD (4'b0000)
    $display("Testing ADD operations...");
    test_operation(32'd10, 32'd20, 4'b0000, 32'd30, "ADD: 10 + 20 = 30");
    test_operation(32'd0, 32'd0, 4'b0000, 32'd0, "ADD: 0 + 0 = 0");
    test_operation(32'hFFFFFFFF, 32'd1, 4'b0000, 32'd0, "ADD: -1 + 1 = 0 (overflow)");
    test_operation(32'h80000000, 32'h80000000, 4'b0000, 32'h0, "ADD: overflow test");

    // Test SUB (4'b0001)
    $display("");
    $display("Testing SUB operations...");
    test_operation(32'd30, 32'd20, 4'b0001, 32'd10, "SUB: 30 - 20 = 10");
    test_operation(32'd20, 32'd30, 4'b0001, 32'hFFFFFFF6, "SUB: 20 - 30 = -10");
    test_operation(32'd0, 32'd0, 4'b0001, 32'd0, "SUB: 0 - 0 = 0");

    // Test SLL (4'b0010)
    $display("");
    $display("Testing SLL (Shift Left Logical)...");
    test_operation(32'd1, 32'd0, 4'b0010, 32'd1, "SLL: 1 << 0 = 1");
    test_operation(32'd1, 32'd1, 4'b0010, 32'd2, "SLL: 1 << 1 = 2");
    test_operation(32'd1, 32'd4, 4'b0010, 32'd16, "SLL: 1 << 4 = 16");
    test_operation(32'hAAAAAAAA, 32'd1, 4'b0010, 32'h55555554, "SLL: pattern shift");
    test_operation(32'd1, 32'd31, 4'b0010, 32'h80000000, "SLL: 1 << 31");

    // Test SLT (4'b0011)
    $display("");
    $display("Testing SLT (Set Less Than - Signed)...");
    test_operation(32'd5, 32'd10, 4'b0011, 32'd1, "SLT: 5 < 10 = 1");
    test_operation(32'd10, 32'd5, 4'b0011, 32'd0, "SLT: 10 < 5 = 0");
    test_operation(32'd5, 32'd5, 4'b0011, 32'd0, "SLT: 5 < 5 = 0");
    test_operation(32'hFFFFFFFE, 32'd1, 4'b0011, 32'd1, "SLT: -2 < 1 = 1");
    test_operation(32'd1, 32'hFFFFFFFE, 4'b0011, 32'd0, "SLT: 1 < -2 = 0");

    // Test SLTU (4'b0100)
    $display("");
    $display("Testing SLTU (Set Less Than - Unsigned)...");
    test_operation(32'd5, 32'd10, 4'b0100, 32'd1, "SLTU: 5 < 10 = 1");
    test_operation(32'd10, 32'd5, 4'b0100, 32'd0, "SLTU: 10 < 5 = 0");
    test_operation(32'hFFFFFFFE, 32'd1, 4'b0100, 32'd0, "SLTU: 0xFFFFFFFE < 1 = 0 (unsigned)");
    test_operation(32'd1, 32'hFFFFFFFE, 4'b0100, 32'd1, "SLTU: 1 < 0xFFFFFFFE = 1 (unsigned)");

    // Test XOR (4'b0101)
    $display("");
    $display("Testing XOR operations...");
    test_operation(32'hAAAAAAAA, 32'h55555555, 4'b0101, 32'hFFFFFFFF, "XOR: 0xAAAA... ^ 0x5555... = 0xFFFF...");
    test_operation(32'hFFFFFFFF, 32'hFFFFFFFF, 4'b0101, 32'h0, "XOR: all 1s ^ all 1s = 0");
    test_operation(32'h12345678, 32'h0, 4'b0101, 32'h12345678, "XOR: x ^ 0 = x");

    // Test SRL (4'b0110)
    $display("");
    $display("Testing SRL (Shift Right Logical)...");
    test_operation(32'd16, 32'd4, 4'b0110, 32'd1, "SRL: 16 >> 4 = 1");
    test_operation(32'h80000000, 32'd1, 4'b0110, 32'h40000000, "SRL: 0x80000000 >> 1 (logical)");
    test_operation(32'hFFFFFFFF, 32'd4, 4'b0110, 32'h0FFFFFFF, "SRL: 0xFFFFFFFF >> 4 (zero fill)");

    // Test SRA (4'b0111)
    $display("");
    $display("Testing SRA (Shift Right Arithmetic)...");
    test_operation(32'd16, 32'd4, 4'b0111, 32'd1, "SRA: 16 >>> 4 = 1");
    test_operation(32'h80000000, 32'd1, 4'b0111, 32'hC0000000, "SRA: 0x80000000 >>> 1 (sign extend)");
    test_operation(32'hFFFFFFFF, 32'd4, 4'b0111, 32'hFFFFFFFF, "SRA: 0xFFFFFFFF >>> 4 (sign extend)");

    // Test OR (4'b1000)
    $display("");
    $display("Testing OR operations...");
    test_operation(32'hAAAAAAAA, 32'h55555555, 4'b1000, 32'hFFFFFFFF, "OR: 0xAAAA... | 0x5555... = 0xFFFF...");
    test_operation(32'h12345678, 32'h0, 4'b1000, 32'h12345678, "OR: x | 0 = x");
    test_operation(32'h0, 32'h0, 4'b1000, 32'h0, "OR: 0 | 0 = 0");

    // Test AND (4'b1001)
    $display("");
    $display("Testing AND operations...");
    test_operation(32'hAAAAAAAA, 32'h55555555, 4'b1001, 32'h0, "AND: 0xAAAA... & 0x5555... = 0");
    test_operation(32'hFFFFFFFF, 32'h12345678, 4'b1001, 32'h12345678, "AND: all 1s & x = x");
    test_operation(32'h12345678, 32'h0, 4'b1001, 32'h0, "AND: x & 0 = 0");

    // Test flags
    $display("");
    $display("Testing flag outputs...");
    operand_a = 32'd0;
    operand_b = 32'd0;
    alu_control = 4'b0000;  // ADD to get zero
    #1;
    if (zero !== 1'b1) begin
      $display("FAIL: Zero flag should be 1 for result=0");
      errors = errors + 1;
    end else begin
      $display("PASS: Zero flag = 1 for result=0");
    end
    tests = tests + 1;

    operand_a = 32'd5;
    operand_b = 32'd3;
    alu_control = 4'b0000;  // ADD to get non-zero
    #1;
    if (zero !== 1'b0) begin
      $display("FAIL: Zero flag should be 0 for result!=0");
      errors = errors + 1;
    end else begin
      $display("PASS: Zero flag = 0 for result!=0");
    end
    tests = tests + 1;

    // Test less_than flag
    operand_a = 32'hFFFFFFFE;  // -2 in signed
    operand_b = 32'd5;
    alu_control = 4'b0000;
    #1;
    if (less_than !== 1'b1) begin
      $display("FAIL: less_than flag should be 1 for -2 < 5");
      errors = errors + 1;
    end else begin
      $display("PASS: less_than flag = 1 for -2 < 5");
    end
    tests = tests + 1;

    // Test less_than_unsigned flag
    if (less_than_unsigned !== 1'b0) begin
      $display("FAIL: less_than_unsigned flag should be 0 for 0xFFFFFFFE < 5 (unsigned)");
      errors = errors + 1;
    end else begin
      $display("PASS: less_than_unsigned flag = 0 for 0xFFFFFFFE < 5 (unsigned)");
    end
    tests = tests + 1;

    // Summary
    $display("");
    $display("========================================");
    $display("Test Summary");
    $display("========================================");
    $display("Total tests: %0d", tests);
    $display("Passed: %0d", tests - errors);
    $display("Failed: %0d", errors);

    if (errors == 0) begin
      $display("");
      $display("All tests PASSED!");
      $display("");
    end else begin
      $display("");
      $display("Some tests FAILED!");
      $display("");
    end

    $finish;
  end

  // Dump waveforms
  initial begin
    $dumpfile("sim/waves/alu.vcd");
    $dumpvars(0, tb_alu);
  end

endmodule
