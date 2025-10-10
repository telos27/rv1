`timescale 1ns/1ps

module test_find_stuck;
  reg clk = 0;
  reg reset_n = 0;
  wire [31:0] pc_out;
  wire [31:0] instr_out;
  integer cycle_count = 0;
  reg [31:0] last_pc = 0;
  integer stuck_count = 0;

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
      
      if (pc_out == last_pc) begin
        stuck_count = stuck_count + 1;
        if (stuck_count == 5) begin
          $display("PC STUCK at cycle %0d: PC=%h instr=%h", cycle_count, pc_out, instr_out);
          $display("  exception=%b trap_flush=%b pc_next=%h", dut.exception, dut.trap_flush, dut.pc_next);
          $display("  stall_pc=%b ex_take_branch=%b", dut.stall_pc, dut.ex_take_branch);
          $finish;
        end
      end else begin
        stuck_count = 0;
      end
      
      last_pc = pc_out;
      
      if (cycle_count >= 10000) begin
        $display("Timeout at cycle %0d, PC=%h", cycle_count, pc_out);
        $finish;
      end
    end
  end

  initial begin
    #20 reset_n = 1;
  end
endmodule
