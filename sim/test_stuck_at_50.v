`timescale 1ns/1ps

module test_stuck_at_50;
  reg clk = 0;
  reg reset_n = 0;
  wire [31:0] pc_out;
  wire [31:0] instr_out;
  integer cycle_count = 0;
  integer stuck_count = 0;
  reg [31:0] last_pc = 0;

  always #5 clk = ~clk;

  rv32i_core_pipelined #(
    .RESET_VECTOR(32'h00000000),
    .MEM_FILE("tests/riscv-compliance/rv32ui-p-add.hex")
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(pc_out),
    .instr_out(instr_out)
  );

  always @(posedge clk) begin
    if (reset_n) begin
      cycle_count = cycle_count + 1;

      // Check if PC is stuck
      if (pc_out == last_pc && pc_out == 32'h50) begin
        stuck_count = stuck_count + 1;
        if (stuck_count <= 10 || (stuck_count % 100 == 0)) begin
          $display("Cycle %0d: STUCK at PC=0x50 (count=%0d)", cycle_count, stuck_count);
          $display("  if_instr=%h ifid_valid=%b", instr_out, dut.ifid_valid);
          $display("  stall_pc=%b stall_ifid=%b flush_ifid=%b",
                   dut.stall_pc, dut.stall_ifid, dut.flush_ifid);
          $display("  idex_valid=%b exmem_valid=%b memwb_valid=%b",
                   dut.idex_valid, dut.exmem_valid, dut.memwb_valid);
          $display("  exception=%b trap_flush=%b mret_flush=%b",
                   dut.exception, dut.trap_flush, dut.mret_flush);
        end
      end else if (pc_out != last_pc) begin
        if (stuck_count > 0) begin
          $display("Cycle %0d: PC advanced from 0x%h to 0x%h (was stuck for %0d cycles)",
                   cycle_count, last_pc, pc_out, stuck_count);
          stuck_count = 0;
        end
      end

      last_pc = pc_out;

      if (cycle_count >= 100) $finish;
    end
  end

  initial begin
    #20 reset_n = 1;
  end
endmodule
