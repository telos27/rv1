`timescale 1ns/1ps

module test_stuck_at_d4;
  reg clk = 0;
  reg reset_n = 0;
  wire [31:0] pc_out;
  wire [31:0] instr_out;
  integer cycle_count = 0;

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
      
      if (cycle_count >= 35 && cycle_count <= 45) begin
        $display("Cycle %0d: PC=%h instr=%h x3(gp)=%h", 
                 cycle_count, pc_out, instr_out, dut.regfile.registers[3]);
      end
      
      if (cycle_count >= 50) $finish;
    end
  end

  initial begin
    #20 reset_n = 1;
  end
endmodule
