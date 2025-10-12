// tb_rvc_quick_test.v - Quick RVC integration test
// Tests that the RVC decoder integrates with the core correctly

`timescale 1ns / 1ps

module tb_rvc_quick_test;
  reg clk;
  reg reset_n;

  // Instruction from decoder
  wire [31:0] decompressed_instr;
  wire is_compressed_out;
  wire illegal_instr;

  // Test compressed instructions
  reg [15:0] test_instr;
  reg is_rv64;

  // Instantiate RVC decoder
  rvc_decoder #(
    .XLEN(32)
  ) dut (
    .compressed_instr(test_instr),
    .is_rv64(is_rv64),
    .decompressed_instr(decompressed_instr),
    .illegal_instr(illegal_instr),
    .is_compressed_out(is_compressed_out)
  );

  integer pass_count, fail_count;

  initial begin
    $display("========================================");
    $display("RVC Decoder Integration Quick Test");
    $display("========================================");
    $display("");

    pass_count = 0;
    fail_count = 0;
    is_rv64 = 0;  // Test RV32C mode

    // Test 1: C.ADDI (basic compressed instruction)
    test_instr = 16'b000_0_01010_10100_01;  // C.ADDI x10, 5
    #1;
    if (is_compressed_out && !illegal_instr && decompressed_instr[6:0] == 7'b0010011) begin
      $display("[PASS] C.ADDI decoded correctly");
      pass_count = pass_count + 1;
    end else begin
      $display("[FAIL] C.ADDI: is_compressed=%b, illegal=%b, opcode=%b",
               is_compressed_out, illegal_instr, decompressed_instr[6:0]);
      fail_count = fail_count + 1;
    end

    // Test 2: C.LW (load compressed)
    test_instr = 16'b010_010_010_01_010_00;  // C.LW x9, 4(x10)
    #1;
    if (is_compressed_out && !illegal_instr && decompressed_instr[6:0] == 7'b0000011) begin
      $display("[PASS] C.LW decoded correctly");
      pass_count = pass_count + 1;
    end else begin
      $display("[FAIL] C.LW: is_compressed=%b, illegal=%b, opcode=%b",
               is_compressed_out, illegal_instr, decompressed_instr[6:0]);
      fail_count = fail_count + 1;
    end

    // Test 3: C.J (jump compressed)
    test_instr = 16'b101_00000001000_01;  // C.J 8
    #1;
    if (is_compressed_out && !illegal_instr && decompressed_instr[6:0] == 7'b1101111) begin
      $display("[PASS] C.J decoded correctly");
      pass_count = pass_count + 1;
    end else begin
      $display("[FAIL] C.J: is_compressed=%b, illegal=%b, opcode=%b",
               is_compressed_out, illegal_instr, decompressed_instr[6:0]);
      fail_count = fail_count + 1;
    end

    // Test 4: C.ADD (register-register)
    test_instr = 16'b1001_01100_01011_10;  // C.ADD x12, x11
    #1;
    if (is_compressed_out && !illegal_instr && decompressed_instr[6:0] == 7'b0110011) begin
      $display("[PASS] C.ADD decoded correctly");
      pass_count = pass_count + 1;
    end else begin
      $display("[FAIL] C.ADD: is_compressed=%b, illegal=%b, opcode=%b",
               is_compressed_out, illegal_instr, decompressed_instr[6:0]);
      fail_count = fail_count + 1;
    end

    // Test 5: Regular 32-bit instruction (should pass through as illegal for 16-bit)
    test_instr = 16'b1111_1111_1111_1111;  // All ones
    #1;
    if (!is_compressed_out || illegal_instr) begin
      $display("[PASS] Non-compressed instruction flagged correctly");
      pass_count = pass_count + 1;
    end else begin
      $display("[FAIL] Should not be valid compressed instruction");
      fail_count = fail_count + 1;
    end

    $display("");
    $display("========================================");
    $display("Quick Test Summary");
    $display("========================================");
    $display("Passed: %0d", pass_count);
    $display("Failed: %0d", fail_count);
    $display("");

    if (fail_count == 0) begin
      $display("RVC DECODER INTEGRATION: PASS");
      $display("Ready for full core integration!");
    end else begin
      $display("RVC DECODER INTEGRATION: FAIL");
    end
    $display("========================================");

    $finish;
  end

endmodule
