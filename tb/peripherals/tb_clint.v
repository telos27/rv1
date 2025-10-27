// tb_clint.v - Testbench for CLINT (Core-Local Interruptor)
// Tests MTIME counter, MTIMECMP compare, MSIP software interrupt
// Author: RV1 Project
// Date: 2025-10-26

`timescale 1ns / 1ps

module tb_clint;

  //===========================================================================
  // Parameters
  //===========================================================================
  parameter CLK_PERIOD = 10;  // 10ns = 100MHz
  parameter NUM_HARTS = 2;    // Test with 2 harts

  //===========================================================================
  // Signals
  //===========================================================================
  reg         clk;
  reg         reset_n;

  // Memory interface
  reg         req_valid;
  reg  [15:0] req_addr;
  reg  [63:0] req_wdata;
  reg         req_we;
  reg  [2:0]  req_size;
  wire        req_ready;
  wire [63:0] req_rdata;

  // Interrupt outputs
  wire [NUM_HARTS-1:0] mti_o;
  wire [NUM_HARTS-1:0] msi_o;

  // Test control
  integer test_num;
  integer errors;

  //===========================================================================
  // DUT Instantiation
  //===========================================================================
  clint #(
    .NUM_HARTS(NUM_HARTS),
    .BASE_ADDR(32'h0200_0000)
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    .req_valid(req_valid),
    .req_addr(req_addr),
    .req_wdata(req_wdata),
    .req_we(req_we),
    .req_size(req_size),
    .req_ready(req_ready),
    .req_rdata(req_rdata),
    .mti_o(mti_o),
    .msi_o(msi_o)
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

  // Write to CLINT register
  task write_clint;
    input [15:0] addr;
    input [63:0] data;
    input [2:0]  size;
    begin
      @(posedge clk);
      #1;  // Small delay to avoid race with module sampling
      req_valid = 1;
      req_addr  = addr;
      req_wdata = data;
      req_we    = 1;
      req_size  = size;
      @(posedge clk);
      while (!req_ready) @(posedge clk);
      req_valid = 0;
      req_we    = 0;
      @(posedge clk);
    end
  endtask

  // Read from CLINT register
  task read_clint;
    input  [15:0] addr;
    output [63:0] data;
    begin
      @(posedge clk);
      #1;  // Small delay to avoid race with module sampling
      req_valid = 1;
      req_addr  = addr;
      req_we    = 0;
      req_size  = 3'h3;  // 64-bit read
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
    req_size = 0;
    test_num = 0;
    errors = 0;

    // Waveform dump
    $dumpfile("waves/tb_clint.vcd");
    $dumpvars(0, tb_clint);

    $display("========================================");
    $display("CLINT Testbench Starting");
    $display("========================================");

    // Reset
    #(CLK_PERIOD * 5);
    reset_n = 1;
    #(CLK_PERIOD * 2);

    //=========================================================================
    // Test 1: MTIME Counter Increment
    //=========================================================================
    test_num = 1;
    $display("\nTest %0d: MTIME counter increments every cycle", test_num);
    begin
      reg [63:0] mtime_start, mtime_end, mtime_diff;
      read_clint(16'hBFF8, mtime_start);
      repeat (100) @(posedge clk);
      read_clint(16'hBFF8, mtime_end);
      mtime_diff = mtime_end - mtime_start;
      // Allow some tolerance for read latency (should be ~100 + read cycles)
      check((mtime_diff >= 100) && (mtime_diff <= 110), "MTIME should increment by ~100 after 100 cycles");
      $display("  MTIME start: 0x%016h, end: 0x%016h, diff: %0d", mtime_start, mtime_end, mtime_diff);
    end

    //=========================================================================
    // Test 2: Write and Read MTIME
    //=========================================================================
    test_num = 2;
    $display("\nTest %0d: Write and read MTIME", test_num);
    begin
      reg [63:0] mtime_read, mtime_expected;
      write_clint(16'hBFF8, 64'h1234_5678_9ABC_DEF0, 3'h3);  // 64-bit write
      #(CLK_PERIOD);  // Wait one cycle for write to complete
      read_clint(16'hBFF8, mtime_read);
      // MTIME continues to increment, so allow for a few cycles of drift
      mtime_expected = 64'h1234_5678_9ABC_DEF0;
      check((mtime_read >= mtime_expected) && (mtime_read <= mtime_expected + 10),
            "MTIME should be close to written value (accounting for increment)");
      $display("  MTIME written: 0x1234_5678_9ABC_DEF0, read: 0x%016h", mtime_read);
    end

    //=========================================================================
    // Test 3: MTIMECMP Write and Read (Hart 0)
    //=========================================================================
    test_num = 3;
    $display("\nTest %0d: Write and read MTIMECMP for hart 0", test_num);
    begin
      reg [63:0] mtimecmp_read;
      write_clint(16'h4000, 64'hDEAD_BEEF_CAFE_BABE, 3'h3);  // Hart 0 MTIMECMP
      read_clint(16'h4000, mtimecmp_read);
      check(mtimecmp_read == 64'hDEAD_BEEF_CAFE_BABE, "MTIMECMP should match written value");
      $display("  MTIMECMP[0] written: 0xDEAD_BEEF_CAFE_BABE, read: 0x%016h", mtimecmp_read);
    end

    //=========================================================================
    // Test 4: MTIMECMP Write and Read (Hart 1)
    //=========================================================================
    test_num = 4;
    $display("\nTest %0d: Write and read MTIMECMP for hart 1", test_num);
    begin
      reg [63:0] mtimecmp_read;
      write_clint(16'h4008, 64'h1111_2222_3333_4444, 3'h3);  // Hart 1 MTIMECMP (offset +8)
      read_clint(16'h4008, mtimecmp_read);
      check(mtimecmp_read == 64'h1111_2222_3333_4444, "MTIMECMP[1] should match written value");
      $display("  MTIMECMP[1] written: 0x1111_2222_3333_4444, read: 0x%016h", mtimecmp_read);
    end

    //=========================================================================
    // Test 5: Timer Interrupt Assertion (Hart 0)
    //=========================================================================
    test_num = 5;
    $display("\nTest %0d: Timer interrupt assertion when MTIME >= MTIMECMP", test_num);
    begin
      reg [63:0] mtime_current;
      // Set MTIME to known value
      write_clint(16'hBFF8, 64'h100, 3'h3);
      // Set MTIMECMP to MTIME + 50
      write_clint(16'h4000, 64'h132, 3'h3);

      // Initially, interrupt should be low (MTIME < MTIMECMP)
      #(CLK_PERIOD * 2);
      check(mti_o[0] == 1'b0, "MTI should be low when MTIME < MTIMECMP");

      // Wait for MTIME to reach MTIMECMP
      repeat (50) @(posedge clk);
      read_clint(16'hBFF8, mtime_current);

      // Now interrupt should be asserted
      #(CLK_PERIOD * 2);
      check(mti_o[0] == 1'b1, "MTI should be high when MTIME >= MTIMECMP");
      $display("  MTIME: 0x%016h, MTIMECMP[0]: 0x132, MTI[0]: %b", mtime_current, mti_o[0]);
    end

    //=========================================================================
    // Test 6: Clear Timer Interrupt by Writing MTIMECMP
    //=========================================================================
    test_num = 6;
    $display("\nTest %0d: Clear timer interrupt by updating MTIMECMP", test_num);
    begin
      // Timer interrupt should still be asserted from Test 5
      check(mti_o[0] == 1'b1, "MTI should still be high from previous test");

      // Write new MTIMECMP value far in the future
      write_clint(16'h4000, 64'hFFFF_FFFF_FFFF_FFFF, 3'h3);

      // Interrupt should now be cleared
      #(CLK_PERIOD * 2);
      check(mti_o[0] == 1'b0, "MTI should be low after MTIMECMP update");
      $display("  Updated MTIMECMP to 0xFFFF_FFFF_FFFF_FFFF, MTI[0]: %b", mti_o[0]);
    end

    //=========================================================================
    // Test 7: Software Interrupt (MSIP) - Hart 0
    //=========================================================================
    test_num = 7;
    $display("\nTest %0d: Software interrupt via MSIP", test_num);
    begin
      reg [63:0] msip_read;

      // Initially, MSIP should be 0
      read_clint(16'h0000, msip_read);
      check(msip_read == 64'h0, "MSIP should be 0 initially");
      check(msi_o[0] == 1'b0, "MSI should be low initially");

      // Write 1 to MSIP[0] to trigger software interrupt
      write_clint(16'h0000, 64'h1, 3'h3);
      #(CLK_PERIOD * 2);

      // Check interrupt is asserted
      check(msi_o[0] == 1'b1, "MSI should be high after writing MSIP=1");
      read_clint(16'h0000, msip_read);
      check(msip_read == 64'h1, "MSIP should read back as 1");
      $display("  MSIP[0] = 1, MSI[0]: %b", msi_o[0]);

      // Clear software interrupt
      write_clint(16'h0000, 64'h0, 3'h3);
      #(CLK_PERIOD * 2);
      check(msi_o[0] == 1'b0, "MSI should be low after clearing MSIP");
      $display("  MSIP[0] = 0, MSI[0]: %b", msi_o[0]);
    end

    //=========================================================================
    // Test 8: Software Interrupt (MSIP) - Hart 1
    //=========================================================================
    test_num = 8;
    $display("\nTest %0d: Software interrupt for hart 1", test_num);
    begin
      // Write to MSIP[1] (offset 0x0004)
      write_clint(16'h0004, 64'h1, 3'h3);
      #(CLK_PERIOD * 2);
      check(msi_o[1] == 1'b1, "MSI[1] should be high");
      check(msi_o[0] == 1'b0, "MSI[0] should remain low");
      $display("  MSIP[1] = 1, MSI[1]: %b, MSI[0]: %b", msi_o[1], msi_o[0]);

      // Clear
      write_clint(16'h0004, 64'h0, 3'h3);
      #(CLK_PERIOD * 2);
      check(msi_o[1] == 1'b0, "MSI[1] should be low after clear");
    end

    //=========================================================================
    // Test 9: 32-bit MTIMECMP Write (Lower and Upper)
    //=========================================================================
    test_num = 9;
    $display("\nTest %0d: 32-bit writes to MTIMECMP", test_num);
    begin
      reg [63:0] mtimecmp_read;

      // Write lower 32 bits
      write_clint(16'h4000, 64'h0000_0000_1234_5678, 3'h2);  // 32-bit write, lower
      read_clint(16'h4000, mtimecmp_read);
      check(mtimecmp_read[31:0] == 32'h1234_5678, "Lower 32 bits should match");
      $display("  After lower write: 0x%016h", mtimecmp_read);

      // Write upper 32 bits
      write_clint(16'h4004, 64'h0000_0000_9ABC_DEF0, 3'h2);  // 32-bit write, upper
      read_clint(16'h4000, mtimecmp_read);
      check(mtimecmp_read[63:32] == 32'h9ABC_DEF0, "Upper 32 bits should match");
      check(mtimecmp_read == 64'h9ABC_DEF0_1234_5678, "Full 64-bit value should be correct");
      $display("  After upper write: 0x%016h", mtimecmp_read);
    end

    //=========================================================================
    // Test 10: Simultaneous Timer Interrupts (Multiple Harts)
    //=========================================================================
    test_num = 10;
    $display("\nTest %0d: Multiple hart timer interrupts", test_num);
    begin
      // Set MTIME to known value
      write_clint(16'hBFF8, 64'h1000, 3'h3);

      // Set MTIMECMP for both harts to near-future values
      write_clint(16'h4000, 64'h1020, 3'h3);  // Hart 0: +32 cycles
      write_clint(16'h4008, 64'h1040, 3'h3);  // Hart 1: +64 cycles

      // Wait 40 cycles - hart 0 should trigger, hart 1 should not
      repeat (40) @(posedge clk);
      check(mti_o[0] == 1'b1, "Hart 0 timer interrupt should be asserted");
      check(mti_o[1] == 1'b0, "Hart 1 timer interrupt should not be asserted yet");
      $display("  After 40 cycles: MTI[0]=%b, MTI[1]=%b", mti_o[0], mti_o[1]);

      // Wait another 30 cycles - both should be asserted
      repeat (30) @(posedge clk);
      check(mti_o[0] == 1'b1, "Hart 0 timer interrupt should still be asserted");
      check(mti_o[1] == 1'b1, "Hart 1 timer interrupt should now be asserted");
      $display("  After 70 cycles: MTI[0]=%b, MTI[1]=%b", mti_o[0], mti_o[1]);
    end

    //=========================================================================
    // Test Results
    //=========================================================================
    #(CLK_PERIOD * 10);
    $display("\n========================================");
    if (errors == 0) begin
      $display("ALL TESTS PASSED (%0d tests)", test_num);
      $display("========================================");
      $finish(0);
    end else begin
      $display("TESTS FAILED: %0d errors in %0d tests", errors, test_num);
      $display("========================================");
      $finish(1);
    end
  end

  //===========================================================================
  // Timeout Watchdog
  //===========================================================================
  initial begin
    #(CLK_PERIOD * 10000);
    $display("\nERROR: Testbench timeout!");
    $finish(1);
  end

endmodule
