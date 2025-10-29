// rv_csr_defines.vh
// RISC-V CSR Constants and Definitions
//
// This header file contains all CSR-related constants shared across the core.
// Single source of truth for CSR addresses, bit positions, privilege modes,
// and exception/interrupt cause codes.
//
// Reference: RISC-V Privileged Specification v1.12
//
// Usage: `include "config/rv_csr_defines.vh"

`ifndef RV_CSR_DEFINES_VH
`define RV_CSR_DEFINES_VH

// =============================================================================
// Privilege Mode Encodings (RISC-V Spec Section 1.2)
// =============================================================================
// Note: Privilege level 2'b10 is reserved for future use

localparam [1:0] PRIV_U_MODE = 2'b00;  // User mode
localparam [1:0] PRIV_S_MODE = 2'b01;  // Supervisor mode
localparam [1:0] PRIV_M_MODE = 2'b11;  // Machine mode

// =============================================================================
// Machine-Level CSR Addresses (RISC-V Spec Section 2)
// =============================================================================

// Machine Information Registers (read-only)
localparam [11:0] CSR_MVENDORID = 12'hF11;  // Vendor ID
localparam [11:0] CSR_MARCHID   = 12'hF12;  // Architecture ID
localparam [11:0] CSR_MIMPID    = 12'hF13;  // Implementation ID
localparam [11:0] CSR_MHARTID   = 12'hF14;  // Hardware thread ID

// Machine Trap Setup
localparam [11:0] CSR_MSTATUS   = 12'h300;  // Machine status register
localparam [11:0] CSR_MISA      = 12'h301;  // ISA and extensions
localparam [11:0] CSR_MEDELEG   = 12'h302;  // Machine exception delegation
localparam [11:0] CSR_MIDELEG   = 12'h303;  // Machine interrupt delegation
localparam [11:0] CSR_MIE       = 12'h304;  // Machine interrupt enable
localparam [11:0] CSR_MTVEC     = 12'h305;  // Machine trap-handler base address

// Machine Trap Handling
localparam [11:0] CSR_MSCRATCH  = 12'h340;  // Machine scratch register
localparam [11:0] CSR_MEPC      = 12'h341;  // Machine exception program counter
localparam [11:0] CSR_MCAUSE    = 12'h342;  // Machine trap cause
localparam [11:0] CSR_MTVAL     = 12'h343;  // Machine bad address or instruction
localparam [11:0] CSR_MIP       = 12'h344;  // Machine interrupt pending

// =============================================================================
// Supervisor-Level CSR Addresses (RISC-V Spec Section 4)
// =============================================================================

// Supervisor Trap Setup
localparam [11:0] CSR_SSTATUS   = 12'h100;  // Supervisor status register
localparam [11:0] CSR_SIE       = 12'h104;  // Supervisor interrupt enable
localparam [11:0] CSR_STVEC     = 12'h105;  // Supervisor trap-handler base address

// Supervisor Trap Handling
localparam [11:0] CSR_SSCRATCH  = 12'h140;  // Supervisor scratch register
localparam [11:0] CSR_SEPC      = 12'h141;  // Supervisor exception program counter
localparam [11:0] CSR_SCAUSE    = 12'h142;  // Supervisor trap cause
localparam [11:0] CSR_STVAL     = 12'h143;  // Supervisor bad address or instruction
localparam [11:0] CSR_SIP       = 12'h144;  // Supervisor interrupt pending

// Supervisor Address Translation and Protection
localparam [11:0] CSR_SATP      = 12'h180;  // Supervisor address translation and protection

// =============================================================================
// Floating-Point CSR Addresses (RISC-V Spec Section 11.2)
// =============================================================================

localparam [11:0] CSR_FFLAGS    = 12'h001;  // Floating-point exception flags
localparam [11:0] CSR_FRM       = 12'h002;  // Floating-point rounding mode
localparam [11:0] CSR_FCSR      = 12'h003;  // Floating-point control and status register

// =============================================================================
// CSR Instruction Opcodes (funct3 field)
// =============================================================================

localparam [2:0] CSR_RW  = 3'b001;  // CSRRW  - Read/Write
localparam [2:0] CSR_RS  = 3'b010;  // CSRRS  - Read and Set bits
localparam [2:0] CSR_RC  = 3'b011;  // CSRRC  - Read and Clear bits
localparam [2:0] CSR_RWI = 3'b101;  // CSRRWI - Read/Write Immediate
localparam [2:0] CSR_RSI = 3'b110;  // CSRRSI - Read and Set bits Immediate
localparam [2:0] CSR_RCI = 3'b111;  // CSRRCI - Read and Clear bits Immediate

// =============================================================================
// MSTATUS/SSTATUS Bit Positions (RISC-V Spec Section 3.1.6)
// =============================================================================

// Interrupt Enable bits
localparam MSTATUS_SIE_BIT  = 1;   // Supervisor Interrupt Enable
localparam MSTATUS_MIE_BIT  = 3;   // Machine Interrupt Enable

// Previous Interrupt Enable bits
localparam MSTATUS_SPIE_BIT = 5;   // Supervisor Previous Interrupt Enable
localparam MSTATUS_MPIE_BIT = 7;   // Machine Previous Interrupt Enable

// Previous Privilege Mode bits
localparam MSTATUS_SPP_BIT  = 8;   // Supervisor Previous Privilege (1 bit: 0=U, 1=S)
localparam MSTATUS_MPP_LSB  = 11;  // Machine Previous Privilege [11:12] (2 bits)
localparam MSTATUS_MPP_MSB  = 12;

// Floating-Point Unit Status bits
localparam MSTATUS_FS_LSB   = 13;  // FPU status [13:14] (2 bits)
localparam MSTATUS_FS_MSB   = 14;
// FS encoding: 00=Off, 01=Initial, 10=Clean, 11=Dirty

// Memory Access Control bits
localparam MSTATUS_SUM_BIT  = 18;  // Supervisor User Memory access
localparam MSTATUS_MXR_BIT  = 19;  // Make eXecutable Readable

// =============================================================================
// Exception Cause Codes (RISC-V Spec Table 3.6)
// =============================================================================
// Note: mcause[XLEN-1] = 1 for interrupts, 0 for exceptions
// These codes go in mcause[XLEN-2:0] when mcause[XLEN-1] = 0

localparam [4:0] CAUSE_INST_ADDR_MISALIGNED  = 5'd0;   // Instruction address misaligned
localparam [4:0] CAUSE_INST_ACCESS_FAULT     = 5'd1;   // Instruction access fault
localparam [4:0] CAUSE_ILLEGAL_INST          = 5'd2;   // Illegal instruction
localparam [4:0] CAUSE_BREAKPOINT            = 5'd3;   // Breakpoint
localparam [4:0] CAUSE_LOAD_ADDR_MISALIGNED  = 5'd4;   // Load address misaligned
localparam [4:0] CAUSE_LOAD_ACCESS_FAULT     = 5'd5;   // Load access fault
localparam [4:0] CAUSE_STORE_ADDR_MISALIGNED = 5'd6;   // Store/AMO address misaligned
localparam [4:0] CAUSE_STORE_ACCESS_FAULT    = 5'd7;   // Store/AMO access fault
localparam [4:0] CAUSE_ECALL_FROM_U_MODE     = 5'd8;   // Environment call from U-mode
localparam [4:0] CAUSE_ECALL_FROM_S_MODE     = 5'd9;   // Environment call from S-mode
localparam [4:0] CAUSE_ECALL_FROM_M_MODE     = 5'd11;  // Environment call from M-mode
localparam [4:0] CAUSE_INST_PAGE_FAULT       = 5'd12;  // Instruction page fault
localparam [4:0] CAUSE_LOAD_PAGE_FAULT       = 5'd13;  // Load page fault
localparam [4:0] CAUSE_STORE_PAGE_FAULT      = 5'd15;  // Store/AMO page fault

// =============================================================================
// Interrupt Cause Codes (RISC-V Spec Table 3.6)
// =============================================================================
// Note: mcause[XLEN-1] = 1 for interrupts
// These codes go in mcause[XLEN-2:0] when mcause[XLEN-1] = 1

localparam [4:0] INT_SUPERVISOR_SOFTWARE  = 5'd1;   // Supervisor software interrupt
localparam [4:0] INT_MACHINE_SOFTWARE     = 5'd3;   // Machine software interrupt
localparam [4:0] INT_SUPERVISOR_TIMER     = 5'd5;   // Supervisor timer interrupt
localparam [4:0] INT_MACHINE_TIMER        = 5'd7;   // Machine timer interrupt
localparam [4:0] INT_SUPERVISOR_EXTERNAL  = 5'd9;   // Supervisor external interrupt
localparam [4:0] INT_MACHINE_EXTERNAL     = 5'd11;  // Machine external interrupt

`endif // RV_CSR_DEFINES_VH
