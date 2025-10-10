`timescale 1ns/1ps

module test_auipc_illegal;
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
      
      if (pc_out == 32'hD4 || (cycle_count >= 36 && cycle_count <= 38)) begin
        $display("Cycle %0d: PC=%h", cycle_count, pc_out);
        $display("  ifid_instr=%h id_opcode=%h id_illegal=%b", 
                 dut.ifid_instruction, dut.id_opcode, dut.id_illegal_inst);
        $display("  idex_instr=%h idex_illegal=%b idex_valid=%b",
                 dut.idex_instruction, dut.idex_illegal_inst, dut.idex_valid);
      end
      
      if (cycle_count >= 40) $finish;
    end
  end

  initial begin
    #20 reset_n = 1;
  end
endmodule
