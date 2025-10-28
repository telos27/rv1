// tb_bus_arbiter.v - Testbench for Bus Arbiter
// Tests address decoding and response multiplexing
// Author: RV1 Project
// Date: 2025-10-26

`timescale 1ns/1ps

module tb_bus_arbiter;

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

  // CPU/Master interface
  reg              req_valid;
  reg  [XLEN-1:0]  req_addr;
  reg  [63:0]      req_wdata;
  reg              req_we;
  reg  [2:0]       req_size;
  wire             req_ready;
  wire [63:0]      req_rdata;
  wire             req_error;

  // DMEM interface (simulated)
  wire             dmem_valid;
  wire [XLEN-1:0]  dmem_addr;
  wire [63:0]      dmem_wdata;
  wire             dmem_we;
  wire [2:0]       dmem_size;
  reg              dmem_ready;
  reg  [63:0]      dmem_rdata;

  // CLINT interface (simulated)
  wire             clint_valid;
  wire [15:0]      clint_addr;
  wire [63:0]      clint_wdata;
  wire             clint_we;
  wire [2:0]       clint_size;
  reg              clint_ready;
  reg  [63:0]      clint_rdata;

  // UART interface (simulated)
  wire             uart_valid;
  wire [2:0]       uart_addr;
  wire [7:0]       uart_wdata;
  wire             uart_we;
  reg              uart_ready;
  reg  [7:0]       uart_rdata;

  //==========================================================================
  // DUT Instantiation
  //==========================================================================
  bus_arbiter #(
    .XLEN(XLEN)
  ) dut (
    .req_valid(req_valid),
    .req_addr(req_addr),
    .req_wdata(req_wdata),
    .req_we(req_we),
    .req_size(req_size),
    .req_ready(req_ready),
    .req_rdata(req_rdata),
    .req_error(req_error),

    .dmem_valid(dmem_valid),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_we(dmem_we),
    .dmem_size(dmem_size),
    .dmem_ready(dmem_ready),
    .dmem_rdata(dmem_rdata),

    .clint_valid(clint_valid),
    .clint_addr(clint_addr),
    .clint_wdata(clint_wdata),
    .clint_we(clint_we),
    .clint_size(clint_size),
    .clint_ready(clint_ready),
    .clint_rdata(clint_rdata),

    .uart_valid(uart_valid),
    .uart_addr(uart_addr),
    .uart_wdata(uart_wdata),
    .uart_we(uart_we),
    .uart_ready(uart_ready),
    .uart_rdata(uart_rdata)
  );

  //==========================================================================
  // Clock Generation
  //==========================================================================
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  //==========================================================================
  // Simulated Slave Responses
  //==========================================================================
  // DMEM: Always ready, return incremented value
  always @(*) begin
    dmem_ready = dmem_valid;
    dmem_rdata = {dmem_addr[31:0], dmem_addr[31:0]} + 64'h1111111111111111;
  end

  // CLINT: Always ready, return specific patterns
  always @(*) begin
    clint_ready = clint_valid;
    case (clint_addr[15:3])
      13'h17FF: clint_rdata = 64'hDEADBEEF_CAFEBABE;  // MTIME
      default:  clint_rdata = 64'h0000_0000_0000_1000;  // MTIMECMP
    endcase
  end

  // UART: Always ready, return register-specific values
  always @(*) begin
    uart_ready = uart_valid;
    case (uart_addr)
      3'h0: uart_rdata = 8'h41;  // RBR: 'A'
      3'h5: uart_rdata = 8'h60;  // LSR: THRE=1, TEMT=1
      3'h7: uart_rdata = 8'hAA;  // SCR: test pattern
      default: uart_rdata = 8'h00;
    endcase
  end

  //==========================================================================
  // Test Variables
  //==========================================================================
  integer test_count;
  integer pass_count;
  integer fail_count;

  //==========================================================================
  // Test Tasks
  //==========================================================================
  task bus_write;
    input [XLEN-1:0] addr;
    input [63:0] wdata;
    input [2:0] size;
    begin
      @(posedge clk);
      #1;
      req_valid = 1'b1;
      req_addr  = addr;
      req_wdata = wdata;
      req_we    = 1'b1;
      req_size  = size;
      #1;  // Wait for combinational logic to settle
      @(posedge clk);
      #1;
      req_valid = 1'b0;
      req_addr  = 32'h0;
      req_wdata = 64'h0;
      req_we    = 1'b0;
      req_size  = 3'h0;
    end
  endtask

  task bus_read;
    input  [XLEN-1:0] addr;
    input  [2:0] size;
    output [63:0] rdata;
    begin
      @(posedge clk);
      #1;
      req_valid = 1'b1;
      req_addr  = addr;
      req_wdata = 64'h0;
      req_we    = 1'b0;
      req_size  = size;
      @(posedge clk);
      #1;
      rdata = req_rdata;
      req_valid = 1'b0;
      req_addr  = 32'h0;
      req_size  = 3'h0;
    end
  endtask

  task check_error;
    input [XLEN-1:0] addr;
    begin
      @(posedge clk);
      #1;
      req_valid = 1'b1;
      req_addr  = addr;
      req_wdata = 64'h0;
      req_we    = 1'b0;
      req_size  = 3'b010;
      @(posedge clk);
      #1;
      req_valid = 1'b0;
      req_addr  = 32'h0;
    end
  endtask

  //==========================================================================
  // Test Stimulus
  //==========================================================================
  initial begin
    // Initialize
    clk = 0;
    reset_n = 0;
    req_valid = 0;
    req_addr = 0;
    req_wdata = 0;
    req_we = 0;
    req_size = 0;
    test_count = 0;
    pass_count = 0;
    fail_count = 0;

    // Reset
    #(CLK_PERIOD*2);
    reset_n = 1;
    #(CLK_PERIOD*2);

    $display("=== Bus Arbiter Test ===");
    $display("");

    //========================================================================
    // Test 1: DMEM Access (0x8000_0000 - 0x8000_FFFF)
    //========================================================================
    begin
      reg [63:0] rdata;
      $display("Test 1: DMEM Access");
      test_count = test_count + 1;

      // Write - check routing during the write
      @(posedge clk);
      #1;
      req_valid = 1'b1;
      req_addr  = 32'h8000_0000;
      req_wdata = 64'hDEADBEEF_CAFEBABE;
      req_we    = 1'b1;
      req_size  = 3'b011;
      #1;  // Wait for combinational logic
      if (!dmem_valid || dmem_addr != 32'h8000_0000) begin
        $display("  FAIL: DMEM write routing (valid=%b, addr=0x%h)", dmem_valid, dmem_addr);
        fail_count = fail_count + 1;
      end else begin
        $display("  PASS: DMEM write routing");
        pass_count = pass_count + 1;
      end
      @(posedge clk);
      #1;
      req_valid = 1'b0;
      req_addr  = 32'h0;
      req_wdata = 64'h0;
      req_we    = 1'b0;
      req_size  = 3'h0;

      // Read
      bus_read(32'h8000_1234, 3'b010, rdata);
      if (!req_ready || req_rdata == 64'h0) begin
        $display("  FAIL: DMEM read response (got 0x%016h)", req_rdata);
        fail_count = fail_count + 1;
      end else begin
        $display("  PASS: DMEM read response (0x%016h)", req_rdata);
        pass_count = pass_count + 1;
      end
    end

    //========================================================================
    // Test 2: CLINT MTIME Access (0x0200_BFF8)
    //========================================================================
    begin
      reg [63:0] rdata;
      $display("");
      $display("Test 2: CLINT MTIME Access");
      test_count = test_count + 1;

      // Read MTIME
      bus_read(32'h0200_BFF8, 3'b011, rdata);
      if (!req_ready || req_rdata != 64'hDEADBEEF_CAFEBABE) begin
        $display("  FAIL: CLINT MTIME read (expected 0x%016h, got 0x%016h)",
                 64'hDEADBEEF_CAFEBABE, req_rdata);
        fail_count = fail_count + 1;
      end else begin
        $display("  PASS: CLINT MTIME read (0x%016h)", req_rdata);
        pass_count = pass_count + 1;
      end
    end

    //========================================================================
    // Test 3: CLINT MTIMECMP Access (0x0200_4000)
    //========================================================================
    begin
      reg [63:0] rdata;
      $display("");
      $display("Test 3: CLINT MTIMECMP Access");
      test_count = test_count + 1;

      // Write MTIMECMP
      bus_write(32'h0200_4000, 64'h0000_0000_0000_5000, 3'b011);
      if (!clint_valid || clint_addr != 16'h4000) begin
        $display("  FAIL: CLINT MTIMECMP write routing");
        fail_count = fail_count + 1;
      end else begin
        $display("  PASS: CLINT MTIMECMP write routing");
        pass_count = pass_count + 1;
      end

      // Read MTIMECMP
      bus_read(32'h0200_4000, 3'b011, rdata);
      if (!req_ready || req_rdata != 64'h0000_0000_0000_1000) begin
        $display("  FAIL: CLINT MTIMECMP read (expected 0x1000, got 0x%016h)", req_rdata);
        fail_count = fail_count + 1;
      end else begin
        $display("  PASS: CLINT MTIMECMP read (0x%016h)", req_rdata);
        pass_count = pass_count + 1;
      end
    end

    //========================================================================
    // Test 4: UART THR Write (0x1000_0000)
    //========================================================================
    begin
      $display("");
      $display("Test 4: UART THR Write");
      test_count = test_count + 1;

      // Write 'A'
      bus_write(32'h1000_0000, 64'h0000_0000_0000_0041, 3'b000);
      if (!uart_valid || uart_addr != 3'h0 || uart_wdata != 8'h41) begin
        $display("  FAIL: UART THR write routing (addr=%h, data=%h)", uart_addr, uart_wdata);
        fail_count = fail_count + 1;
      end else begin
        $display("  PASS: UART THR write routing");
        pass_count = pass_count + 1;
      end
    end

    //========================================================================
    // Test 5: UART LSR Read (0x1000_0005)
    //========================================================================
    begin
      reg [63:0] rdata;
      $display("");
      $display("Test 5: UART LSR Read");
      test_count = test_count + 1;

      // Read LSR
      bus_read(32'h1000_0005, 3'b000, rdata);
      if (!req_ready || req_rdata != 64'h0000_0000_0000_0060) begin
        $display("  FAIL: UART LSR read (expected 0x60, got 0x%016h)", req_rdata);
        fail_count = fail_count + 1;
      end else begin
        $display("  PASS: UART LSR read (0x%016h)", req_rdata);
        pass_count = pass_count + 1;
      end
    end

    //========================================================================
    // Test 6: Invalid Address (0x5000_0000)
    //========================================================================
    begin
      $display("");
      $display("Test 6: Invalid Address Error");
      test_count = test_count + 1;

      check_error(32'h5000_0000);
      if (!req_error) begin
        $display("  FAIL: Bus error not asserted");
        fail_count = fail_count + 1;
      end else begin
        $display("  PASS: Bus error asserted for invalid address");
        pass_count = pass_count + 1;
      end
    end

    //========================================================================
    // Summary
    //========================================================================
    $display("");
    $display("=== Test Summary ===");
    $display("Total:  %0d tests", test_count);
    $display("Passed: %0d tests", pass_count);
    $display("Failed: %0d tests", fail_count);
    $display("");

    if (fail_count == 0) begin
      $display("✓ All tests PASSED");
    end else begin
      $display("✗ Some tests FAILED");
    end

    #(CLK_PERIOD*5);
    $finish;
  end

  //==========================================================================
  // Timeout
  //==========================================================================
  initial begin
    #(CLK_PERIOD*1000);
    $display("ERROR: Simulation timeout");
    $finish;
  end

endmodule
