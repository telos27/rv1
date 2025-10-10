`timescale 1ns/1ps

module test_exception_at_e8;
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

      if (cycle_count >= 40 && cycle_count <= 44) begin
        $display("Cycle %0d: PC=%h if_instr=%h", cycle_count, pc_out, instr_out);
        $display("  idex_instr=%h idex_csr_addr=%h idex_csr_we=%b",
                 dut.idex_instruction, dut.idex_csr_addr, dut.idex_csr_we);
        $display("  ex_illegal_csr=%b idex_illegal_inst=%b idex_valid=%b",
                 dut.ex_illegal_csr, dut.idex_illegal_inst, dut.idex_valid);
        $display("  exception=%b exception_code=%h", dut.exception, dut.exception_code);
        $display("");
      end

      if (cycle_count >= 46) $finish;
    end
  end

  initial begin
    #20 reset_n = 1;
  end
endmodule
