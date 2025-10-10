// Testbench for Pipeline Registers
// Tests all four pipeline registers: IF/ID, ID/EX, EX/MEM, MEM/WB
// Validates stall, flush, and normal operation

`timescale 1ns / 1ps

module tb_pipeline_registers;

  // Clock and reset
  reg clk;
  reg reset_n;

  // Test control
  integer test_num;
  integer pass_count;
  integer fail_count;

  //============================================================================
  // Test 1: IF/ID Register
  //============================================================================

  // IF/ID signals
  reg         ifid_stall;
  reg         ifid_flush;
  reg  [31:0] ifid_pc_in;
  reg  [31:0] ifid_instruction_in;
  wire [31:0] ifid_pc_out;
  wire [31:0] ifid_instruction_out;
  wire        ifid_valid_out;

  ifid_register u_ifid (
    .clk            (clk),
    .reset_n        (reset_n),
    .stall          (ifid_stall),
    .flush          (ifid_flush),
    .pc_in          (ifid_pc_in),
    .instruction_in (ifid_instruction_in),
    .pc_out         (ifid_pc_out),
    .instruction_out(ifid_instruction_out),
    .valid_out      (ifid_valid_out)
  );

  //============================================================================
  // Test 2: ID/EX Register
  //============================================================================

  // ID/EX signals
  reg         idex_flush;
  reg  [31:0] idex_pc_in;
  reg  [31:0] idex_rs1_data_in;
  reg  [31:0] idex_rs2_data_in;
  reg  [4:0]  idex_rs1_addr_in;
  reg  [4:0]  idex_rs2_addr_in;
  reg  [4:0]  idex_rd_addr_in;
  reg  [31:0] idex_imm_in;
  reg  [6:0]  idex_opcode_in;
  reg  [2:0]  idex_funct3_in;
  reg  [6:0]  idex_funct7_in;
  reg  [3:0]  idex_alu_control_in;
  reg         idex_alu_src_in;
  reg         idex_branch_in;
  reg         idex_jump_in;
  reg         idex_mem_read_in;
  reg         idex_mem_write_in;
  reg         idex_reg_write_in;
  reg  [1:0]  idex_wb_sel_in;
  reg         idex_valid_in;

  wire [31:0] idex_pc_out;
  wire [31:0] idex_rs1_data_out;
  wire [31:0] idex_rs2_data_out;
  wire [4:0]  idex_rs1_addr_out;
  wire [4:0]  idex_rs2_addr_out;
  wire [4:0]  idex_rd_addr_out;
  wire [31:0] idex_imm_out;
  wire [6:0]  idex_opcode_out;
  wire [2:0]  idex_funct3_out;
  wire [6:0]  idex_funct7_out;
  wire [3:0]  idex_alu_control_out;
  wire        idex_alu_src_out;
  wire        idex_branch_out;
  wire        idex_jump_out;
  wire        idex_mem_read_out;
  wire        idex_mem_write_out;
  wire        idex_reg_write_out;
  wire [1:0]  idex_wb_sel_out;
  wire        idex_valid_out;

  idex_register u_idex (
    .clk              (clk),
    .reset_n          (reset_n),
    .flush            (idex_flush),
    .pc_in            (idex_pc_in),
    .rs1_data_in      (idex_rs1_data_in),
    .rs2_data_in      (idex_rs2_data_in),
    .rs1_addr_in      (idex_rs1_addr_in),
    .rs2_addr_in      (idex_rs2_addr_in),
    .rd_addr_in       (idex_rd_addr_in),
    .imm_in           (idex_imm_in),
    .opcode_in        (idex_opcode_in),
    .funct3_in        (idex_funct3_in),
    .funct7_in        (idex_funct7_in),
    .alu_control_in   (idex_alu_control_in),
    .alu_src_in       (idex_alu_src_in),
    .branch_in        (idex_branch_in),
    .jump_in          (idex_jump_in),
    .mem_read_in      (idex_mem_read_in),
    .mem_write_in     (idex_mem_write_in),
    .reg_write_in     (idex_reg_write_in),
    .wb_sel_in        (idex_wb_sel_in),
    .valid_in         (idex_valid_in),
    .pc_out           (idex_pc_out),
    .rs1_data_out     (idex_rs1_data_out),
    .rs2_data_out     (idex_rs2_data_out),
    .rs1_addr_out     (idex_rs1_addr_out),
    .rs2_addr_out     (idex_rs2_addr_out),
    .rd_addr_out      (idex_rd_addr_out),
    .imm_out          (idex_imm_out),
    .opcode_out       (idex_opcode_out),
    .funct3_out       (idex_funct3_out),
    .funct7_out       (idex_funct7_out),
    .alu_control_out  (idex_alu_control_out),
    .alu_src_out      (idex_alu_src_out),
    .branch_out       (idex_branch_out),
    .jump_out         (idex_jump_out),
    .mem_read_out     (idex_mem_read_out),
    .mem_write_out    (idex_mem_write_out),
    .reg_write_out    (idex_reg_write_out),
    .wb_sel_out       (idex_wb_sel_out),
    .valid_out        (idex_valid_out)
  );

  //============================================================================
  // Test 3: EX/MEM Register
  //============================================================================

  // EX/MEM signals
  reg  [31:0] exmem_alu_result_in;
  reg  [31:0] exmem_mem_write_data_in;
  reg  [4:0]  exmem_rd_addr_in;
  reg  [31:0] exmem_pc_plus_4_in;
  reg  [2:0]  exmem_funct3_in;
  reg         exmem_mem_read_in;
  reg         exmem_mem_write_in;
  reg         exmem_reg_write_in;
  reg  [1:0]  exmem_wb_sel_in;
  reg         exmem_valid_in;

  wire [31:0] exmem_alu_result_out;
  wire [31:0] exmem_mem_write_data_out;
  wire [4:0]  exmem_rd_addr_out;
  wire [31:0] exmem_pc_plus_4_out;
  wire [2:0]  exmem_funct3_out;
  wire        exmem_mem_read_out;
  wire        exmem_mem_write_out;
  wire        exmem_reg_write_out;
  wire [1:0]  exmem_wb_sel_out;
  wire        exmem_valid_out;

  exmem_register u_exmem (
    .clk                (clk),
    .reset_n            (reset_n),
    .alu_result_in      (exmem_alu_result_in),
    .mem_write_data_in  (exmem_mem_write_data_in),
    .rd_addr_in         (exmem_rd_addr_in),
    .pc_plus_4_in       (exmem_pc_plus_4_in),
    .funct3_in          (exmem_funct3_in),
    .mem_read_in        (exmem_mem_read_in),
    .mem_write_in       (exmem_mem_write_in),
    .reg_write_in       (exmem_reg_write_in),
    .wb_sel_in          (exmem_wb_sel_in),
    .valid_in           (exmem_valid_in),
    .alu_result_out     (exmem_alu_result_out),
    .mem_write_data_out (exmem_mem_write_data_out),
    .rd_addr_out        (exmem_rd_addr_out),
    .pc_plus_4_out      (exmem_pc_plus_4_out),
    .funct3_out         (exmem_funct3_out),
    .mem_read_out       (exmem_mem_read_out),
    .mem_write_out      (exmem_mem_write_out),
    .reg_write_out      (exmem_reg_write_out),
    .wb_sel_out         (exmem_wb_sel_out),
    .valid_out          (exmem_valid_out)
  );

  //============================================================================
  // Test 4: MEM/WB Register
  //============================================================================

  // MEM/WB signals
  reg  [31:0] memwb_alu_result_in;
  reg  [31:0] memwb_mem_read_data_in;
  reg  [4:0]  memwb_rd_addr_in;
  reg  [31:0] memwb_pc_plus_4_in;
  reg         memwb_reg_write_in;
  reg  [1:0]  memwb_wb_sel_in;
  reg         memwb_valid_in;

  wire [31:0] memwb_alu_result_out;
  wire [31:0] memwb_mem_read_data_out;
  wire [4:0]  memwb_rd_addr_out;
  wire [31:0] memwb_pc_plus_4_out;
  wire        memwb_reg_write_out;
  wire [1:0]  memwb_wb_sel_out;
  wire        memwb_valid_out;

  memwb_register u_memwb (
    .clk               (clk),
    .reset_n           (reset_n),
    .alu_result_in     (memwb_alu_result_in),
    .mem_read_data_in  (memwb_mem_read_data_in),
    .rd_addr_in        (memwb_rd_addr_in),
    .pc_plus_4_in      (memwb_pc_plus_4_in),
    .reg_write_in      (memwb_reg_write_in),
    .wb_sel_in         (memwb_wb_sel_in),
    .valid_in          (memwb_valid_in),
    .alu_result_out    (memwb_alu_result_out),
    .mem_read_data_out (memwb_mem_read_data_out),
    .rd_addr_out       (memwb_rd_addr_out),
    .pc_plus_4_out     (memwb_pc_plus_4_out),
    .reg_write_out     (memwb_reg_write_out),
    .wb_sel_out        (memwb_wb_sel_out),
    .valid_out         (memwb_valid_out)
  );

  //============================================================================
  // Clock Generation
  //============================================================================

  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 10ns period (100MHz)
  end

  //============================================================================
  // Test Stimulus
  //============================================================================

  initial begin
    // Initialize
    test_num = 0;
    pass_count = 0;
    fail_count = 0;

    // Initialize all inputs
    reset_n = 0;
    ifid_stall = 0;
    ifid_flush = 0;
    ifid_pc_in = 0;
    ifid_instruction_in = 0;

    idex_flush = 0;
    idex_pc_in = 0;
    idex_rs1_data_in = 0;
    idex_rs2_data_in = 0;
    idex_rs1_addr_in = 0;
    idex_rs2_addr_in = 0;
    idex_rd_addr_in = 0;
    idex_imm_in = 0;
    idex_opcode_in = 0;
    idex_funct3_in = 0;
    idex_funct7_in = 0;
    idex_alu_control_in = 0;
    idex_alu_src_in = 0;
    idex_branch_in = 0;
    idex_jump_in = 0;
    idex_mem_read_in = 0;
    idex_mem_write_in = 0;
    idex_reg_write_in = 0;
    idex_wb_sel_in = 0;
    idex_valid_in = 0;

    exmem_alu_result_in = 0;
    exmem_mem_write_data_in = 0;
    exmem_rd_addr_in = 0;
    exmem_pc_plus_4_in = 0;
    exmem_funct3_in = 0;
    exmem_mem_read_in = 0;
    exmem_mem_write_in = 0;
    exmem_reg_write_in = 0;
    exmem_wb_sel_in = 0;
    exmem_valid_in = 0;

    memwb_alu_result_in = 0;
    memwb_mem_read_data_in = 0;
    memwb_rd_addr_in = 0;
    memwb_pc_plus_4_in = 0;
    memwb_reg_write_in = 0;
    memwb_wb_sel_in = 0;
    memwb_valid_in = 0;

    $display("\n=== Pipeline Register Tests ===\n");

    // Reset pulse
    #20 reset_n = 1;
    #10;

    //--------------------------------------------------------------------------
    // Test 1: IF/ID Normal Operation
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("Test %0d: IF/ID normal operation", test_num);
    ifid_pc_in = 32'h00001000;
    ifid_instruction_in = 32'hDEADBEEF;
    #10;
    if (ifid_pc_out == 32'h00001000 && ifid_instruction_out == 32'hDEADBEEF && ifid_valid_out == 1'b1) begin
      $display("  PASS: Data latched correctly");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Expected pc=0x00001000, instr=0xDEADBEEF, valid=1");
      $display("        Got pc=0x%h, instr=0x%h, valid=%b", ifid_pc_out, ifid_instruction_out, ifid_valid_out);
      fail_count = fail_count + 1;
    end

    //--------------------------------------------------------------------------
    // Test 2: IF/ID Stall
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("Test %0d: IF/ID stall (should hold values)", test_num);
    ifid_stall = 1;
    ifid_pc_in = 32'h00002000;
    ifid_instruction_in = 32'hCAFEBABE;
    #10;
    if (ifid_pc_out == 32'h00001000 && ifid_instruction_out == 32'hDEADBEEF) begin
      $display("  PASS: Values held during stall");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Values should not change during stall");
      fail_count = fail_count + 1;
    end
    ifid_stall = 0;
    #10;

    //--------------------------------------------------------------------------
    // Test 3: IF/ID Flush
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("Test %0d: IF/ID flush (insert NOP)", test_num);
    ifid_flush = 1;
    ifid_pc_in = 32'h00003000;
    ifid_instruction_in = 32'h12345678;
    #10;
    if (ifid_instruction_out == 32'h00000013 && ifid_valid_out == 1'b0) begin
      $display("  PASS: NOP inserted (0x00000013), valid=0");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Expected NOP (0x00000013) and valid=0");
      $display("        Got instr=0x%h, valid=%b", ifid_instruction_out, ifid_valid_out);
      fail_count = fail_count + 1;
    end
    ifid_flush = 0;
    #10;

    //--------------------------------------------------------------------------
    // Test 4: ID/EX Normal Operation
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("Test %0d: ID/EX normal operation", test_num);
    idex_pc_in = 32'h00001000;
    idex_rs1_data_in = 32'hAAAAAAAA;
    idex_rs2_data_in = 32'h55555555;
    idex_rs1_addr_in = 5'd5;
    idex_rs2_addr_in = 5'd6;
    idex_rd_addr_in = 5'd7;
    idex_imm_in = 32'h00000100;
    idex_alu_control_in = 4'h1;
    idex_reg_write_in = 1'b1;
    idex_valid_in = 1'b1;
    #10;
    if (idex_rs1_data_out == 32'hAAAAAAAA && idex_rs2_data_out == 32'h55555555 &&
        idex_rd_addr_out == 5'd7 && idex_reg_write_out == 1'b1) begin
      $display("  PASS: ID/EX data latched correctly");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: ID/EX data mismatch");
      fail_count = fail_count + 1;
    end

    //--------------------------------------------------------------------------
    // Test 5: ID/EX Flush
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("Test %0d: ID/EX flush (clear control signals)", test_num);
    idex_flush = 1;
    idex_reg_write_in = 1'b1;
    idex_mem_read_in = 1'b1;
    #10;
    if (idex_reg_write_out == 1'b0 && idex_mem_read_out == 1'b0 &&
        idex_valid_out == 1'b0 && idex_rd_addr_out == 5'd0) begin
      $display("  PASS: Control signals cleared, valid=0");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Control signals should be cleared on flush");
      $display("        reg_write=%b, mem_read=%b, valid=%b, rd=0x%h",
               idex_reg_write_out, idex_mem_read_out, idex_valid_out, idex_rd_addr_out);
      fail_count = fail_count + 1;
    end
    idex_flush = 0;
    #10;

    //--------------------------------------------------------------------------
    // Test 6: EX/MEM Normal Operation
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("Test %0d: EX/MEM normal operation", test_num);
    exmem_alu_result_in = 32'hBEEFCAFE;
    exmem_mem_write_data_in = 32'h11223344;
    exmem_rd_addr_in = 5'd8;
    exmem_reg_write_in = 1'b1;
    exmem_valid_in = 1'b1;
    #10;
    if (exmem_alu_result_out == 32'hBEEFCAFE && exmem_rd_addr_out == 5'd8 &&
        exmem_reg_write_out == 1'b1) begin
      $display("  PASS: EX/MEM data latched correctly");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: EX/MEM data mismatch");
      fail_count = fail_count + 1;
    end

    //--------------------------------------------------------------------------
    // Test 7: MEM/WB Normal Operation
    //--------------------------------------------------------------------------
    test_num = test_num + 1;
    $display("Test %0d: MEM/WB normal operation", test_num);
    memwb_alu_result_in = 32'h87654321;
    memwb_mem_read_data_in = 32'hFEDCBA98;
    memwb_rd_addr_in = 5'd9;
    memwb_reg_write_in = 1'b1;
    memwb_wb_sel_in = 2'b01;
    memwb_valid_in = 1'b1;
    #10;
    if (memwb_alu_result_out == 32'h87654321 && memwb_mem_read_data_out == 32'hFEDCBA98 &&
        memwb_rd_addr_out == 5'd9 && memwb_wb_sel_out == 2'b01) begin
      $display("  PASS: MEM/WB data latched correctly");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: MEM/WB data mismatch");
      fail_count = fail_count + 1;
    end

    //--------------------------------------------------------------------------
    // Test Summary
    //--------------------------------------------------------------------------
    #10;
    $display("\n=== Test Summary ===");
    $display("Total: %0d, Pass: %0d, Fail: %0d", test_num, pass_count, fail_count);

    if (fail_count == 0) begin
      $display("\nALL TESTS PASSED!");
    end else begin
      $display("\nSOME TESTS FAILED!");
    end

    $finish;
  end

  // Timeout
  initial begin
    #1000;
    $display("\nERROR: Test timeout!");
    $finish;
  end

endmodule
