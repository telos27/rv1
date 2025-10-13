// tb_debug_simple.v - Ultra-simple debug testbench
// Just runs a few cycles and prints what happens

`timescale 1ns / 1ps

module tb_debug_simple;
  reg clk;
  reg reset_n;
  wire [31:0] pc_out;
  wire [31:0] instr_out;
  integer cycle;

  // Instantiate core with simple_add test
  rv_core_pipelined #(
    .XLEN(32),
    .RESET_VECTOR(32'h0),
    .IMEM_SIZE(1024),
    .DMEM_SIZE(1024),
    .MEM_FILE("tests/asm/test_rvc_simple.hex")
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(pc_out),
    .instr_out(instr_out)
  );

  // Clock
  integer clk_toggle_count = 0;
  initial begin
    clk = 0;
    forever begin
      #5 clk = ~clk;
      clk_toggle_count = clk_toggle_count + 1;
      if (clk_toggle_count > 100) begin
        $display("ERROR: Clock toggled >100 times but simulation hasn't progressed!");
        $finish;
      end
    end
  end

  // Test
  initial begin
    cycle = 0;
    reset_n = 0;
    #25;
    reset_n = 1;

    $display("\n=== Starting Debug Test ===\n");
    $display("About to run 20 cycles...");

    // Add monitor for critical signals
    $monitor("Time=%0t clk=%b PC=0x%h is_c=%b pc_inc=0x%h pc_next=0x%h",
             $time, clk, pc_out, dut.if_is_compressed, dut.pc_increment, dut.pc_next);

    // Run for 20 cycles and print everything
    repeat(20) begin
      $display("Waiting for clock edge...");
      $fflush();
      @(posedge clk);
      $display("Clock edge detected!");
      $fflush();
      cycle = cycle + 1;
      $display("Cycle %2d: PC=0x%08h, IF_Instr=0x%08h, is_c=%b, stall=%b, x10=%0d",
               cycle, pc_out, instr_out, dut.if_is_compressed, dut.stall_pc, dut.regfile.registers[10]);
      $fflush();
    end

    $display("\n=== Final Register State ===");
    $display("x10 = %0d (expected 15)", dut.regfile.registers[10]);
    $display("x11 = %0d (expected 10)", dut.regfile.registers[11]);
    $display("x12 = %0d (expected 15)", dut.regfile.registers[12]);

    $finish;
  end

endmodule
