`timescale 1ns/1ps

module test_debug7;
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
    
    repeat(10) begin
      @(posedge clk);
      $display("PC=%h exc=%b idex_instr=%h idex_valid=%b idex_illegal=%b ex_illegal_csr=%b", 
               pc_out, dut.exception, dut.idex_instruction,
               dut.idex_valid, dut.idex_illegal_inst, dut.ex_illegal_csr);
    end
    
    $finish;
  end
endmodule
