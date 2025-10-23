// tb_debug_mixed.v - Debug testbench for mixed compressed/normal instructions
// Traces PC, instruction fetch, decode, and pipeline control signals

`timescale 1ns/1ps

module tb_debug_mixed;

  parameter CLK_PERIOD = 10;
  parameter MAX_CYCLES = 30;  // Only run 30 cycles for debugging

  reg clk;
  reg reset_n;
  wire [31:0] pc;
  wire [31:0] instruction;

  // Instantiate core
  rv_core_pipelined #(
    .RESET_VECTOR(32'h00000000),
    .IMEM_SIZE(16384),
    .DMEM_SIZE(16384),
    .MEM_FILE("tests/asm/test_mixed_real.hex")
  ) core (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(pc),
    .instr_out(instruction)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  integer cycle;

  // Monitor critical signals
  initial begin
    $dumpfile("sim/waves/debug_mixed.vcd");
    $dumpvars(0, tb_debug_mixed);

    $display("========================================");
    $display("Debug: Mixed Compressed/Normal Instructions");
    $display("========================================");

    reset_n = 0;
    cycle = 0;

    // Release reset
    repeat(5) @(posedge clk);
    reset_n = 1;
    $display("Reset released at cycle 5");
    $display("");
    $display("Cycle | PC(IF)   | PC_next  | IFID_PC  | IDEX_PC  | Flush | Trap | ExcCode");
    $display("------|----------|----------|----------|----------|-------|------|--------");

    // Monitor execution
    for (cycle = 0; cycle < MAX_CYCLES; cycle = cycle + 1) begin
      @(posedge clk);

      // Access internal signals (need to use hierarchical references)
      $display("%5d | %08h | %08h | %08h | %08h | %b     | %b    | %02h",
        cycle,
        pc,
        core.pc_next,
        core.ifid_pc,
        core.idex_pc,
        core.flush_ifid,
        core.trap_flush,
        core.exception_code
      );

      // Stop if ebreak detected or PC stuck
      if (cycle > 10 && pc == core.pc_current) begin
        $display("");
        $display("ERROR: PC appears stuck at %08h for multiple cycles!", pc);
        $display("");
        $display("=== Pipeline State ===");
        $display("IF stage:");
        $display("  if_instruction_raw  = %08h", core.if_instruction_raw);
        $display("  if_is_compressed    = %b", core.if_is_compressed);
        $display("  if_instruction      = %08h", core.if_instruction);
        $display("  pc_current          = %08h", core.pc_current);
        $display("  pc_next             = %08h", core.pc_next);
        $display("  pc_increment        = %08h", core.pc_increment);
        $display("  pc_plus_2           = %08h", core.pc_plus_2);
        $display("  pc_plus_4           = %08h", core.pc_plus_4);
        $display("");
        $display("Pipeline control:");
        $display("  stall_pc            = %b", core.stall_pc);
        $display("  stall_ifid          = %b", core.stall_ifid);
        $display("  flush_ifid          = %b", core.flush_ifid);
        $display("  flush_idex          = %b", core.flush_idex);
        $display("");
        $display("Flush sources:");
        $display("  trap_flush          = %b", core.trap_flush);
        $display("  mret_flush          = %b", core.mret_flush);
        $display("  sret_flush          = %b", core.sret_flush);
        $display("  ex_take_branch      = %b", core.ex_take_branch);
        $display("");
        $display("ID/EX stage:");
        $display("  idex_pc             = %08h", core.idex_pc);
        $display("  idex_instruction    = %08h", core.idex_instruction);
        $display("");

        $finish;
      end

      // Check for success
      if (core.regfile.registers[28] == 32'h0000BEEF) begin
        $display("");
        $display("SUCCESS: x28 = 0x0000BEEF");
        $display("Final x10 = %08h (expected 0x00000064 = 100)", core.regfile.registers[10]);
        $finish;
      end
    end

    $display("");
    $display("TIMEOUT: Reached %0d cycles", MAX_CYCLES);
    $finish;
  end

endmodule
