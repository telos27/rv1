// tb_simple_with_program.v - Testbench with actual program
// Loads test_simple.hex and executes it

`timescale 1ns / 1ps

module tb_simple_with_program;

  reg clk;
  reg reset_n;
  wire [31:0] pc_out;
  wire [31:0] instr_out;

  // Clock generation (10ns period = 100MHz)
  always #5 clk = ~clk;

  // DUT instantiation
  rv32i_core #(
    .IMEM_SIZE(4096),
    .DMEM_SIZE(4096),
    .MEM_FILE("tests/asm/test_simple.hex")
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    .pc_out(pc_out),
    .instr_out(instr_out)
  );

  // Instruction decoder (for display)
  reg [6:0] opcode;
  reg [4:0] rd, rs1, rs2;
  reg [2:0] funct3;
  reg [6:0] funct7;

  always @(*) begin
    opcode = instr_out[6:0];
    rd = instr_out[11:7];
    funct3 = instr_out[14:12];
    rs1 = instr_out[19:15];
    rs2 = instr_out[24:20];
    funct7 = instr_out[31:25];
  end

  // Test program monitor
  integer cycle_count;
  reg [31:0] prev_pc;

  initial begin
    // Initialize
    clk = 0;
    reset_n = 0;
    cycle_count = 0;
    prev_pc = 32'hFFFFFFFF;

    // Dump waveform
    $dumpfile("simple_program.vcd");
    $dumpvars(0, tb_simple_with_program);
    $dumpvars(0, dut.register_file_inst);

    // Reset
    #10 reset_n = 1;
    #5;

    $display("\n=== Simple Program Execution Test ===\n");
    $display("Loaded program: tests/asm/test_simple.hex");
    $display("\nTime  | Cycle | PC       | Instruction | Opcode | Decoded");
    $display("------|-------|----------|-------------|--------|---------------------------");

    // Monitor execution
    repeat(30) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;

      // Display instruction info
      if (pc_out != prev_pc) begin
        $write("%5t | %5d | %08h | %08h    | %02h     | ",
               $time, cycle_count, pc_out, instr_out, opcode);

        // Decode instruction
        case (opcode)
          7'b0110011: begin // R-type
            case (funct3)
              3'b000: $display("ADD  x%0d, x%0d, x%0d", rd, rs1, rs2);
              3'b000: if (funct7[5]) $display("SUB  x%0d, x%0d, x%0d", rd, rs1, rs2);
              3'b111: $display("AND  x%0d, x%0d, x%0d", rd, rs1, rs2);
              3'b110: $display("OR   x%0d, x%0d, x%0d", rd, rs1, rs2);
              default: $display("R-type (funct3=%b)", funct3);
            endcase
          end
          7'b0010011: begin // I-type (immediate)
            case (funct3)
              3'b000: $display("ADDI x%0d, x%0d, %0d", rd, rs1, $signed(instr_out[31:20]));
              3'b111: $display("ANDI x%0d, x%0d, 0x%03h", rd, rs1, instr_out[31:20]);
              3'b110: $display("ORI  x%0d, x%0d, 0x%03h", rd, rs1, instr_out[31:20]);
              default: $display("I-type (funct3=%b)", funct3);
            endcase
          end
          7'b1100011: begin // Branch
            case (funct3)
              3'b000: $display("BEQ  x%0d, x%0d, offset=%0d", rs1, rs2,
                      $signed({instr_out[31], instr_out[7], instr_out[30:25], instr_out[11:8], 1'b0}));
              default: $display("Branch (funct3=%b)", funct3);
            endcase
          end
          7'b0000000: $display("(Invalid/NOP)");
          default: $display("Unknown opcode");
        endcase

        prev_pc = pc_out;
      end
    end

    $display("\n=== Execution Complete ===");
    $display("\nRegister File Final State:");
    $display("x10 (a0) = 0x%08h (%0d)", dut.register_file_inst.registers[10], $signed(dut.register_file_inst.registers[10]));
    $display("x11 (a1) = 0x%08h (%0d)", dut.register_file_inst.registers[11], $signed(dut.register_file_inst.registers[11]));
    $display("x12 (a2) = 0x%08h (%0d)", dut.register_file_inst.registers[12], $signed(dut.register_file_inst.registers[12]));
    $display("x13 (a3) = 0x%08h (%0d)", dut.register_file_inst.registers[13], $signed(dut.register_file_inst.registers[13]));
    $display("x14 (a4) = 0x%08h (%0d)", dut.register_file_inst.registers[14], $signed(dut.register_file_inst.registers[14]));
    $display("x15 (a5) = 0x%08h (%0d)", dut.register_file_inst.registers[15], $signed(dut.register_file_inst.registers[15]));

    $display("\n=== Test Complete ===");
    $display("Waveform saved to: simple_program.vcd");
    $display("View with: gtkwave simple_program.vcd\n");

    $finish;
  end

  // Timeout watchdog
  initial begin
    #10000;
    $display("\nWARNING: Test timeout at %0t", $time);
    $finish;
  end

endmodule
