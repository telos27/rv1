// tb_decoder.v - Testbench for instruction decoder
// Tests field extraction and immediate generation
// Author: RV1 Project
// Date: 2025-10-09

`timescale 1ns/1ps

module tb_decoder;

  // Testbench signals
  reg  [31:0] instruction;
  wire [6:0]  opcode;
  wire [4:0]  rd;
  wire [4:0]  rs1;
  wire [4:0]  rs2;
  wire [2:0]  funct3;
  wire [6:0]  funct7;
  wire [31:0] imm_i;
  wire [31:0] imm_s;
  wire [31:0] imm_b;
  wire [31:0] imm_u;
  wire [31:0] imm_j;

  // Error counter
  integer errors = 0;
  integer tests = 0;

  // Instantiate DUT
  decoder DUT (
    .instruction(instruction),
    .opcode(opcode),
    .rd(rd),
    .rs1(rs1),
    .rs2(rs2),
    .funct3(funct3),
    .funct7(funct7),
    .imm_i(imm_i),
    .imm_s(imm_s),
    .imm_b(imm_b),
    .imm_u(imm_u),
    .imm_j(imm_j)
  );

  // Test task for field extraction
  task test_fields;
    input [31:0] instr;
    input [6:0]  exp_opcode;
    input [4:0]  exp_rd;
    input [4:0]  exp_rs1;
    input [4:0]  exp_rs2;
    input [2:0]  exp_funct3;
    input [6:0]  exp_funct7;
    input [80*8:1] test_name;
    begin
      tests = tests + 1;
      instruction = instr;
      #1;

      if (opcode !== exp_opcode || rd !== exp_rd || rs1 !== exp_rs1 ||
          rs2 !== exp_rs2 || funct3 !== exp_funct3 || funct7 !== exp_funct7) begin
        $display("FAIL: %s", test_name);
        $display("  Opcode: exp=0x%02h, got=0x%02h", exp_opcode, opcode);
        $display("  rd:     exp=x%0d, got=x%0d", exp_rd, rd);
        $display("  rs1:    exp=x%0d, got=x%0d", exp_rs1, rs1);
        $display("  rs2:    exp=x%0d, got=x%0d", exp_rs2, rs2);
        $display("  funct3: exp=0x%01h, got=0x%01h", exp_funct3, funct3);
        $display("  funct7: exp=0x%02h, got=0x%02h", exp_funct7, funct7);
        errors = errors + 1;
      end else begin
        $display("PASS: %s", test_name);
      end
    end
  endtask

  // Test task for immediate generation
  task test_immediate;
    input [31:0] instr;
    input [31:0] exp_i;
    input [31:0] exp_s;
    input [31:0] exp_b;
    input [31:0] exp_u;
    input [31:0] exp_j;
    input [80*8:1] test_name;
    begin
      tests = tests + 1;
      instruction = instr;
      #1;

      if (imm_i !== exp_i || imm_s !== exp_s || imm_b !== exp_b ||
          imm_u !== exp_u || imm_j !== exp_j) begin
        $display("FAIL: %s", test_name);
        $display("  imm_i: exp=0x%08h, got=0x%08h", exp_i, imm_i);
        $display("  imm_s: exp=0x%08h, got=0x%08h", exp_s, imm_s);
        $display("  imm_b: exp=0x%08h, got=0x%08h", exp_b, imm_b);
        $display("  imm_u: exp=0x%08h, got=0x%08h", exp_u, imm_u);
        $display("  imm_j: exp=0x%08h, got=0x%08h", exp_j, imm_j);
        errors = errors + 1;
      end else begin
        $display("PASS: %s", test_name);
      end
    end
  endtask

  // Main test sequence
  initial begin
    $display("========================================");
    $display("Decoder Testbench");
    $display("========================================");
    $display("");

    instruction = 32'h0;
    #10;

    // Test 1: R-type instruction (ADD x5, x6, x7)
    // opcode=0110011, rd=5, funct3=000, rs1=6, rs2=7, funct7=0000000
    $display("Test 1: R-type instruction (ADD)...");
    test_fields(
      32'b0000000_00111_00110_000_00101_0110011,
      7'b0110011,  // opcode
      5'd5,        // rd
      5'd6,        // rs1
      5'd7,        // rs2
      3'b000,      // funct3
      7'b0000000,  // funct7
      "R-type ADD"
    );
    $display("");

    // Test 2: I-type instruction (ADDI x10, x11, 42)
    // opcode=0010011, rd=10, funct3=000, rs1=11, imm=42
    $display("Test 2: I-type instruction (ADDI)...");
    test_fields(
      32'b000000101010_01011_000_01010_0010011,
      7'b0010011,  // opcode
      5'd10,       // rd
      5'd11,       // rs1
      5'd10,       // rs2 (don't care for I-type)
      3'b000,      // funct3
      7'b0000001,  // funct7 (upper bits of immediate)
      "I-type ADDI fields"
    );
    // Check I-type immediate
    instruction = 32'b000000101010_01011_000_01010_0010011;
    #1;
    if (imm_i !== 32'd42) begin
      $display("FAIL: I-type immediate (exp=42, got=%0d)", $signed(imm_i));
      errors = errors + 1;
    end else begin
      $display("PASS: I-type immediate = 42");
    end
    tests = tests + 1;
    $display("");

    // Test 3: I-type with negative immediate (ADDI x1, x2, -1)
    $display("Test 3: I-type with negative immediate...");
    instruction = 32'b111111111111_00010_000_00001_0010011;
    #1;
    if (imm_i !== 32'hFFFFFFFF) begin
      $display("FAIL: I-type negative immediate (exp=-1, got=%0d)", $signed(imm_i));
      errors = errors + 1;
    end else begin
      $display("PASS: I-type negative immediate = -1 (0x%08h)", imm_i);
    end
    tests = tests + 1;
    $display("");

    // Test 4: S-type instruction (SW x5, 8(x2))
    // opcode=0100011, funct3=010, rs1=2, rs2=5, imm=8
    $display("Test 4: S-type instruction (SW)...");
    instruction = 32'b0000000_00101_00010_010_01000_0100011;
    #1;
    if (imm_s !== 32'd8) begin
      $display("FAIL: S-type immediate (exp=8, got=%0d)", $signed(imm_s));
      errors = errors + 1;
    end else begin
      $display("PASS: S-type immediate = 8");
    end
    tests = tests + 1;
    $display("");

    // Test 5: S-type with negative offset (SW x10, -4(x15))
    $display("Test 5: S-type with negative offset...");
    instruction = 32'b1111111_01010_01111_010_11100_0100011;
    #1;
    if (imm_s !== 32'hFFFFFFFC) begin  // -4
      $display("FAIL: S-type negative immediate (exp=-4, got=%0d)", $signed(imm_s));
      errors = errors + 1;
    end else begin
      $display("PASS: S-type negative immediate = -4 (0x%08h)", imm_s);
    end
    tests = tests + 1;
    $display("");

    // Test 6: B-type instruction (BEQ x1, x2, 8)
    // Branch offset 8 (aligned to 2 bytes)
    $display("Test 6: B-type instruction (BEQ)...");
    // imm[12|10:5] = 0000000, imm[4:1|11] = 01000
    // For offset 8: bits are [12]=0, [11]=0, [10:5]=000000, [4:1]=0100
    instruction = 32'b0_000000_00010_00001_000_0100_0_1100011;
    #1;
    if (imm_b !== 32'd8) begin
      $display("FAIL: B-type immediate (exp=8, got=%0d)", $signed(imm_b));
      errors = errors + 1;
    end else begin
      $display("PASS: B-type immediate = 8");
    end
    tests = tests + 1;
    $display("");

    // Test 7: B-type with negative offset (BNE x5, x6, -4)
    $display("Test 7: B-type with negative offset...");
    // -4 = 0xFFFFFFFC, bits: [12]=1, [11]=1, [10:5]=111111, [4:1]=1110
    instruction = 32'b1_111111_00110_00101_001_1110_1_1100011;
    #1;
    if (imm_b !== 32'hFFFFFFFC) begin  // -4
      $display("FAIL: B-type negative immediate (exp=-4, got=%0d)", $signed(imm_b));
      errors = errors + 1;
    end else begin
      $display("PASS: B-type negative immediate = -4 (0x%08h)", imm_b);
    end
    tests = tests + 1;
    $display("");

    // Test 8: U-type instruction (LUI x15, 0x12345)
    $display("Test 8: U-type instruction (LUI)...");
    instruction = 32'b00010010001101000101_01111_0110111;
    #1;
    if (imm_u !== 32'h12345000) begin
      $display("FAIL: U-type immediate (exp=0x12345000, got=0x%08h)", imm_u);
      errors = errors + 1;
    end else begin
      $display("PASS: U-type immediate = 0x12345000");
    end
    tests = tests + 1;
    $display("");

    // Test 9: J-type instruction (JAL x1, 16)
    // offset 16: [20]=0, [19:12]=00000000, [11]=0, [10:1]=0000001000
    $display("Test 9: J-type instruction (JAL)...");
    instruction = 32'b0_0000001000_0_00000000_00001_1101111;
    #1;
    if (imm_j !== 32'd16) begin
      $display("FAIL: J-type immediate (exp=16, got=%0d)", $signed(imm_j));
      errors = errors + 1;
    end else begin
      $display("PASS: J-type immediate = 16");
    end
    tests = tests + 1;
    $display("");

    // Test 10: J-type with negative offset
    $display("Test 10: J-type with negative offset...");
    // -8: [20]=1, [19:12]=11111111, [11]=1, [10:1]=1111111100
    instruction = 32'b1_1111111100_1_11111111_00010_1101111;
    #1;
    if (imm_j !== 32'hFFFFFFF8) begin  // -8
      $display("FAIL: J-type negative immediate (exp=-8, got=%0d)", $signed(imm_j));
      errors = errors + 1;
    end else begin
      $display("PASS: J-type negative immediate = -8 (0x%08h)", imm_j);
    end
    tests = tests + 1;
    $display("");

    // Summary
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
    $dumpfile("sim/waves/decoder.vcd");
    $dumpvars(0, tb_decoder);
  end

endmodule
