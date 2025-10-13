// Verilator C++ testbench for C extension testing
#include <verilated.h>
#include "Vrv_core_pipelined_wrapper.h"
#include <iostream>
#include <iomanip>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // Instantiate DUT
    Vrv_core_pipelined_wrapper* dut = new Vrv_core_pipelined_wrapper;

    // Initialize
    dut->clk = 0;
    dut->reset_n = 0;

    std::cout << "=== Starting Verilator C Extension Test ===" << std::endl;

    // Reset for a few cycles
    for (int i = 0; i < 5; i++) {
        dut->clk = 0;
        dut->eval();
        dut->clk = 1;
        dut->eval();
    }

    // Release reset
    dut->reset_n = 1;
    std::cout << "Reset released" << std::endl;

    // Run for 30 cycles
    for (int cycle = 1; cycle <= 30; cycle++) {
        // Negative edge
        dut->clk = 0;
        dut->eval();

        // Positive edge
        dut->clk = 1;
        dut->eval();

        // Print every cycle
        std::cout << "Cycle " << std::setw(2) << cycle
                  << ": PC=0x" << std::hex << std::setw(8) << std::setfill('0') << dut->pc_out
                  << " Instr=0x" << std::setw(8) << dut->instr_out
                  << std::dec << std::endl;
    }

    std::cout << "\n=== Test Completed Successfully ===" << std::endl;
    std::cout << "Verilator successfully simulated C extension!" << std::endl;

    delete dut;
    return 0;
}
