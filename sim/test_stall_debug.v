`timescale 1ns/1ps

module test_stall_debug;
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
        $display("PC=0x68: stall_pc=%b stall_ifid=%b flush_ifid=%b flush_idex=%b", 
                 dut.stall_pc, dut.stall_ifid, dut.flush_ifid, dut.flush_idex);
        $display("  idex_mem_read=%b idex_rd=%d id_rs1=%d id_rs2=%d",
                 dut.idex_mem_read, dut.idex_rd_addr, dut.id_rs1, dut.id_rs2);
        $display("  pc_current=%h pc_next=%h instr=%h",
                 dut.pc_current, dut.pc_next, instr_out);
      end
    end
    
    $finish;
  end
endmodule
