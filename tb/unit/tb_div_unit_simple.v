// tb_div_unit_simple.v - Simple testbench for division-by-zero bug
// Tests the specific case: DIVU 1/0 should return 0xFFFFFFFF

`timescale 1ns / 1ps

// Define XLEN for div_unit
`define XLEN 32

module tb_div_unit_simple;

  reg clk;
  reg reset_n;
  reg start;
  reg [1:0] div_op;
  reg is_word_op;
  reg [31:0] dividend;
  reg [31:0] divisor;
  wire [31:0] result;
  wire busy;
  wire ready;

  // Instantiate div_unit
  div_unit #(.XLEN(32)) dut (
    .clk(clk),
    .reset_n(reset_n),
    .start(start),
    .div_op(div_op),
    .is_word_op(is_word_op),
    .dividend(dividend),
    .divisor(divisor),
    .result(result),
    .busy(busy),
    .ready(ready)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Test sequence
  initial begin
    $dumpfile("sim/waves/div_unit_simple.vcd");
    $dumpvars(0, tb_div_unit_simple);

    // Initialize
    reset_n = 0;
    start = 0;
    div_op = 2'b01;  // DIVU
    is_word_op = 0;
    dividend = 32'h00000001;
    divisor = 32'h00000000;

    // Reset
    #20;
    reset_n = 1;
    #10;

    $display("=== Test 1: DIVU 1/0 (should return 0xFFFFFFFF) ===");
    $display("Time=%0t: Starting division: dividend=%h, divisor=%h", $time, dividend, divisor);

    // Start division
    start = 1;
    #10;
    start = 0;

    // Wait for completion
    wait(ready);
    #10;

    $display("Time=%0t: Division complete: result=%h (expected: 0xFFFFFFFF)", $time, result);

    if (result == 32'hFFFFFFFF) begin
      $display("PASS: DIVU 1/0 = 0xFFFFFFFF");
    end else begin
      $display("FAIL: DIVU 1/0 = %h (expected 0xFFFFFFFF)", result);
      $display("Difference: %d (0x%h)", 32'hFFFFFFFF - result, 32'hFFFFFFFF - result);
    end

    #20;

    // Test 2: REMU (should return dividend)
    $display("\n=== Test 2: REMU 5/0 (should return 5) ===");
    dividend = 32'h00000005;
    divisor = 32'h00000000;
    div_op = 2'b11;  // REMU

    $display("Time=%0t: Starting remainder: dividend=%h, divisor=%h", $time, dividend, divisor);
    start = 1;
    #10;
    start = 0;

    wait(ready);
    #10;

    $display("Time=%0t: Remainder complete: result=%h (expected: 0x00000005)", $time, result);

    if (result == 32'h00000005) begin
      $display("PASS: REMU 5/0 = 5");
    end else begin
      $display("FAIL: REMU 5/0 = %h (expected 0x00000005)", result);
    end

    #20;

    // Test 3: Normal division (sanity check)
    $display("\n=== Test 3: DIVU 10/2 (should return 5) ===");
    dividend = 32'h0000000A;
    divisor = 32'h00000002;
    div_op = 2'b01;  // DIVU

    $display("Time=%0t: Starting division: dividend=%h, divisor=%h", $time, dividend, divisor);
    start = 1;
    #10;
    start = 0;

    wait(ready);
    #10;

    $display("Time=%0t: Division complete: result=%h (expected: 0x00000005)", $time, result);

    if (result == 32'h00000005) begin
      $display("PASS: DIVU 10/2 = 5");
    end else begin
      $display("FAIL: DIVU 10/2 = %h (expected 0x00000005)", result);
    end

    #20;
    $display("\n=== All tests complete ===");
    $finish;
  end

  // Monitor internal signals
  initial begin
    $monitor("Time=%0t: state=%b, div_by_zero=%b, cycle_count=%d, ready=%b, result=%h",
             $time, dut.state, dut.div_by_zero, dut.cycle_count, ready, result);
  end

  // Timeout
  initial begin
    #10000;
    $display("ERROR: Timeout!");
    $finish;
  end

endmodule
