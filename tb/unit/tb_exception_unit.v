// Testbench for Exception Unit
// Tests exception detection logic

`timescale 1ns / 1ps

module tb_exception_unit;

  // IF stage
  reg [31:0] if_pc;
  reg        if_valid;

  // ID stage
  reg        id_illegal_inst;
  reg        id_ecall;
  reg        id_ebreak;
  reg [31:0] id_pc;
  reg [31:0] id_instruction;
  reg        id_valid;

  // MEM stage
  reg [31:0] mem_addr;
  reg        mem_read;
  reg        mem_write;
  reg [2:0]  mem_funct3;
  reg [31:0] mem_pc;
  reg [31:0] mem_instruction;
  reg        mem_valid;

  // Outputs
  wire        exception;
  wire [4:0]  exception_code;
  wire [31:0] exception_pc;
  wire [31:0] exception_val;

  // Test counters
  integer passed = 0;
  integer failed = 0;

  // Exception codes
  localparam CAUSE_INST_ADDR_MISALIGNED  = 5'd0;
  localparam CAUSE_ILLEGAL_INST          = 5'd2;
  localparam CAUSE_BREAKPOINT            = 5'd3;
  localparam CAUSE_LOAD_ADDR_MISALIGNED  = 5'd4;
  localparam CAUSE_STORE_ADDR_MISALIGNED = 5'd6;
  localparam CAUSE_ECALL_FROM_M_MODE     = 5'd11;

  // Instantiate exception unit
  exception_unit uut (
    .if_pc(if_pc),
    .if_valid(if_valid),
    .id_illegal_inst(id_illegal_inst),
    .id_ecall(id_ecall),
    .id_ebreak(id_ebreak),
    .id_pc(id_pc),
    .id_instruction(id_instruction),
    .id_valid(id_valid),
    .mem_addr(mem_addr),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .mem_funct3(mem_funct3),
    .mem_pc(mem_pc),
    .mem_instruction(mem_instruction),
    .mem_valid(mem_valid),
    .exception(exception),
    .exception_code(exception_code),
    .exception_pc(exception_pc),
    .exception_val(exception_val)
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

  task check_val;
    input [31:0] expected;
    input [31:0] actual;
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

  task check_code;
    input [4:0] expected;
    input [4:0] actual;
    input [255:0] test_name;
    begin
      if (expected === actual) begin
        $display("PASS: %s", test_name);
        passed = passed + 1;
      end else begin
        $display("FAIL: %s (expected=%d, actual=%d)", test_name, expected, actual);
        failed = failed + 1;
      end
    end
  endtask

  // Initialize inputs
  task init_inputs;
    begin
      if_pc = 32'h0;
      if_valid = 1'b0;
      id_illegal_inst = 1'b0;
      id_ecall = 1'b0;
      id_ebreak = 1'b0;
      id_pc = 32'h0;
      id_instruction = 32'h0;
      id_valid = 1'b0;
      mem_addr = 32'h0;
      mem_read = 1'b0;
      mem_write = 1'b0;
      mem_funct3 = 3'b0;
      mem_pc = 32'h0;
      mem_instruction = 32'h0;
      mem_valid = 1'b0;
    end
  endtask

  // Main test sequence
  initial begin
    $display("========================================");
    $display("Exception Unit Test");
    $display("========================================");

    init_inputs();

    // ======================================================================
    // Test 1: No exception
    // ======================================================================
    $display("\n--- Test 1: No exception ---");
    #10;
    check(1'b0, exception, "No exception");

    // ======================================================================
    // Test 2: Instruction address misaligned
    // ======================================================================
    $display("\n--- Test 2: Instruction address misaligned ---");
    init_inputs();
    if_pc = 32'h0000_0102;  // Misaligned (not multiple of 4)
    if_valid = 1'b1;
    #10;
    check(1'b1, exception, "Exception detected");
    check_code(CAUSE_INST_ADDR_MISALIGNED, exception_code, "Inst addr misaligned code");
    check_val(32'h0000_0102, exception_pc, "Exception PC");
    check_val(32'h0000_0102, exception_val, "Exception value (bad PC)");

    // ======================================================================
    // Test 3: Illegal instruction
    // ======================================================================
    $display("\n--- Test 3: Illegal instruction ---");
    init_inputs();
    id_illegal_inst = 1'b1;
    id_pc = 32'h0000_0200;
    id_instruction = 32'hBADC_0DE0;
    id_valid = 1'b1;
    #10;
    check(1'b1, exception, "Exception detected");
    check_code(CAUSE_ILLEGAL_INST, exception_code, "Illegal inst code");
    check_val(32'h0000_0200, exception_pc, "Exception PC");
    check_val(32'hBADC_0DE0, exception_val, "Exception value (bad inst)");

    // ======================================================================
    // Test 4: ECALL
    // ======================================================================
    $display("\n--- Test 4: ECALL ---");
    init_inputs();
    id_ecall = 1'b1;
    id_pc = 32'h0000_0300;
    id_valid = 1'b1;
    #10;
    check(1'b1, exception, "Exception detected");
    check_code(CAUSE_ECALL_FROM_M_MODE, exception_code, "ECALL code");
    check_val(32'h0000_0300, exception_pc, "Exception PC");
    check_val(32'h0, exception_val, "Exception value (0)");

    // ======================================================================
    // Test 5: EBREAK
    // ======================================================================
    $display("\n--- Test 5: EBREAK ---");
    init_inputs();
    id_ebreak = 1'b1;
    id_pc = 32'h0000_0400;
    id_valid = 1'b1;
    #10;
    check(1'b1, exception, "Exception detected");
    check_code(CAUSE_BREAKPOINT, exception_code, "EBREAK code");
    check_val(32'h0000_0400, exception_pc, "Exception PC");
    check_val(32'h0000_0400, exception_val, "Exception value (PC)");

    // ======================================================================
    // Test 6: Load halfword misaligned
    // ======================================================================
    $display("\n--- Test 6: Load halfword misaligned ---");
    init_inputs();
    mem_addr = 32'h1000_0001;  // Odd address
    mem_read = 1'b1;
    mem_funct3 = 3'b001;  // LH
    mem_pc = 32'h0000_0500;
    mem_valid = 1'b1;
    #10;
    check(1'b1, exception, "Exception detected");
    check_code(CAUSE_LOAD_ADDR_MISALIGNED, exception_code, "Load misaligned code");
    check_val(32'h0000_0500, exception_pc, "Exception PC");
    check_val(32'h1000_0001, exception_val, "Exception value (bad addr)");

    // ======================================================================
    // Test 7: Load word misaligned
    // ======================================================================
    $display("\n--- Test 7: Load word misaligned ---");
    init_inputs();
    mem_addr = 32'h1000_0002;  // Not 4-byte aligned
    mem_read = 1'b1;
    mem_funct3 = 3'b010;  // LW
    mem_pc = 32'h0000_0600;
    mem_valid = 1'b1;
    #10;
    check(1'b1, exception, "Exception detected");
    check_code(CAUSE_LOAD_ADDR_MISALIGNED, exception_code, "Load word misaligned code");
    check_val(32'h0000_0600, exception_pc, "Exception PC");
    check_val(32'h1000_0002, exception_val, "Exception value (bad addr)");

    // ======================================================================
    // Test 8: Load byte (no exception, always aligned)
    // ======================================================================
    $display("\n--- Test 8: Load byte (no exception) ---");
    init_inputs();
    mem_addr = 32'h1000_0003;  // Any address is fine for byte
    mem_read = 1'b1;
    mem_funct3 = 3'b000;  // LB
    mem_pc = 32'h0000_0700;
    mem_valid = 1'b1;
    #10;
    check(1'b0, exception, "No exception for LB");

    // ======================================================================
    // Test 9: Store halfword misaligned
    // ======================================================================
    $display("\n--- Test 9: Store halfword misaligned ---");
    init_inputs();
    mem_addr = 32'h1000_0007;  // Odd address
    mem_write = 1'b1;
    mem_funct3 = 3'b001;  // SH
    mem_pc = 32'h0000_0800;
    mem_valid = 1'b1;
    #10;
    check(1'b1, exception, "Exception detected");
    check_code(CAUSE_STORE_ADDR_MISALIGNED, exception_code, "Store misaligned code");
    check_val(32'h0000_0800, exception_pc, "Exception PC");
    check_val(32'h1000_0007, exception_val, "Exception value (bad addr)");

    // ======================================================================
    // Test 10: Store word misaligned
    // ======================================================================
    $display("\n--- Test 10: Store word misaligned ---");
    init_inputs();
    mem_addr = 32'h1000_0001;  // Not 4-byte aligned
    mem_write = 1'b1;
    mem_funct3 = 3'b010;  // SW
    mem_pc = 32'h0000_0900;
    mem_valid = 1'b1;
    #10;
    check(1'b1, exception, "Exception detected");
    check_code(CAUSE_STORE_ADDR_MISALIGNED, exception_code, "Store word misaligned code");
    check_val(32'h0000_0900, exception_pc, "Exception PC");
    check_val(32'h1000_0001, exception_val, "Exception value (bad addr)");

    // ======================================================================
    // Test 11: Store byte (no exception)
    // ======================================================================
    $display("\n--- Test 11: Store byte (no exception) ---");
    init_inputs();
    mem_addr = 32'h1000_0009;  // Any address
    mem_write = 1'b1;
    mem_funct3 = 3'b000;  // SB
    mem_pc = 32'h0000_0A00;
    mem_valid = 1'b1;
    #10;
    check(1'b0, exception, "No exception for SB");

    // ======================================================================
    // Test 12: Exception priority - IF over ID
    // ======================================================================
    $display("\n--- Test 12: Exception priority - IF over ID ---");
    init_inputs();
    if_pc = 32'h0000_0102;  // Misaligned
    if_valid = 1'b1;
    id_illegal_inst = 1'b1;  // Also illegal
    id_pc = 32'h0000_0200;
    id_valid = 1'b1;
    #10;
    check(1'b1, exception, "Exception detected");
    check_code(CAUSE_INST_ADDR_MISALIGNED, exception_code, "IF has priority");
    check_val(32'h0000_0102, exception_pc, "IF exception PC");

    // ======================================================================
    // Test 13: Exception priority - EBREAK over ECALL
    // ======================================================================
    $display("\n--- Test 13: Exception priority - EBREAK over ECALL ---");
    init_inputs();
    id_ebreak = 1'b1;
    id_ecall = 1'b1;  // Both set (shouldn't happen in practice)
    id_pc = 32'h0000_0500;
    id_valid = 1'b1;
    #10;
    check(1'b1, exception, "Exception detected");
    check_code(CAUSE_BREAKPOINT, exception_code, "EBREAK has priority");

    // ======================================================================
    // Test 14: Exception priority - ID over MEM
    // ======================================================================
    $display("\n--- Test 14: Exception priority - ID over MEM ---");
    init_inputs();
    id_illegal_inst = 1'b1;
    id_pc = 32'h0000_0600;
    id_valid = 1'b1;
    mem_addr = 32'h1000_0001;  // Misaligned
    mem_write = 1'b1;
    mem_funct3 = 3'b010;  // SW
    mem_pc = 32'h0000_0700;
    mem_valid = 1'b1;
    #10;
    check(1'b1, exception, "Exception detected");
    check_code(CAUSE_ILLEGAL_INST, exception_code, "ID has priority over MEM");
    check_val(32'h0000_0600, exception_pc, "ID exception PC");

    // ======================================================================
    // Test 15: Valid flag - ID stage disabled
    // ======================================================================
    $display("\n--- Test 15: Valid flag - ID stage disabled ---");
    init_inputs();
    id_illegal_inst = 1'b1;
    id_pc = 32'h0000_0800;
    id_valid = 1'b0;  // Not valid
    #10;
    check(1'b0, exception, "No exception when stage not valid");

    // ======================================================================
    // Test 16: Aligned accesses (no exceptions)
    // ======================================================================
    $display("\n--- Test 16: Aligned accesses (no exceptions) ---");
    init_inputs();
    mem_addr = 32'h1000_0004;  // 4-byte aligned
    mem_read = 1'b1;
    mem_funct3 = 3'b010;  // LW
    mem_valid = 1'b1;
    #10;
    check(1'b0, exception, "No exception for aligned LW");

    init_inputs();
    mem_addr = 32'h1000_0002;  // 2-byte aligned
    mem_read = 1'b1;
    mem_funct3 = 3'b001;  // LH
    mem_valid = 1'b1;
    #10;
    check(1'b0, exception, "No exception for aligned LH");

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
