// tb_rvc_decoder.v - Testbench for RVC Decoder
// Tests the compressed instruction decompressor
// Author: RV1 Project
// Date: 2025-10-11

module tb_rvc_decoder;

  // Parameters
  parameter XLEN = 32;
  parameter CLK_PERIOD = 10;

  // Signals
  reg  [15:0] compressed_instr;
  reg         is_rv64;
  wire [31:0] decompressed_instr;
  wire        illegal_instr;
  wire        is_compressed_out;

  // Counters
  integer tests_run = 0;
  integer tests_passed = 0;
  integer tests_failed = 0;

  // DUT instantiation
  rvc_decoder #(
    .XLEN(XLEN)
  ) dut (
    .compressed_instr(compressed_instr),
    .is_rv64(is_rv64),
    .decompressed_instr(decompressed_instr),
    .illegal_instr(illegal_instr),
    .is_compressed_out(is_compressed_out)
  );

  // Test task
  task test_instruction;
    input [15:0] c_instr;
    input [31:0] expected;
    input        rv64;
    input        should_be_illegal;
    input [200*8-1:0] name;
    begin
      compressed_instr = c_instr;
      is_rv64 = rv64;
      #1;  // Wait for combinational logic

      tests_run = tests_run + 1;

      if (should_be_illegal) begin
        if (illegal_instr) begin
          $display("[PASS] %0s: Correctly flagged as illegal", name);
          tests_passed = tests_passed + 1;
        end else begin
          $display("[FAIL] %0s: Should be illegal but wasn't", name);
          $display("       Got: 0x%08h", decompressed_instr);
          tests_failed = tests_failed + 1;
        end
      end else begin
        if (illegal_instr) begin
          $display("[FAIL] %0s: Incorrectly flagged as illegal", name);
          tests_failed = tests_failed + 1;
        end else if (decompressed_instr !== expected) begin
          $display("[FAIL] %0s", name);
          $display("       Expected: 0x%08h", expected);
          $display("       Got:      0x%08h", decompressed_instr);
          tests_failed = tests_failed + 1;
        end else begin
          $display("[PASS] %0s", name);
          tests_passed = tests_passed + 1;
        end
      end
    end
  endtask

  // Main test sequence
  initial begin
    $display("========================================");
    $display("RVC Decoder Testbench");
    $display("========================================");

    is_rv64 = 1'b0;  // Default to RV32

    // Test illegal instruction (quadrant 3)
    $display("\n--- Testing Illegal Instructions ---");
    test_instruction(16'hFFFF, 32'h00000000, 0, 1, "Illegal (Q3 - not compressed)");

    // Test Quadrant 0 Instructions
    $display("\n--- Testing Quadrant 0 ---");

    // C.ADDI4SPN: addi rd', x2, 256 (rd'=x8+2=x10)
    // Format: 000 nzuimm[5:4|9:6|2|3] rd' 00
    // nzuimm=256: nzuimm[9:2]=01000000, so [5:4]=00,[9:6]=0100,[3:2]=00
    // rd'=010 (binary) -> x8+2 = x10
    // Encoded: inst[12:11]=00, inst[10:7]=0100, inst[6:5]=00, inst[4:2]=010
    test_instruction(16'b000_00010000_010_00, 32'h10010513, 0, 0, "C.ADDI4SPN x10, 256");

    // C.LW: lw x9, 4(x10)
    // Format: 010 offset[5:3] rs1' offset[2|6] rd' 00
    // offset=4 (0b100): offset[6]=0, offset[5:3]=000, offset[2]=1
    // inst[12:10]=000, inst[6]=1, inst[5]=0
    test_instruction(16'b010_000_010_10_001_00, 32'h00452483, 0, 0, "C.LW x9, 4(x10)");

    // C.SW: sw x9, 8(x10)
    // Format: 110 offset[5:3] rs1' offset[2|6] rs2' 00
    // offset=8 (0b1000): offset[6]=0, offset[5:3]=001, offset[2]=0
    // inst[12:10]=001, inst[6]=0, inst[5]=0
    test_instruction(16'b110_001_010_00_001_00, 32'h00952423, 0, 0, "C.SW x9, 8(x10)");

    // Test Quadrant 1 Instructions
    $display("\n--- Testing Quadrant 1 ---");

    // C.NOP
    test_instruction(16'b000_0_00000_00000_01, 32'h00000013, 0, 0, "C.NOP");

    // C.ADDI: addi x10, x10, 5
    // Format: 000 imm[5] rd/rs1 imm[4:0] 01
    test_instruction(16'b000_0_01010_00101_01, 32'h00550513, 0, 0, "C.ADDI x10, 5");

    // C.LI: addi x11, x0, 10
    test_instruction(16'b010_0_01011_01010_01, 32'h00a00593, 0, 0, "C.LI x11, 10");

    // C.LUI: lui x12, 0x1
    // Format: 011 imm[17] rd imm[16:12] 01
    test_instruction(16'b011_0_01100_00001_01, 32'h00001637, 0, 0, "C.LUI x12, 0x1");

    // C.ADDI16SP: addi x2, x2, 16
    // Format: 011 nzimm[9] 00010 nzimm[4|6|8:7|5] 01
    // nzimm=16: nzimm[9]=0, [8:7]=00, [6]=0, [5]=0, [4]=1
    // inst[6:2] = nzimm[4|6|8:7|5] = 1,0,00,0 (MSB first)
    // In binary bits[6:2]: bit[6]=1, bit[5]=0, bit[4:3]=00, bit[2]=0 -> 10000
    test_instruction(16'b011_0_00010_10000_01, 32'h01010113, 0, 0, "C.ADDI16SP 16");

    // C.SRLI: srli x8, x8, 2
    // Format: 100 imm[5] 00 rd'/rs1' imm[4:0] 01
    test_instruction(16'b100_0_00_000_00010_01, 32'h00245413, 0, 0, "C.SRLI x8, 2");

    // C.SRAI: srai x9, x9, 1
    test_instruction(16'b100_0_01_001_00001_01, 32'h4014d493, 0, 0, "C.SRAI x9, 1");

    // C.ANDI: andi x10, x10, 15
    test_instruction(16'b100_0_10_010_01111_01, 32'h00f57513, 0, 0, "C.ANDI x10, 15");

    // C.SUB: sub x8, x8, x9
    // Format: 100_0_11_rs1'_00_rs2'_01
    test_instruction(16'b100_0_11_000_00_001_01, 32'h40940433, 0, 0, "C.SUB x8, x9");

    // C.XOR: xor x8, x8, x9
    test_instruction(16'b100_0_11_000_01_001_01, 32'h00944433, 0, 0, "C.XOR x8, x9");

    // C.OR: or x8, x8, x9
    test_instruction(16'b100_0_11_000_10_001_01, 32'h00946433, 0, 0, "C.OR x8, x9");

    // C.AND: and x8, x8, x9
    test_instruction(16'b100_0_11_000_11_001_01, 32'h00947433, 0, 0, "C.AND x8, x9");

    // C.J: jal x0, offset
    // Format: 101 imm[11|4|9:8|10|6|7|3:1|5] 01
    // offset = 8: offset[3]=1, all others 0
    // Scrambled: imm[11|4|9:8|10|6|7|3:1|5] = 0|0|00|0|0|0|100|0
    test_instruction(16'b101_00000001000_01, 32'h0080006f, 0, 0, "C.J 8");

    // C.BEQZ: beq x8, x0, offset
    // Format: 110 offset[8|4:3] rs1' offset[7:6|2:1|5] 01
    // offset=4: offset[8|4:3]=0|00, offset[7:6|2:1|5]=00|10|0
    test_instruction(16'b110_000_000_00100_01, 32'h00040263, 0, 0, "C.BEQZ x8, 4");

    // C.BNEZ: bne x9, x0, offset
    // Format: 111 offset[8|4:3] rs1' offset[7:6|2:1|5] 01
    // offset=4: offset[8|4:3]=0|00, offset[7:6|2:1|5]=00|10|0
    test_instruction(16'b111_000_001_00100_01, 32'h00049263, 0, 0, "C.BNEZ x9, 4");

    // Test Quadrant 2 Instructions
    $display("\n--- Testing Quadrant 2 ---");

    // C.SLLI: slli x10, x10, 3
    test_instruction(16'b000_0_01010_00011_10, 32'h00351513, 0, 0, "C.SLLI x10, 3");

    // C.LWSP: lw x11, 8(x2)
    // Format: 010 imm[5] rd imm[4:2|7:6] 10
    test_instruction(16'b010_0_01011_01000_10, 32'h00812583, 0, 0, "C.LWSP x11, 8(sp)");

    // C.JR: jalr x0, 0(x10)
    // Format: 100 0 rs1!=0 00000 10
    test_instruction(16'b100_0_01010_00000_10, 32'h00050067, 0, 0, "C.JR x10");

    // C.MV: add x11, x0, x10
    // Format: 100 0 rd!=0 rs2!=0 10
    test_instruction(16'b100_0_01011_01010_10, 32'h00050593, 0, 0, "C.MV x11, x10");

    // C.EBREAK
    // Format: 100 1 00000 00000 10
    test_instruction(16'b100_1_00000_00000_10, 32'h00100073, 0, 0, "C.EBREAK");

    // C.JALR: jalr x1, 0(x10)
    // Format: 100 1 rs1!=0 00000 10
    test_instruction(16'b100_1_01010_00000_10, 32'h000500e7, 0, 0, "C.JALR x10");

    // C.ADD: add x12, x12, x11
    // Format: 100 1 rd/rs1!=0 rs2!=0 10
    test_instruction(16'b100_1_01100_01011_10, 32'h00b60633, 0, 0, "C.ADD x12, x11");

    // C.SWSP: sw x10, 12(x2)
    // Format: 110 offset[5:2|7:6] rs2 10
    test_instruction(16'b110_001100_01010_10, 32'h00a12623, 0, 0, "C.SWSP x10, 12(sp)");

    // Test RV64C-specific instructions
    $display("\n--- Testing RV64C Instructions ---");
    is_rv64 = 1'b1;

    // C.LD: ld x9, 8(x10)
    // Format: 011 imm[5:3] rs1' imm[7:6] rd' 00
    test_instruction(16'b011_001_010_00_001_00, 32'h00853483, 1, 0, "C.LD x9, 8(x10)");

    // C.SD: sd x9, 16(x10)
    // Format: 111 imm[5:3] rs1' imm[7:6] rs2' 00
    test_instruction(16'b111_010_010_00_001_00, 32'h00953823, 1, 0, "C.SD x9, 16(x10)");

    // C.ADDIW: addiw x11, x11, 5
    // Format: 001 imm[5] rd/rs1 imm[4:0] 01
    test_instruction(16'b001_0_01011_00101_01, 32'h0055859b, 1, 0, "C.ADDIW x11, 5");

    // C.SUBW: subw x8, x8, x9
    test_instruction(16'b100_1_11_000_00_001_01, 32'h4094043b, 1, 0, "C.SUBW x8, x9");

    // C.ADDW: addw x8, x8, x9
    test_instruction(16'b100_1_11_000_01_001_01, 32'h0094043b, 1, 0, "C.ADDW x8, x9");

    // C.LDSP: ld x12, 16(x2)
    // Format: 011 imm[5] rd imm[4:3|8:6] 10
    test_instruction(16'b011_0_01100_10000_10, 32'h01013603, 1, 0, "C.LDSP x12, 16(sp)");

    // C.SDSP: sd x11, 24(x2)
    // Format: 111 offset[5:3|8:6] rs2 10
    test_instruction(16'b111_011000_01011_10, 32'h00b13c23, 1, 0, "C.SDSP x11, 24(sp)");

    // Final results
    $display("\n========================================");
    $display("Test Results:");
    $display("  Tests Run:    %0d", tests_run);
    $display("  Tests Passed: %0d", tests_passed);
    $display("  Tests Failed: %0d", tests_failed);
    $display("========================================");

    if (tests_failed == 0) begin
      $display("ALL TESTS PASSED!");
    end else begin
      $display("SOME TESTS FAILED!");
    end

    $finish;
  end

endmodule
