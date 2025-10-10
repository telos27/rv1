`timescale 1ns/1ps

module test_debug2;
  reg clk = 0;
  reg reset_n = 0;
  wire [31:0] pc_out;
  wire [31:0] instr_out;

  always #5 clk = ~clk;

  rv32i_core_pipelined #(
    .RESET_VECTOR(32'h00000000),
    .MEM_FILE("tests/hex/simple_add.hex")
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(pc_out),
    .instr_out(instr_out)
  );

  initial begin
    #20 reset_n = 1;
    
    repeat(20) begin
      @(posedge clk);
      $display("Cycle PC=%h instr=%h exc=%b code=%h idex_valid=%b exmem_valid=%b", 
               pc_out, instr_out, dut.exception, dut.exception_code, 
               dut.idex_valid, dut.exmem_valid);
    end
    
    $finish;
  end
endmodule
