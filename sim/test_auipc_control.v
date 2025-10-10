`timescale 1ns/1ps

module test_auipc_control;
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

      // Monitor around cycle 36-38 when AUIPC reaches ID stage
      if (cycle_count >= 35 && cycle_count <= 40) begin
        $display("Cycle %0d: PC=%h if_instr=%h", cycle_count, pc_out, instr_out);
        $display("  ifid_instr=%h id_opcode=%b", dut.ifid_instruction, dut.id_opcode);
        $display("  id_illegal_inst=%b control.illegal_inst=%b",
                 dut.id_illegal_inst, dut.control_inst.illegal_inst);
        $display("  idex_illegal=%b idex_valid=%b idex_instr=%h",
                 dut.idex_illegal_inst, dut.idex_valid, dut.idex_instruction);
        $display("  exception=%b exception_code=%h", dut.exception, dut.exception_code);
        $display("");
      end

      if (cycle_count >= 42) $finish;
    end
  end

  initial begin
    #20 reset_n = 1;
  end
endmodule
