`timescale 1ns/1ps

module test_debug5;
  reg clk = 0;
  reg reset_n = 0;
  wire [31:0] pc_out;
  wire [31:0] instr_out;

  always #5 clk = ~clk;

  rv32i_core_pipelined #(
    .RESET_VECTOR(32'h00000000),
    .MEM_FILE("tests/vectors/simple_add.hex")
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(pc_out),
    .instr_out(instr_out)
  );

  initial begin
    #20 reset_n = 1;
    
    repeat(15) begin
      @(posedge clk);
      $display("PC=%h instr=%h pc_next=%h trap_flush=%b ex_take_branch=%b", 
               pc_out, instr_out, dut.pc_next, dut.trap_flush, dut.ex_take_branch);
    end
    
    $finish;
  end
endmodule
