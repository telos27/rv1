`timescale 1ns/1ps

module test_debug;
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
    $dumpfile("sim/waves/debug.vcd");
    $dumpvars(0, test_debug);
    $dumpvars(0, dut.exception);
    $dumpvars(0, dut.trap_flush);
    $dumpvars(0, dut.trap_vector);
    $dumpvars(0, dut.pc_next);
    
    #20 reset_n = 1;
    
    repeat(20) begin
      @(posedge clk);
      $display("PC=%h instr=%h exception=%b trap_flush=%b trap_vector=%h", 
               pc_out, instr_out, dut.exception, dut.trap_flush, dut.trap_vector);
    end
    
    $finish;
  end
endmodule
