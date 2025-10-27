// tb_simple_bus.v - Testbench for Simple Bus Interconnect
// Tests address decoding, request routing, and response handling
// Author: RV1 Project
// Date: 2025-10-27

`timescale 1ns / 1ps

module tb_simple_bus;

  //==========================================================================
  // Parameters
  //==========================================================================
  parameter XLEN = 32;
  parameter CLK_PERIOD = 10;  // 10ns = 100MHz

  //==========================================================================
  // DUT Signals
  //==========================================================================
  reg              clk;
  reg              reset_n;

  // Master (CPU) interface
  reg              master_req_valid;
  reg  [XLEN-1:0]  master_req_addr;
  reg  [63:0]      master_req_wdata;
  reg              master_req_we;
  reg  [2:0]       master_req_size;
  wire             master_req_ready;
  wire [63:0]      master_req_rdata;

  // CLINT interface
  wire             clint_req_valid;
  wire [15:0]      clint_req_addr;
  wire [63:0]      clint_req_wdata;
  wire             clint_req_we;
  wire [2:0]       clint_req_size;
  reg              clint_req_ready;
  reg  [63:0]      clint_req_rdata;

  // UART interface
  wire             uart_req_valid;
  wire [2:0]       uart_req_addr;
  wire [7:0]       uart_req_wdata;
  wire             uart_req_we;
  reg              uart_req_ready;
  reg  [7:0]       uart_req_rdata;

  // DMEM interface
  wire             dmem_req_valid;
  wire [XLEN-1:0]  dmem_req_addr;
  wire [63:0]      dmem_req_wdata;
  wire             dmem_req_we;
  wire [2:0]       dmem_req_size;
  reg              dmem_req_ready;
  reg  [63:0]      dmem_req_rdata;

  // PLIC interface
  wire             plic_req_valid;
  wire [XLEN-1:0]  plic_req_addr;
  wire [31:0]      plic_req_wdata;
  wire             plic_req_we;
  reg              plic_req_ready;
  reg  [31:0]      plic_req_rdata;

  //==========================================================================
  // Test Status
  //==========================================================================
  integer test_count;
  integer pass_count;
  integer fail_count;

  //==========================================================================
  // DUT Instantiation
  //==========================================================================
  simple_bus #(
    .XLEN(XLEN)
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    // Master
    .master_req_valid(master_req_valid),
    .master_req_addr(master_req_addr),
    .master_req_wdata(master_req_wdata),
    .master_req_we(master_req_we),
    .master_req_size(master_req_size),
    .master_req_ready(master_req_ready),
    .master_req_rdata(master_req_rdata),
    // CLINT
    .clint_req_valid(clint_req_valid),
    .clint_req_addr(clint_req_addr),
    .clint_req_wdata(clint_req_wdata),
    .clint_req_we(clint_req_we),
    .clint_req_size(clint_req_size),
    .clint_req_ready(clint_req_ready),
    .clint_req_rdata(clint_req_rdata),
    // UART
    .uart_req_valid(uart_req_valid),
    .uart_req_addr(uart_req_addr),
    .uart_req_wdata(uart_req_wdata),
    .uart_req_we(uart_req_we),
    .uart_req_ready(uart_req_ready),
    .uart_req_rdata(uart_req_rdata),
    // DMEM
    .dmem_req_valid(dmem_req_valid),
    .dmem_req_addr(dmem_req_addr),
    .dmem_req_wdata(dmem_req_wdata),
    .dmem_req_we(dmem_req_we),
    .dmem_req_size(dmem_req_size),
    .dmem_req_ready(dmem_req_ready),
    .dmem_req_rdata(dmem_req_rdata),
    // PLIC
    .plic_req_valid(plic_req_valid),
    .plic_req_addr(plic_req_addr),
    .plic_req_wdata(plic_req_wdata),
    .plic_req_we(plic_req_we),
    .plic_req_ready(plic_req_ready),
    .plic_req_rdata(plic_req_rdata)
  );

  //==========================================================================
  // Clock Generation
  //==========================================================================
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  //==========================================================================
  // Slave Response Logic (Mock Peripherals)
  //==========================================================================

  // CLINT mock response (single cycle, echo lower 32 bits of write data)
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      clint_req_ready <= 1'b0;
      clint_req_rdata <= 64'h0;
    end else begin
      clint_req_ready <= clint_req_valid;
      if (clint_req_valid && !clint_req_we) begin
        clint_req_rdata <= {32'h0, clint_req_addr, 16'hC117};  // Pattern with address
      end
    end
  end

  // UART mock response
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      uart_req_ready <= 1'b0;
      uart_req_rdata <= 8'h0;
    end else begin
      uart_req_ready <= uart_req_valid;
      if (uart_req_valid && !uart_req_we) begin
        uart_req_rdata <= {5'h0, uart_req_addr};  // Echo address in lower 3 bits
      end
    end
  end

  // DMEM mock response
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      dmem_req_ready <= 1'b0;
      dmem_req_rdata <= 64'h0;
    end else begin
      dmem_req_ready <= dmem_req_valid;
      if (dmem_req_valid && !dmem_req_we) begin
        dmem_req_rdata <= {32'hDEADBEEF, dmem_req_addr[31:0]};  // Pattern with address
      end
    end
  end

  // PLIC mock response
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      plic_req_ready <= 1'b0;
      plic_req_rdata <= 32'h0;
    end else begin
      plic_req_ready <= plic_req_valid;
      if (plic_req_valid && !plic_req_we) begin
        plic_req_rdata <= {8'hA5, plic_req_addr[23:0]};  // Pattern with address
      end
    end
  end

  //==========================================================================
  // Test Tasks
  //==========================================================================

  task master_write;
    input [XLEN-1:0] addr;
    input [63:0]     data;
    input [2:0]      size;
    begin
      @(posedge clk);
      master_req_valid <= 1'b1;
      master_req_addr  <= addr;
      master_req_wdata <= data;
      master_req_we    <= 1'b1;
      master_req_size  <= size;
      @(posedge clk);
      while (!master_req_ready) @(posedge clk);
      master_req_valid <= 1'b0;
      $display("[WRITE] addr=0x%08h data=0x%016h size=%0d", addr, data, size);
    end
  endtask

  task master_read;
    input  [XLEN-1:0] addr;
    input  [2:0]      size;
    output [63:0]     data;
    begin
      @(posedge clk);
      master_req_valid <= 1'b1;
      master_req_addr  <= addr;
      master_req_we    <= 1'b0;
      master_req_size  <= size;
      @(posedge clk);
      while (!master_req_ready) @(posedge clk);
      data = master_req_rdata;
      master_req_valid <= 1'b0;
      $display("[READ]  addr=0x%08h data=0x%016h size=%0d", addr, data, size);
    end
  endtask

  task check_result;
    input [63:0] expected;
    input [63:0] actual;
    begin
      test_count = test_count + 1;
      if (expected == actual) begin
        $display("  [PASS] Test %0d", test_count);
        pass_count = pass_count + 1;
      end else begin
        $display("  [FAIL] Test %0d - Expected: 0x%016h, Got: 0x%016h", test_count, expected, actual);
        fail_count = fail_count + 1;
      end
    end
  endtask

  //==========================================================================
  // Test Sequence
  //==========================================================================
  reg [63:0] read_data;

  initial begin
    // Initialize
    test_count = 0;
    pass_count = 0;
    fail_count = 0;

    master_req_valid = 1'b0;
    master_req_addr = 0;
    master_req_wdata = 0;
    master_req_we = 1'b0;
    master_req_size = 0;

    reset_n = 1'b0;
    repeat(5) @(posedge clk);
    reset_n = 1'b1;
    repeat(2) @(posedge clk);

    $display("\n========================================");
    $display("  Simple Bus Interconnect Test");
    $display("========================================\n");

    //=======================================================================
    // Test 1: CLINT Address Decode
    //=======================================================================
    $display("Test 1: CLINT Address Decode");
    master_read(32'h0200_0000, 3'h3, read_data);  // MSIP
    master_read(32'h0200_4000, 3'h3, read_data);  // MTIMECMP
    master_read(32'h0200_BFF8, 3'h3, read_data);  // MTIME
    $display("  Checking CLINT selected");
    check_result(1'b1, clint_req_valid);

    //=======================================================================
    // Test 2: UART Address Decode
    //=======================================================================
    $display("\nTest 2: UART Address Decode");
    master_read(32'h1000_0000, 3'h0, read_data);  // RBR
    master_read(32'h1000_0005, 3'h0, read_data);  // LSR
    master_read(32'h1000_0007, 3'h0, read_data);  // SCR
    $display("  Checking UART address echo");
    check_result(64'h7, read_data & 64'hFF);

    //=======================================================================
    // Test 3: PLIC Address Decode
    //=======================================================================
    $display("\nTest 3: PLIC Address Decode");
    master_read(32'h0C00_0004, 3'h2, read_data);  // Priority[1]
    master_read(32'h0C00_2000, 3'h2, read_data);  // Enable M-mode
    master_read(32'h0C20_0000, 3'h2, read_data);  // Threshold M-mode
    $display("  Checking PLIC selected");
    check_result(1'b1, plic_req_valid);

    //=======================================================================
    // Test 4: DMEM Address Decode
    //=======================================================================
    $display("\nTest 4: DMEM Address Decode");
    master_read(32'h8000_0000, 3'h3, read_data);  // DMEM base
    master_read(32'h8000_1234, 3'h3, read_data);  // DMEM offset
    $display("  Checking DMEM response pattern");
    check_result(64'hDEADBEEF80001234, read_data);

    //=======================================================================
    // Test 5: Unmapped Address (should return 0)
    //=======================================================================
    $display("\nTest 5: Unmapped Address Handling");
    master_read(32'h5000_0000, 3'h3, read_data);  // Unmapped
    $display("  Checking unmapped returns 0");
    check_result(64'h0, read_data);
    $display("  Checking unmapped returns ready");
    check_result(1'b1, master_req_ready);

    //=======================================================================
    // Test 6: Write Operations
    //=======================================================================
    $display("\nTest 6: Write Operations");
    master_write(32'h0200_0000, 64'h1, 3'h2);  // CLINT MSIP
    $display("  Checking CLINT write valid");
    check_result(1'b1, clint_req_valid);
    $display("  Checking CLINT write enable");
    check_result(1'b1, clint_req_we);

    master_write(32'h1000_0000, 64'h41, 3'h0);  // UART THR
    $display("  Checking UART write valid");
    check_result(1'b1, uart_req_valid);
    $display("  Checking UART write data");
    check_result(8'h41, {56'h0, uart_req_wdata});

    //=======================================================================
    // Test Summary
    //=======================================================================
    repeat(5) @(posedge clk);

    $display("\n========================================");
    $display("  Test Summary");
    $display("========================================");
    $display("  Total:  %0d", test_count);
    $display("  Passed: %0d", pass_count);
    $display("  Failed: %0d", fail_count);
    $display("========================================\n");

    if (fail_count == 0) begin
      $display("✓ All tests PASSED!");
      $finish(0);
    end else begin
      $display("✗ Some tests FAILED!");
      $finish(1);
    end
  end

  //==========================================================================
  // Timeout Watchdog
  //==========================================================================
  initial begin
    #10000;
    $display("\n[ERROR] Testbench timeout!");
    $finish(1);
  end

endmodule
