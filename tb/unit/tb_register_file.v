// tb_register_file.v - Testbench for register file
// Tests read/write operations and x0 hardwiring
// Author: RV1 Project
// Date: 2025-10-09

`timescale 1ns/1ps

module tb_register_file;

  // Clock parameters
  parameter CLK_PERIOD = 10;

  // Testbench signals
  reg         clk;
  reg         reset_n;
  reg  [4:0]  rs1_addr;
  reg  [4:0]  rs2_addr;
  reg  [4:0]  rd_addr;
  reg  [31:0] rd_data;
  reg         rd_wen;
  wire [31:0] rs1_data;
  wire [31:0] rs2_data;

  // Error counter
  integer errors = 0;
  integer tests = 0;

  // Instantiate DUT
  register_file DUT (
    .clk(clk),
    .reset_n(reset_n),
    .rs1_addr(rs1_addr),
    .rs2_addr(rs2_addr),
    .rd_addr(rd_addr),
    .rd_data(rd_data),
    .rd_wen(rd_wen),
    .rs1_data(rs1_data),
    .rs2_data(rs2_data)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // Test task
  task write_register;
    input [4:0] addr;
    input [31:0] data;
    begin
      @(posedge clk);
      rd_addr = addr;
      rd_data = data;
      rd_wen = 1'b1;
      @(posedge clk);
      rd_wen = 1'b0;
      @(posedge clk);
    end
  endtask

  task read_and_check;
    input [4:0] addr;
    input [31:0] expected;
    input [80*8:1] test_name;
    begin
      tests = tests + 1;
      rs1_addr = addr;
      #1;  // Small delay for combinational logic

      if (rs1_data !== expected) begin
        $display("FAIL: %s", test_name);
        $display("  Addr=x%0d, Expected=0x%08h, Got=0x%08h",
                 addr, expected, rs1_data);
        errors = errors + 1;
      end else begin
        $display("PASS: %s (x%0d = 0x%08h)", test_name, addr, rs1_data);
      end
    end
  endtask

  // Main test sequence
  initial begin
    $display("========================================");
    $display("Register File Testbench");
    $display("========================================");
    $display("");

    // Initialize signals
    reset_n = 0;
    rs1_addr = 5'h0;
    rs2_addr = 5'h0;
    rd_addr = 5'h0;
    rd_data = 32'h0;
    rd_wen = 1'b0;

    // Reset
    $display("Applying reset...");
    #(CLK_PERIOD*2);
    reset_n = 1;
    #(CLK_PERIOD*2);
    $display("Reset released");
    $display("");

    // Test 1: Check that all registers are zero after reset
    $display("Test 1: Checking reset state...");
    for (integer i = 0; i < 32; i = i + 1) begin
      read_and_check(i[4:0], 32'h0, "Reset check");
    end
    $display("");

    // Test 2: Write and read back from different registers
    $display("Test 2: Write and read operations...");
    write_register(5'd1, 32'hDEADBEEF);
    read_and_check(5'd1, 32'hDEADBEEF, "Write/Read x1");

    write_register(5'd5, 32'h12345678);
    read_and_check(5'd5, 32'h12345678, "Write/Read x5");

    write_register(5'd31, 32'hAAAAAAAA);
    read_and_check(5'd31, 32'hAAAAAAAA, "Write/Read x31");

    $display("");

    // Test 3: Verify x0 is always zero
    $display("Test 3: x0 hardwired to zero...");

    // Try to write to x0
    write_register(5'd0, 32'hFFFFFFFF);
    read_and_check(5'd0, 32'h00000000, "x0 stays zero after write");

    // Write again
    write_register(5'd0, 32'h12345678);
    read_and_check(5'd0, 32'h00000000, "x0 still zero");

    $display("");

    // Test 4: Simultaneous read from two ports
    $display("Test 4: Dual-port read...");
    write_register(5'd10, 32'h11111111);
    write_register(5'd20, 32'h22222222);

    tests = tests + 1;
    rs1_addr = 5'd10;
    rs2_addr = 5'd20;
    #1;

    if (rs1_data !== 32'h11111111 || rs2_data !== 32'h22222222) begin
      $display("FAIL: Dual-port read");
      $display("  rs1_data=0x%08h (expected 0x11111111)", rs1_data);
      $display("  rs2_data=0x%08h (expected 0x22222222)", rs2_data);
      errors = errors + 1;
    end else begin
      $display("PASS: Dual-port read (x10=0x%08h, x20=0x%08h)", rs1_data, rs2_data);
    end
    $display("");

    // Test 5: Overwrite existing values
    $display("Test 5: Overwrite operations...");
    write_register(5'd15, 32'hFFFFFFFF);
    read_and_check(5'd15, 32'hFFFFFFFF, "Initial write x15");

    write_register(5'd15, 32'h00000000);
    read_and_check(5'd15, 32'h00000000, "Overwrite x15");

    write_register(5'd15, 32'h55AA55AA);
    read_and_check(5'd15, 32'h55AA55AA, "Overwrite x15 again");

    $display("");

    // Test 6: Write enable control
    $display("Test 6: Write enable control...");
    write_register(5'd7, 32'h77777777);
    read_and_check(5'd7, 32'h77777777, "Write with wen=1");

    // Try to write with wen=0
    @(posedge clk);
    rd_addr = 5'd7;
    rd_data = 32'h88888888;
    rd_wen = 1'b0;  // Write disabled
    @(posedge clk);
    @(posedge clk);

    read_and_check(5'd7, 32'h77777777, "No write with wen=0");

    $display("");

    // Test 7: Test all registers
    $display("Test 7: Testing all 32 registers...");
    for (integer i = 1; i < 32; i = i + 1) begin
      write_register(i[4:0], i[31:0]);
    end

    for (integer i = 1; i < 32; i = i + 1) begin
      read_and_check(i[4:0], i[31:0], "All registers test");
    end

    // Verify x0 is still zero
    read_and_check(5'd0, 32'h0, "x0 still zero after all writes");

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
    $dumpfile("sim/waves/register_file.vcd");
    $dumpvars(0, tb_register_file);
  end

  // Timeout
  initial begin
    #(CLK_PERIOD * 10000);
    $display("ERROR: Testbench timeout!");
    $finish;
  end

endmodule
