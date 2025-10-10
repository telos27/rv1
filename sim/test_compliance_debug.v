`timescale 1ns/1ps

module test_compliance_debug;
  reg clk = 0;
  reg reset_n = 0;
  wire [31:0] pc_out;
  wire [31:0] instr_out;

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

  initial begin
    #20 reset_n = 1;
    
    repeat(100) begin
      @(posedge clk);
      if (pc_out == 32'h68) begin
        $display("Stuck at PC=0x68: instr=%h exception=%b trap_flush=%b mret_flush=%b ex_take_branch=%b", 
                 instr_out, dut.exception, dut.trap_flush, dut.mret_flush, dut.ex_take_branch);
        $display("  pc_next=%h pc_plus_4=%h trap_vector=%h mepc=%h", 
                 dut.pc_next, dut.pc_plus_4, dut.trap_vector, dut.mepc);
        $display("  memwb_reg_write=%b memwb_rd=%d memwb_data=%h",
                 dut.memwb_reg_write, dut.memwb_rd_addr, dut.wb_data);
      end
    end
    
    $finish;
  end
endmodule
