`timescale 1ns/1ps

module test_debug4;
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
    
    repeat(30) begin
      @(posedge clk);
      $display("PC=%h instr=%h ifid_instr=%h reg_write=%b memwb_rd=%d memwb_data=%h", 
               pc_out, instr_out, dut.ifid_instruction, 
               dut.memwb_reg_write, dut.memwb_rd_addr, dut.wb_data);
    end
    
    $finish;
  end
endmodule
