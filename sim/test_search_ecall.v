`timescale 1ns/1ps

module test_search_ecall;
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
      
      // Check opcode field for SYSTEM instructions (opcode = 0x73)
      if ((instr_out & 32'h7F) == 32'h73) begin
        $display("Cycle %0d: PC=%h instr=%h (SYSTEM instruction)", cycle_count, pc_out, instr_out);
        
        // Check if it's ECALL (funct3=0, funct7=0, imm[31:20]=0)
        if (instr_out[31:7] == 25'h0) begin
          $display("  -> This is ECALL!");
          $display("  -> x3 (gp) = %h", dut.regfile.registers[3]);
          $finish;
        end
      end
      
      if (cycle_count >= 500) $finish;
    end
  end

  initial begin
    #20 reset_n = 1;
  end
endmodule
