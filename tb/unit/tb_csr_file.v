// Testbench for CSR File
// Tests CSR read/write operations, trap handling, and MRET

`timescale 1ns / 1ps

module tb_csr_file;

  // Clock and reset
  reg clk;
  reg reset_n;

  // CSR interface
  reg [11:0] csr_addr;
  reg [31:0] csr_wdata;
  reg [2:0]  csr_op;
  reg        csr_we;
  wire [31:0] csr_rdata;

  // Trap interface
  reg        trap_entry;
  reg [31:0] trap_pc;
  reg [4:0]  trap_cause;
  reg [31:0] trap_val;
  wire [31:0] trap_vector;

  // MRET
  reg        mret;
  wire [31:0] mepc_out;

  // Status
  wire       mstatus_mie;
  wire       illegal_csr;

  // Test counters
  integer passed = 0;
  integer failed = 0;

  // CSR addresses
  localparam CSR_MSTATUS   = 12'h300;
  localparam CSR_MISA      = 12'h301;
  localparam CSR_MIE       = 12'h304;
  localparam CSR_MTVEC     = 12'h305;
  localparam CSR_MSCRATCH  = 12'h340;
  localparam CSR_MEPC      = 12'h341;
  localparam CSR_MCAUSE    = 12'h342;
  localparam CSR_MTVAL     = 12'h343;
  localparam CSR_MIP       = 12'h344;
  localparam CSR_MVENDORID = 12'hF11;
  localparam CSR_MARCHID   = 12'hF12;
  localparam CSR_MIMPID    = 12'hF13;
  localparam CSR_MHARTID   = 12'hF14;

  // CSR operations
  localparam CSR_RW  = 3'b001;
  localparam CSR_RS  = 3'b010;
  localparam CSR_RC  = 3'b011;
  localparam CSR_RWI = 3'b101;
  localparam CSR_RSI = 3'b110;
  localparam CSR_RCI = 3'b111;

  // Instantiate CSR file
  csr_file uut (
    .clk(clk),
    .reset_n(reset_n),
    .csr_addr(csr_addr),
    .csr_wdata(csr_wdata),
    .csr_op(csr_op),
    .csr_we(csr_we),
    .csr_rdata(csr_rdata),
    .trap_entry(trap_entry),
    .trap_pc(trap_pc),
    .trap_cause(trap_cause),
    .trap_val(trap_val),
    .trap_vector(trap_vector),
    .mret(mret),
    .mepc_out(mepc_out),
    .mstatus_mie(mstatus_mie),
    .illegal_csr(illegal_csr)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Test task
  task check;
    input [31:0] expected;
    input [31:0] actual;
    input [255:0] test_name;
    begin
      if (expected === actual) begin
        $display("PASS: %s (expected=%h, actual=%h)", test_name, expected, actual);
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
    $display("CSR File Unit Test");
    $display("========================================");

    // Initialize signals
    reset_n = 0;
    csr_addr = 0;
    csr_wdata = 0;
    csr_op = 0;
    csr_we = 0;
    trap_entry = 0;
    trap_pc = 0;
    trap_cause = 0;
    trap_val = 0;
    mret = 0;

    // Reset
    #20;
    reset_n = 1;
    #10;

    // ======================================================================
    // Test 1: Read-Only CSRs
    // ======================================================================
    $display("\n--- Test 1: Read-Only CSRs ---");

    // MISA
    csr_addr = CSR_MISA;
    #10;
    check(32'h4000_0100, csr_rdata, "MISA read (RV32I)");

    // MVENDORID
    csr_addr = CSR_MVENDORID;
    #10;
    check(32'h0000_0000, csr_rdata, "MVENDORID read");

    // MARCHID
    csr_addr = CSR_MARCHID;
    #10;
    check(32'h0000_0000, csr_rdata, "MARCHID read");

    // MIMPID
    csr_addr = CSR_MIMPID;
    #10;
    check(32'h0000_0001, csr_rdata, "MIMPID read");

    // MHARTID
    csr_addr = CSR_MHARTID;
    #10;
    check(32'h0000_0000, csr_rdata, "MHARTID read");

    // ======================================================================
    // Test 2: CSRRW (Read/Write)
    // ======================================================================
    $display("\n--- Test 2: CSRRW (Read/Write) ---");

    // Write to MSCRATCH
    csr_addr = CSR_MSCRATCH;
    csr_wdata = 32'hDEAD_BEEF;
    csr_op = CSR_RW;
    csr_we = 1;
    #10;
    @(posedge clk);
    #1;
    csr_we = 0;
    #10;
    check(32'hDEAD_BEEF, csr_rdata, "MSCRATCH write/read");

    // Write to MTVEC
    csr_addr = CSR_MTVEC;
    csr_wdata = 32'h0000_1000;
    csr_op = CSR_RW;
    csr_we = 1;
    #10;
    @(posedge clk);
    #1;
    csr_we = 0;
    #10;
    check(32'h0000_1000, csr_rdata, "MTVEC write/read");
    check(32'h0000_1000, trap_vector, "MTVEC output");

    // ======================================================================
    // Test 3: CSRRS (Read/Set)
    // ======================================================================
    $display("\n--- Test 3: CSRRS (Read/Set) ---");

    // Write initial value to MIE
    csr_addr = CSR_MIE;
    csr_wdata = 32'h0000_00FF;
    csr_op = CSR_RW;
    csr_we = 1;
    #10;
    @(posedge clk);
    #1;
    csr_we = 0;
    #10;

    // Set additional bits
    csr_wdata = 32'h0000_FF00;
    csr_op = CSR_RS;
    csr_we = 1;
    #10;
    @(posedge clk);
    #1;
    csr_we = 0;
    #10;
    check(32'h0000_FFFF, csr_rdata, "MIE set bits");

    // ======================================================================
    // Test 4: CSRRC (Read/Clear)
    // ======================================================================
    $display("\n--- Test 4: CSRRC (Read/Clear) ---");

    // Clear some bits
    csr_addr = CSR_MIE;
    csr_wdata = 32'h0000_0F0F;
    csr_op = CSR_RC;
    csr_we = 1;
    #10;
    @(posedge clk);
    #1;
    csr_we = 0;
    #10;
    check(32'h0000_F0F0, csr_rdata, "MIE clear bits");

    // ======================================================================
    // Test 5: MSTATUS Read/Write
    // ======================================================================
    $display("\n--- Test 5: MSTATUS Read/Write ---");

    // Write to MSTATUS (set MIE and MPP)
    csr_addr = CSR_MSTATUS;
    csr_wdata = 32'h0000_1808;  // MIE = 1, MPP = 11
    csr_op = CSR_RW;
    csr_we = 1;
    #10;
    @(posedge clk);
    #1;
    csr_we = 0;
    #10;
    check(32'h0000_1808, csr_rdata, "MSTATUS write (MIE=1, MPP=11)");
    check(1'b1, mstatus_mie, "MSTATUS.MIE output");

    // Set MPIE
    csr_wdata = 32'h0000_0080;  // MPIE = 1
    csr_op = CSR_RS;
    csr_we = 1;
    #10;
    @(posedge clk);
    #1;
    csr_we = 0;
    #10;
    check(32'h0000_1888, csr_rdata, "MSTATUS set MPIE");

    // ======================================================================
    // Test 6: Trap Entry
    // ======================================================================
    $display("\n--- Test 6: Trap Entry ---");

    // Check MSTATUS before trap for debugging
    csr_addr = CSR_MSTATUS;
    #10;
    $display("DEBUG: MSTATUS before trap = %h", csr_rdata);
    $display("DEBUG: mstatus_mie_r = %b, mstatus_mpie_r = %b", uut.mstatus_mie_r, uut.mstatus_mpie_r);

    // Trigger trap (illegal instruction)
    @(negedge clk);     // Align to negative edge
    $display("DEBUG: Before trap, trap_entry=%b, mret=%b, csr_we=%b", trap_entry, mret, csr_we);
    trap_entry = 1;
    trap_pc = 32'h0000_0100;
    trap_cause = 5'd2;  // Illegal instruction
    trap_val = 32'hBAD0_C0DE;
    $display("DEBUG: Trap signals set, trap_entry=%b, mret=%b, csr_we=%b", trap_entry, mret, csr_we);
    @(posedge clk);     // Wait for positive edge (trap happens here)
    #1;
    $display("DEBUG: Just after posedge, mstatus_mie_r = %b, mstatus_mpie_r = %b", uut.mstatus_mie_r, uut.mstatus_mpie_r);
    @(posedge clk);     // Wait one more cycle for it to settle
    trap_entry = 0;
    #1;
    $display("DEBUG: After trap, mstatus_mie_r = %b, mstatus_mpie_r = %b", uut.mstatus_mie_r, uut.mstatus_mpie_r);
    #10;

    // Check MEPC
    csr_addr = CSR_MEPC;
    #10;
    check(32'h0000_0100, csr_rdata, "MEPC after trap");
    check(32'h0000_0100, mepc_out, "MEPC output");

    // Check MCAUSE
    csr_addr = CSR_MCAUSE;
    #10;
    check(32'h0000_0002, csr_rdata, "MCAUSE after trap (illegal inst)");

    // Check MTVAL
    csr_addr = CSR_MTVAL;
    #10;
    check(32'hBAD0_C0DE, csr_rdata, "MTVAL after trap");

    // Check MSTATUS (MIE should be 0, MPIE should be old MIE which was 1)
    csr_addr = CSR_MSTATUS;
    #10;
    check(32'h0000_1880, csr_rdata, "MSTATUS after trap (MIE=0, MPIE=1, MPP=11)");
    check(1'b0, mstatus_mie, "MSTATUS.MIE disabled");

    // ======================================================================
    // Test 7: MRET (Trap Return)
    // ======================================================================
    $display("\n--- Test 7: MRET (Trap Return) ---");

    // Execute MRET
    mret = 1;
    #10;
    @(posedge clk);
    #1;
    mret = 0;
    #10;

    // Check MSTATUS (MIE should be restored from MPIE)
    csr_addr = CSR_MSTATUS;
    #10;
    check(32'h0000_1888, csr_rdata, "MSTATUS after MRET (MIE=1, MPIE=1)");
    check(1'b1, mstatus_mie, "MSTATUS.MIE restored");

    // ======================================================================
    // Test 8: Write to Read-Only CSR (Illegal)
    // ======================================================================
    $display("\n--- Test 8: Write to Read-Only CSR ---");

    csr_addr = CSR_MISA;
    csr_wdata = 32'hFFFF_FFFF;
    csr_op = CSR_RW;
    csr_we = 1;
    #10;
    check(1'b1, illegal_csr, "Illegal CSR write to MISA");
    csr_we = 0;
    #10;

    // ======================================================================
    // Test 9: Invalid CSR Address
    // ======================================================================
    $display("\n--- Test 9: Invalid CSR Address ---");

    csr_addr = 12'hFFF;  // Invalid
    csr_we = 0;
    #10;
    check(32'h0, csr_rdata, "Invalid CSR read returns 0");

    csr_we = 1;
    #10;
    check(1'b1, illegal_csr, "Illegal CSR write to invalid addr");
    csr_we = 0;
    #10;

    // ======================================================================
    // Test 10: Nested Trap
    // ======================================================================
    $display("\n--- Test 10: Nested Trap ---");

    // First trap (ECALL)
    trap_entry = 1;
    trap_pc = 32'h0000_0200;
    trap_cause = 5'd11;  // ECALL from M-mode
    trap_val = 32'h0;
    #10;
    @(posedge clk);
    #1;
    trap_entry = 0;
    #10;

    // Check MEPC
    csr_addr = CSR_MEPC;
    #10;
    check(32'h0000_0200, csr_rdata, "MEPC after first nested trap");

    // Check MCAUSE
    csr_addr = CSR_MCAUSE;
    #10;
    check(32'h0000_000B, csr_rdata, "MCAUSE after first nested trap (ECALL)");

    // Second trap (breakpoint) - should overwrite first
    trap_entry = 1;
    trap_pc = 32'h0000_0300;
    trap_cause = 5'd3;  // Breakpoint
    trap_val = 32'h0;
    #10;
    @(posedge clk);
    #1;
    trap_entry = 0;
    #10;

    // Check MEPC (should be new PC)
    csr_addr = CSR_MEPC;
    #10;
    check(32'h0000_0300, csr_rdata, "MEPC after second nested trap");

    // Check MCAUSE (should be new cause)
    csr_addr = CSR_MCAUSE;
    #10;
    check(32'h0000_0003, csr_rdata, "MCAUSE after second nested trap (breakpoint)");

    // ======================================================================
    // Test 11: Alignment Enforcement
    // ======================================================================
    $display("\n--- Test 11: Alignment Enforcement ---");

    // Write misaligned MTVEC
    csr_addr = CSR_MTVEC;
    csr_wdata = 32'h0000_1003;  // Misaligned (last 2 bits != 0)
    csr_op = CSR_RW;
    csr_we = 1;
    #10;
    @(posedge clk);
    #1;
    csr_we = 0;
    #10;
    check(32'h0000_1000, csr_rdata, "MTVEC aligned to 4 bytes");

    // Write misaligned MEPC
    csr_addr = CSR_MEPC;
    csr_wdata = 32'h0000_0505;  // Misaligned
    csr_op = CSR_RW;
    csr_we = 1;
    #10;
    @(posedge clk);
    #1;
    csr_we = 0;
    #10;
    check(32'h0000_0504, csr_rdata, "MEPC aligned to 4 bytes");

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

  // Timeout
  initial begin
    #10000;
    $display("ERROR: Testbench timeout!");
    $finish;
  end

endmodule
