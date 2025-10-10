`timescale 1ns/1ps

module test_reach_ecall;
  reg clk = 0;
  reg reset_n = 0;
  wire [31:0] pc_out;
  wire [31:0] instr_out;
  integer cycle_count = 0;
  reg [31:0] max_pc = 0;

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
      
      if (pc_out > max_pc) begin
        max_pc = pc_out;
        $display("New max PC reached: 0x%h at cycle %0d", max_pc, cycle_count);
      end
      
      if (pc_out >= 32'h158 && pc_out < 32'h160) begin
        $display("Near ECALL! Cycle %0d: PC=%h instr=%h", cycle_count, pc_out, instr_out);
      end
      
      if (cycle_count >= 1000) begin
        $display("After 1000 cycles, max PC reached: 0x%h", max_pc);
        $finish;
      end
    end
  end

  initial begin
    #20 reset_n = 1;
  end
endmodule
