// Testbench for Decoder and Control Unit with CSR support
// Tests CSR instruction decoding and control signal generation

`timescale 1ns / 1ps

module tb_decoder_control_csr;

  // Decoder inputs
  reg [31:0] instruction;

  // Decoder outputs
  wire [6:0]  opcode;
  wire [4:0]  rd, rs1, rs2;
  wire [2:0]  funct3;
  wire [6:0]  funct7;
  wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  wire [11:0] csr_addr;
  wire [4:0]  csr_uimm;
  wire        is_csr, is_ecall, is_ebreak, is_mret;

  // Control outputs
  wire        reg_write, mem_read, mem_write;
  wire        branch, jump;
  wire [3:0]  alu_control;
  wire        alu_src;
  wire [1:0]  wb_sel;
  wire [2:0]  imm_sel;
  wire        csr_we, csr_src;
  wire        illegal_inst;

  // Test counters
  integer passed = 0;
  integer failed = 0;

  // Instantiate decoder
  decoder uut_decoder (
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
    .imm_j(imm_j),
    .csr_addr(csr_addr),
    .csr_uimm(csr_uimm),
    .is_csr(is_csr),
    .is_ecall(is_ecall),
    .is_ebreak(is_ebreak),
    .is_mret(is_mret)
  );

  // Instantiate control unit
  control uut_control (
    .opcode(opcode),
    .funct3(funct3),
    .funct7(funct7),
    .is_csr(is_csr),
    .is_ecall(is_ecall),
    .is_ebreak(is_ebreak),
    .is_mret(is_mret),
    .reg_write(reg_write),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .branch(branch),
    .jump(jump),
    .alu_control(alu_control),
    .alu_src(alu_src),
    .wb_sel(wb_sel),
    .imm_sel(imm_sel),
    .csr_we(csr_we),
    .csr_src(csr_src),
    .illegal_inst(illegal_inst)
  );

  // Test task
  task check;
    input expected;
    input actual;
    input [255:0] test_name;
    begin
      if (expected === actual) begin
        $display("PASS: %s", test_name);
        passed = passed + 1;
      end else begin
        $display("FAIL: %s (expected=%b, actual=%b)", test_name, expected, actual);
        failed = failed + 1;
      end
    end
  endtask

  task check_addr;
    input [11:0] expected;
    input [11:0] actual;
    input [255:0] test_name;
    begin
      if (expected === actual) begin
        $display("PASS: %s", test_name);
        passed = passed + 1;
      end else begin
        $display("FAIL: %s (expected=%h, actual=%h)", test_name, expected, actual);
        failed = failed + 1;
      end
    end
  endtask

  // Main test sequence
  initial begin
    $display("========================================");
    $display("Decoder & Control CSR Test");
    $display("========================================");

    // ======================================================================
    // Test 1: CSRRW (CSR Read/Write)
    // ======================================================================
    $display("\n--- Test 1: CSRRW ---");
    // CSRRW x1, mstatus, x2
    // opcode=SYSTEM(1110011), funct3=001, rs1=x2, rd=x1, csr=0x300
    instruction = 32'b0011000_00000_00010_001_00001_1110011;
    #10;
    check(1'b1, is_csr, "CSRRW is_csr");
    check(1'b0, is_ecall, "CSRRW is_ecall");
    check(1'b0, is_ebreak, "CSRRW is_ebreak");
    check(1'b0, is_mret, "CSRRW is_mret");
    check_addr(12'h300, csr_addr, "CSRRW csr_addr");
    check(1'b1, reg_write, "CSRRW reg_write");
    check(2'b11, wb_sel, "CSRRW wb_sel (CSR)");
    check(1'b1, csr_we, "CSRRW csr_we");
    check(1'b0, csr_src, "CSRRW csr_src (register)");
    check(1'b0, illegal_inst, "CSRRW not illegal");

    // ======================================================================
    // Test 2: CSRRS (CSR Read/Set)
    // ======================================================================
    $display("\n--- Test 2: CSRRS ---");
    // CSRRS x3, mie, x4
    // opcode=SYSTEM, funct3=010, rs1=x4, rd=x3, csr=0x304
    instruction = 32'b0011000_00100_00100_010_00011_1110011;
    #10;
    check(1'b1, is_csr, "CSRRS is_csr");
    check_addr(12'h304, csr_addr, "CSRRS csr_addr");
    check(1'b1, csr_we, "CSRRS csr_we");
    check(1'b0, csr_src, "CSRRS csr_src");

    // ======================================================================
    // Test 3: CSRRC (CSR Read/Clear)
    // ======================================================================
    $display("\n--- Test 3: CSRRC ---");
    // CSRRC x5, mtvec, x6
    // opcode=SYSTEM, funct3=011, rs1=x6, rd=x5, csr=0x305
    instruction = 32'b0011000_00101_00110_011_00101_1110011;
    #10;
    check(1'b1, is_csr, "CSRRC is_csr");
    check_addr(12'h305, csr_addr, "CSRRC csr_addr");
    check(3'b011, funct3, "CSRRC funct3");

    // ======================================================================
    // Test 4: CSRRWI (CSR Read/Write Immediate)
    // ======================================================================
    $display("\n--- Test 4: CSRRWI ---");
    // CSRRWI x7, mscratch, 15
    // opcode=SYSTEM, funct3=101, uimm=15, rd=x7, csr=0x340
    instruction = 32'b0011010_00000_01111_101_00111_1110011;
    #10;
    check(1'b1, is_csr, "CSRRWI is_csr");
    check_addr(12'h340, csr_addr, "CSRRWI csr_addr");
    check(5'd15, csr_uimm, "CSRRWI csr_uimm");
    check(1'b1, csr_we, "CSRRWI csr_we");
    check(1'b1, csr_src, "CSRRWI csr_src (immediate)");

    // ======================================================================
    // Test 5: CSRRSI (CSR Read/Set Immediate)
    // ======================================================================
    $display("\n--- Test 5: CSRRSI ---");
    // CSRRSI x8, mepc, 10
    // opcode=SYSTEM, funct3=110, uimm=10, rd=x8, csr=0x341
    instruction = 32'b0011010_00001_01010_110_01000_1110011;
    #10;
    check(1'b1, is_csr, "CSRRSI is_csr");
    check_addr(12'h341, csr_addr, "CSRRSI csr_addr");
    check(5'd10, csr_uimm, "CSRRSI csr_uimm");
    check(1'b1, csr_src, "CSRRSI csr_src (immediate)");

    // ======================================================================
    // Test 6: CSRRCI (CSR Read/Clear Immediate)
    // ======================================================================
    $display("\n--- Test 6: CSRRCI ---");
    // CSRRCI x9, mcause, 5
    // opcode=SYSTEM, funct3=111, uimm=5, rd=x9, csr=0x342
    instruction = 32'b0011010_00010_00101_111_01001_1110011;
    #10;
    check(1'b1, is_csr, "CSRRCI is_csr");
    check_addr(12'h342, csr_addr, "CSRRCI csr_addr");
    check(5'd5, csr_uimm, "CSRRCI csr_uimm");
    check(1'b1, csr_src, "CSRRCI csr_src (immediate)");

    // ======================================================================
    // Test 7: ECALL
    // ======================================================================
    $display("\n--- Test 7: ECALL ---");
    // ECALL: 0000000_00000_00000_000_00000_1110011
    instruction = 32'b0000000_00000_00000_000_00000_1110011;
    #10;
    check(1'b0, is_csr, "ECALL is_csr");
    check(1'b1, is_ecall, "ECALL is_ecall");
    check(1'b0, is_ebreak, "ECALL is_ebreak");
    check(1'b0, is_mret, "ECALL is_mret");
    check(1'b0, reg_write, "ECALL reg_write");
    check(1'b0, csr_we, "ECALL csr_we");
    check(1'b0, illegal_inst, "ECALL not illegal");

    // ======================================================================
    // Test 8: EBREAK
    // ======================================================================
    $display("\n--- Test 8: EBREAK ---");
    // EBREAK: 0000000_00001_00000_000_00000_1110011
    instruction = 32'b0000000_00001_00000_000_00000_1110011;
    #10;
    check(1'b0, is_csr, "EBREAK is_csr");
    check(1'b0, is_ecall, "EBREAK is_ecall");
    check(1'b1, is_ebreak, "EBREAK is_ebreak");
    check(1'b0, is_mret, "EBREAK is_mret");
    check(1'b0, reg_write, "EBREAK reg_write");
    check(1'b0, illegal_inst, "EBREAK not illegal");

    // ======================================================================
    // Test 9: MRET
    // ======================================================================
    $display("\n--- Test 9: MRET ---");
    // MRET: 0011000_00010_00000_000_00000_1110011
    instruction = 32'b0011000_00010_00000_000_00000_1110011;
    #10;
    check(1'b0, is_csr, "MRET is_csr");
    check(1'b0, is_ecall, "MRET is_ecall");
    check(1'b0, is_ebreak, "MRET is_ebreak");
    check(1'b1, is_mret, "MRET is_mret");
    check(1'b1, jump, "MRET jump");
    check(1'b0, csr_we, "MRET csr_we");
    check(1'b0, illegal_inst, "MRET not illegal");

    // ======================================================================
    // Test 10: Illegal SYSTEM instruction
    // ======================================================================
    $display("\n--- Test 10: Illegal SYSTEM instruction ---");
    // Invalid SYSTEM: funct3=000, but not ECALL/EBREAK/MRET
    instruction = 32'b0000000_00011_00000_000_00000_1110011;
    #10;
    check(1'b0, is_csr, "Illegal is_csr");
    check(1'b0, is_ecall, "Illegal is_ecall");
    check(1'b0, is_ebreak, "Illegal is_ebreak");
    check(1'b0, is_mret, "Illegal is_mret");
    check(1'b1, illegal_inst, "Illegal instruction detected");

    // ======================================================================
    // Test 11: Unknown opcode
    // ======================================================================
    $display("\n--- Test 11: Unknown opcode ---");
    instruction = 32'b0000000_00000_00000_000_00000_0001010;  // Invalid opcode
    #10;
    check(1'b1, illegal_inst, "Unknown opcode illegal");

    // ======================================================================
    // Test 12: Regular instruction (ADD) should not trigger CSR
    // ======================================================================
    $display("\n--- Test 12: Regular instruction (ADD) ---");
    // ADD x1, x2, x3: 0000000_00011_00010_000_00001_0110011
    instruction = 32'b0000000_00011_00010_000_00001_0110011;
    #10;
    check(1'b0, is_csr, "ADD is_csr");
    check(1'b0, is_ecall, "ADD is_ecall");
    check(1'b0, is_ebreak, "ADD is_ebreak");
    check(1'b0, is_mret, "ADD is_mret");
    check(1'b1, reg_write, "ADD reg_write");
    check(2'b00, wb_sel, "ADD wb_sel (ALU)");
    check(1'b0, illegal_inst, "ADD not illegal");

    // ======================================================================
    // Summary
    // ======================================================================
    $display("\n========================================");
    $display("Test Summary");
    $display("========================================");
    $display("PASSED: %0d", passed);
    $display("FAILED: %0d", failed);
    if (failed == 0) begin
      $display("ALL TESTS PASSED!");
    end else begin
      $display("SOME TESTS FAILED!");
    end
    $display("========================================");

    $finish;
  end

endmodule
