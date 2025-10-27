// tb_uart.v - Testbench for 16550-Compatible UART
// Tests register access, FIFO operation, TX/RX data flow, interrupts
// Author: RV1 Project
// Date: 2025-10-26

`timescale 1ns / 1ps

module tb_uart;

  //===========================================================================
  // Parameters
  //===========================================================================
  parameter CLK_PERIOD = 10;  // 10ns = 100MHz
  parameter FIFO_DEPTH = 16;

  //===========================================================================
  // Signals
  //===========================================================================
  reg        clk;
  reg        reset_n;

  // Memory interface
  reg        req_valid;
  reg  [2:0] req_addr;
  reg  [7:0] req_wdata;
  reg        req_we;
  wire       req_ready;
  wire [7:0] req_rdata;

  // Serial interface
  wire       tx_valid;
  wire [7:0] tx_data;
  reg        tx_ready;

  reg        rx_valid;
  reg  [7:0] rx_data;
  wire       rx_ready;

  // Interrupt
  wire       irq_o;

  // Test control
  integer test_num;
  integer errors;
  integer i;

  //===========================================================================
  // DUT Instantiation
  //===========================================================================
  uart_16550 #(
    .BASE_ADDR(32'h1000_0000),
    .FIFO_DEPTH(FIFO_DEPTH)
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    .req_valid(req_valid),
    .req_addr(req_addr),
    .req_wdata(req_wdata),
    .req_we(req_we),
    .req_ready(req_ready),
    .req_rdata(req_rdata),
    .tx_valid(tx_valid),
    .tx_data(tx_data),
    .tx_ready(tx_ready),
    .rx_valid(rx_valid),
    .rx_data(rx_data),
    .rx_ready(rx_ready),
    .irq_o(irq_o)
  );

  //===========================================================================
  // Clock Generation
  //===========================================================================
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  //===========================================================================
  // Test Tasks
  //===========================================================================

  // Write to UART register
  task write_uart;
    input [2:0] addr;
    input [7:0] data;
    begin
      @(posedge clk);
      #1;  // Small delay to avoid race
      req_valid = 1;
      req_addr  = addr;
      req_wdata = data;
      req_we    = 1;
      @(posedge clk);
      while (!req_ready) @(posedge clk);
      req_valid = 0;
      req_we    = 0;
      @(posedge clk);
    end
  endtask

  // Read from UART register
  task read_uart;
    input  [2:0] addr;
    output [7:0] data;
    begin
      @(posedge clk);
      #1;  // Small delay to avoid race
      req_valid = 1;
      req_addr  = addr;
      req_we    = 0;
      @(posedge clk);
      while (!req_ready) @(posedge clk);
      data = req_rdata;
      req_valid = 0;
      @(posedge clk);
    end
  endtask

  // Check condition and report error if false
  task check;
    input condition;
    input [255:0] message;
    begin
      if (!condition) begin
        $display("ERROR [Test %0d]: %s at time %t", test_num, message, $time);
        errors = errors + 1;
      end
    end
  endtask

  // Inject RX data (simulate serial input)
  task inject_rx;
    input [7:0] data;
    begin
      while (!rx_ready) @(posedge clk);  // Wait for FIFO space
      #1;  // Small delay after clock edge
      rx_valid = 1;
      rx_data = data;
      @(posedge clk);  // Hold for one full clock cycle
      #1;
      rx_valid = 0;
      @(posedge clk);
    end
  endtask

  // Wait for TX data (simulate serial output consumer)
  task consume_tx;
    output [7:0] data;
    begin
      while (!tx_valid) @(posedge clk);  // Wait for TX data valid
      data = tx_data;                     // Capture data
      @(posedge clk);
      #1;
      tx_ready = 1;                       // Signal ready to accept
      @(posedge clk);
      while (tx_valid) @(posedge clk);    // Wait for UART to clear valid
      tx_ready = 0;                       // Deassert ready
      @(posedge clk);
    end
  endtask

  //===========================================================================
  // Register Addresses
  //===========================================================================
  localparam REG_RBR_THR = 3'h0;
  localparam REG_IER     = 3'h1;
  localparam REG_IIR_FCR = 3'h2;
  localparam REG_LCR     = 3'h3;
  localparam REG_MCR     = 3'h4;
  localparam REG_LSR     = 3'h5;
  localparam REG_MSR     = 3'h6;
  localparam REG_SCR     = 3'h7;

  //===========================================================================
  // Test Stimulus
  //===========================================================================
  initial begin
    // Initialize
    clk = 0;
    reset_n = 0;
    req_valid = 0;
    req_addr = 0;
    req_wdata = 0;
    req_we = 0;
    tx_ready = 0;  // TX consumer starts not ready
    rx_valid = 0;
    rx_data = 0;
    test_num = 0;
    errors = 0;

    // Waveform dump
    $dumpfile("waves/tb_uart.vcd");
    $dumpvars(0, tb_uart);

    $display("========================================");
    $display("UART 16550 Testbench Starting");
    $display("========================================");

    // Reset
    #(CLK_PERIOD * 5);
    reset_n = 1;
    #(CLK_PERIOD * 2);

    //=======================================================================
    // Test 1: Register Reset Values
    //=======================================================================
    test_num = 1;
    $display("\n[Test %0d] Checking register reset values...", test_num);
    begin
      reg [7:0] rdata;

      read_uart(REG_IER, rdata);
      check(rdata == 8'h00, "IER should reset to 0x00");

      read_uart(REG_LCR, rdata);
      check(rdata == 8'h03, "LCR should reset to 0x03 (8N1)");

      read_uart(REG_MCR, rdata);
      check(rdata == 8'h00, "MCR should reset to 0x00");

      read_uart(REG_LSR, rdata);
      check(rdata[5] == 1'b1, "LSR[5] THRE should be 1 (TX empty)");
      check(rdata[6] == 1'b1, "LSR[6] TEMT should be 1 (TX empty)");
      check(rdata[0] == 1'b0, "LSR[0] DR should be 0 (no RX data)");

      if (errors == 0) $display("  PASSED");
    end

    //=======================================================================
    // Test 2: Scratch Register Read/Write
    //=======================================================================
    test_num = 2;
    $display("\n[Test %0d] Testing scratch register...", test_num);
    begin
      reg [7:0] rdata;

      write_uart(REG_SCR, 8'hA5);
      read_uart(REG_SCR, rdata);
      check(rdata == 8'hA5, "SCR should read back 0xA5");

      write_uart(REG_SCR, 8'h5A);
      read_uart(REG_SCR, rdata);
      check(rdata == 8'h5A, "SCR should read back 0x5A");

      if (errors == 0) $display("  PASSED");
    end

    //=======================================================================
    // Test 3: TX Single Byte
    //=======================================================================
    test_num = 3;
    $display("\n[Test %0d] Testing TX single byte...", test_num);
    begin
      reg [7:0] rdata, tx_byte;

      // Write character 'A' to THR
      write_uart(REG_RBR_THR, 8'h41);  // 'A'

      // Wait for it to appear on TX interface
      consume_tx(tx_byte);
      check(tx_byte == 8'h41, "TX data should be 'A' (0x41)");

      // Check LSR - TX should be empty again
      read_uart(REG_LSR, rdata);
      check(rdata[5] == 1'b1, "LSR[5] THRE should be 1 after TX");
      check(rdata[6] == 1'b1, "LSR[6] TEMT should be 1 after TX");

      if (errors == 0) $display("  PASSED");
    end

    //=======================================================================
    // Test 4: RX Single Byte
    //=======================================================================
    test_num = 4;
    $display("\n[Test %0d] Testing RX single byte...", test_num);
    begin
      reg [7:0] rdata, lsr;

      // Inject character 'B' from RX interface
      inject_rx(8'h42);  // 'B'

      // Check LSR - data should be ready
      read_uart(REG_LSR, lsr);
      check(lsr[0] == 1'b1, "LSR[0] DR should be 1 (RX data available)");

      // Read from RBR
      read_uart(REG_RBR_THR, rdata);
      check(rdata == 8'h42, "RBR should read 'B' (0x42)");

      // Check LSR - data should be gone
      read_uart(REG_LSR, lsr);
      check(lsr[0] == 1'b0, "LSR[0] DR should be 0 after reading");

      if (errors == 0) $display("  PASSED");
    end

    //=======================================================================
    // Test 5: TX FIFO (Multiple Bytes)
    //=======================================================================
    test_num = 5;
    $display("\n[Test %0d] Testing TX FIFO (8 bytes)...", test_num);
    begin
      reg [7:0] tx_byte;

      // Write string "HELLO" to TX FIFO
      write_uart(REG_RBR_THR, 8'h48);  // 'H'
      write_uart(REG_RBR_THR, 8'h45);  // 'E'
      write_uart(REG_RBR_THR, 8'h4C);  // 'L'
      write_uart(REG_RBR_THR, 8'h4C);  // 'L'
      write_uart(REG_RBR_THR, 8'h4F);  // 'O'

      // Consume TX bytes
      consume_tx(tx_byte);
      check(tx_byte == 8'h48, "TX byte 1 should be 'H'");
      consume_tx(tx_byte);
      check(tx_byte == 8'h45, "TX byte 2 should be 'E'");
      consume_tx(tx_byte);
      check(tx_byte == 8'h4C, "TX byte 3 should be 'L'");
      consume_tx(tx_byte);
      check(tx_byte == 8'h4C, "TX byte 4 should be 'L'");
      consume_tx(tx_byte);
      check(tx_byte == 8'h4F, "TX byte 5 should be 'O'");

      if (errors == 0) $display("  PASSED");
    end

    //=======================================================================
    // Test 6: RX FIFO (Multiple Bytes)
    //=======================================================================
    test_num = 6;
    $display("\n[Test %0d] Testing RX FIFO (5 bytes)...", test_num);
    begin
      reg [7:0] rdata;

      // Inject string "WORLD"
      inject_rx(8'h57);  // 'W'
      inject_rx(8'h4F);  // 'O'
      inject_rx(8'h52);  // 'R'
      inject_rx(8'h4C);  // 'L'
      inject_rx(8'h44);  // 'D'

      // Read back from RBR
      read_uart(REG_RBR_THR, rdata);
      check(rdata == 8'h57, "RX byte 1 should be 'W'");
      read_uart(REG_RBR_THR, rdata);
      check(rdata == 8'h4F, "RX byte 2 should be 'O'");
      read_uart(REG_RBR_THR, rdata);
      check(rdata == 8'h52, "RX byte 3 should be 'R'");
      read_uart(REG_RBR_THR, rdata);
      check(rdata == 8'h4C, "RX byte 4 should be 'L'");
      read_uart(REG_RBR_THR, rdata);
      check(rdata == 8'h44, "RX byte 5 should be 'D'");

      if (errors == 0) $display("  PASSED");
    end

    //=======================================================================
    // Test 7: TX FIFO Full (16 bytes)
    //=======================================================================
    test_num = 7;
    $display("\n[Test %0d] Testing TX FIFO (16 bytes)...", test_num);
    begin
      reg [7:0] lsr, tx_byte;
      integer local_errors;
      local_errors = errors;

      // Fill TX FIFO (16 bytes)
      // Note: First byte will immediately go to transmitter, so FIFO shows 15
      for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
        write_uart(REG_RBR_THR, 8'h30 + i);  // '0', '1', '2', ...
      end

      // Wait for FIFO state to settle
      #(CLK_PERIOD * 2);

      // Check LSR - TEMT should be 0 (transmitter has data)
      read_uart(REG_LSR, lsr);
      check(lsr[6] == 1'b0, "LSR[6] TEMT should be 0 when TX active");

      // Consume all bytes
      for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
        consume_tx(tx_byte);
        check(tx_byte == (8'h30 + i), "TX FIFO byte mismatch");
      end

      // Check LSR - both THRE and TEMT should be 1 (empty)
      #(CLK_PERIOD * 2);
      read_uart(REG_LSR, lsr);
      check(lsr[5] == 1'b1, "LSR[5] THRE should be 1 after draining");
      check(lsr[6] == 1'b1, "LSR[6] TEMT should be 1 after draining");

      if (errors == local_errors) $display("  PASSED");
    end

    //=======================================================================
    // Test 8: RX FIFO Full (16 bytes)
    //=======================================================================
    test_num = 8;
    $display("\n[Test %0d] Testing RX FIFO full condition...", test_num);
    begin
      reg [7:0] rdata;

      // Fill RX FIFO (16 bytes)
      for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
        inject_rx(8'h41 + i);  // 'A', 'B', 'C', ...
      end

      // Check that rx_ready is low (FIFO full)
      @(posedge clk);
      check(rx_ready == 1'b0, "rx_ready should be 0 when FIFO full");

      // Read all bytes
      for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
        read_uart(REG_RBR_THR, rdata);
        check(rdata == (8'h41 + i), "RX FIFO byte mismatch");
      end

      // Check that rx_ready is high again
      @(posedge clk);
      check(rx_ready == 1'b1, "rx_ready should be 1 after draining FIFO");

      if (errors == 0) $display("  PASSED");
    end

    //=======================================================================
    // Test 9: Interrupt Enable Register (IER)
    //=======================================================================
    test_num = 9;
    $display("\n[Test %0d] Testing IER read/write...", test_num);
    begin
      reg [7:0] rdata;

      write_uart(REG_IER, 8'b0000_0011);  // Enable RDA and THRE interrupts
      read_uart(REG_IER, rdata);
      check(rdata == 8'b0000_0011, "IER should read back 0x03");

      write_uart(REG_IER, 8'b0000_0000);  // Disable all interrupts
      read_uart(REG_IER, rdata);
      check(rdata == 8'b0000_0000, "IER should read back 0x00");

      if (errors == 0) $display("  PASSED");
    end

    //=======================================================================
    // Test 10: RX Data Available Interrupt
    //=======================================================================
    test_num = 10;
    $display("\n[Test %0d] Testing RX data available interrupt...", test_num);
    begin
      reg [7:0] iir, rdata;

      // Enable RDA interrupt
      write_uart(REG_IER, 8'b0000_0001);

      // Inject RX data
      inject_rx(8'hAA);

      // Check IIR - interrupt should be pending
      read_uart(REG_IIR_FCR, iir);
      check(iir[0] == 1'b0, "IIR[0] should be 0 (interrupt pending)");
      check(iir[3:1] == 3'b010, "IIR[3:1] should be 010 (RDA interrupt)");
      check(irq_o == 1'b1, "irq_o should be asserted");

      // Read RBR to clear interrupt
      read_uart(REG_RBR_THR, rdata);
      check(rdata == 8'hAA, "RBR should read 0xAA");

      // Check IIR - interrupt should be cleared
      #(CLK_PERIOD * 2);
      read_uart(REG_IIR_FCR, iir);
      check(iir[0] == 1'b1, "IIR[0] should be 1 (no interrupt)");
      check(irq_o == 1'b0, "irq_o should be deasserted");

      // Disable interrupts
      write_uart(REG_IER, 8'h00);

      if (errors == 0) $display("  PASSED");
    end

    //=======================================================================
    // Test 11: TX Empty Interrupt
    //=======================================================================
    test_num = 11;
    $display("\n[Test %0d] Testing TX empty interrupt...", test_num);
    begin
      reg [7:0] iir, tx_byte;

      // Enable THRE interrupt
      write_uart(REG_IER, 8'b0000_0010);

      // TX FIFO is already empty, so interrupt should fire
      #(CLK_PERIOD * 2);
      check(irq_o == 1'b1, "irq_o should be asserted for TX empty");

      read_uart(REG_IIR_FCR, iir);
      check(iir[0] == 1'b0, "IIR[0] should be 0 (interrupt pending)");
      check(iir[3:1] == 3'b001, "IIR[3:1] should be 001 (THRE interrupt)");

      // Write to THR to clear interrupt
      write_uart(REG_RBR_THR, 8'h55);

      // Interrupt should be deasserted
      #(CLK_PERIOD * 2);
      check(irq_o == 1'b0, "irq_o should be deasserted after THR write");

      // Consume TX byte
      consume_tx(tx_byte);
      check(tx_byte == 8'h55, "TX should output 0x55");

      // TX is empty again, interrupt should fire again
      #(CLK_PERIOD * 2);
      check(irq_o == 1'b1, "irq_o should reassert when TX empty again");

      // Disable interrupts
      write_uart(REG_IER, 8'h00);

      if (errors == 0) $display("  PASSED");
    end

    //=======================================================================
    // Test 12: FIFO Clear via FCR
    //=======================================================================
    test_num = 12;
    $display("\n[Test %0d] Testing FIFO clear via FCR...", test_num);
    begin
      reg [7:0] lsr, rdata;

      // Fill TX FIFO with data
      write_uart(REG_RBR_THR, 8'h11);
      write_uart(REG_RBR_THR, 8'h22);
      write_uart(REG_RBR_THR, 8'h33);

      // Check TX FIFO not empty
      read_uart(REG_LSR, lsr);
      check(lsr[6] == 1'b0, "LSR[6] TEMT should be 0 (TX FIFO has data)");

      // Clear TX FIFO
      write_uart(REG_IIR_FCR, 8'b0000_0100);  // Bit 2: Clear TX FIFO

      // Check TX FIFO empty
      #(CLK_PERIOD * 2);
      read_uart(REG_LSR, lsr);
      check(lsr[6] == 1'b1, "LSR[6] TEMT should be 1 after TX FIFO clear");

      // Fill RX FIFO
      inject_rx(8'hAA);
      inject_rx(8'hBB);

      // Check RX FIFO not empty
      read_uart(REG_LSR, lsr);
      check(lsr[0] == 1'b1, "LSR[0] DR should be 1 (RX data available)");

      // Clear RX FIFO
      write_uart(REG_IIR_FCR, 8'b0000_0010);  // Bit 1: Clear RX FIFO

      // Check RX FIFO empty
      #(CLK_PERIOD * 2);
      read_uart(REG_LSR, lsr);
      check(lsr[0] == 1'b0, "LSR[0] DR should be 0 after RX FIFO clear");

      if (errors == 0) $display("  PASSED");
    end

    //=======================================================================
    // Test Summary
    //=======================================================================
    #(CLK_PERIOD * 10);
    $display("\n========================================");
    $display("UART Testbench Complete");
    $display("========================================");
    $display("Tests Run: %0d", test_num);
    $display("Errors:    %0d", errors);
    if (errors == 0) begin
      $display("STATUS: ALL TESTS PASSED ✓");
    end else begin
      $display("STATUS: FAILED ✗");
    end
    $display("========================================");

    $finish;
  end

  //===========================================================================
  // Timeout Watchdog
  //===========================================================================
  initial begin
    #(CLK_PERIOD * 10000);  // 100us timeout
    $display("\nERROR: Testbench timeout!");
    $finish;
  end

endmodule
