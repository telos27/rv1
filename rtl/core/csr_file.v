// CSR (Control and Status Register) File
// Implements Machine-mode CSRs for RISC-V
// Supports CSR instructions: CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
// Supports trap handling: exception entry and MRET
// Parameterized for RV32/RV64

`include "config/rv_config.vh"

module csr_file #(
  parameter XLEN = `XLEN
) (
  input  wire             clk,
  input  wire             reset_n,

  // CSR read/write interface
  input  wire [11:0]      csr_addr,       // CSR address
  input  wire [XLEN-1:0]  csr_wdata,      // Write data (from rs1 or uimm)
  input  wire [2:0]       csr_op,         // CSR operation (funct3)
  input  wire             csr_we,         // CSR write enable
  output reg  [XLEN-1:0]  csr_rdata,      // Read data

  // Trap handling interface
  input  wire             trap_entry,     // Trap is occurring
  input  wire [XLEN-1:0]  trap_pc,        // PC to save in mepc
  input  wire [4:0]       trap_cause,     // Exception cause code
  input  wire [XLEN-1:0]  trap_val,       // mtval value (bad address, instruction, etc.)
  output wire [XLEN-1:0]  trap_vector,    // mtvec value (trap handler address)

  // MRET (trap return)
  input  wire             mret,           // MRET instruction
  output wire [XLEN-1:0]  mepc_out,       // mepc for return

  // SRET (supervisor trap return)
  input  wire             sret,           // SRET instruction
  output wire [XLEN-1:0]  sepc_out,       // sepc for return

  // Status outputs
  output wire             mstatus_mie,    // Global interrupt enable
  output wire             illegal_csr,    // Invalid CSR access

  // Privilege mode tracking (Phase 1)
  input  wire [1:0]       current_priv,   // Current privilege mode
  output wire [1:0]       trap_target_priv, // Target privilege for trap
  output wire [1:0]       mpp_out,        // Machine Previous Privilege
  output wire             spp_out,        // Supervisor Previous Privilege

  // MMU-related status outputs
  output wire [XLEN-1:0]  satp_out,       // SATP register (for MMU)
  output wire             mstatus_sum,    // SUM bit (for MMU)
  output wire             mstatus_mxr,    // MXR bit (for MMU)

  // Floating-Point CSR outputs
  output wire [2:0]       frm_out,        // FP rounding mode (for FPU)
  output wire [4:0]       fflags_out,     // FP exception flags (for reading)

  // Floating-Point flag accumulation (from FPU in WB stage)
  input  wire             fflags_we,      // Write enable for flag accumulation
  input  wire [4:0]       fflags_in       // Exception flags from FPU
);

  // =========================================================================
  // CSR Address Definitions
  // =========================================================================

  // Machine Information Registers (read-only)
  localparam CSR_MVENDORID = 12'hF11;
  localparam CSR_MARCHID   = 12'hF12;
  localparam CSR_MIMPID    = 12'hF13;
  localparam CSR_MHARTID   = 12'hF14;

  // Machine Trap Setup
  localparam CSR_MSTATUS   = 12'h300;
  localparam CSR_MISA      = 12'h301;
  localparam CSR_MIE       = 12'h304;
  localparam CSR_MTVEC     = 12'h305;

  // Machine Trap Handling
  localparam CSR_MSCRATCH  = 12'h340;
  localparam CSR_MEPC      = 12'h341;
  localparam CSR_MCAUSE    = 12'h342;
  localparam CSR_MTVAL     = 12'h343;
  localparam CSR_MIP       = 12'h344;

  // Supervisor Trap Setup
  localparam CSR_SSTATUS   = 12'h100;
  localparam CSR_SIE       = 12'h104;
  localparam CSR_STVEC     = 12'h105;

  // Supervisor Trap Handling
  localparam CSR_SSCRATCH  = 12'h140;
  localparam CSR_SEPC      = 12'h141;
  localparam CSR_SCAUSE    = 12'h142;
  localparam CSR_STVAL     = 12'h143;
  localparam CSR_SIP       = 12'h144;

  // Supervisor Address Translation and Protection
  localparam CSR_SATP      = 12'h180;

  // Machine Trap Delegation
  localparam CSR_MEDELEG   = 12'h302;
  localparam CSR_MIDELEG   = 12'h303;

  // Floating-Point CSRs (F/D extension)
  localparam CSR_FFLAGS    = 12'h001;  // Floating-point exception flags
  localparam CSR_FRM       = 12'h002;  // Floating-point rounding mode
  localparam CSR_FCSR      = 12'h003;  // Full floating-point CSR

  // CSR Operation Encodings (funct3)
  localparam CSR_RW  = 3'b001;  // CSRRW
  localparam CSR_RS  = 3'b010;  // CSRRS
  localparam CSR_RC  = 3'b011;  // CSRRC
  localparam CSR_RWI = 3'b101;  // CSRRWI
  localparam CSR_RSI = 3'b110;  // CSRRSI
  localparam CSR_RCI = 3'b111;  // CSRRCI

  // =========================================================================
  // CSR Registers
  // =========================================================================

  // Machine Status Register (mstatus)
  // Implements fields for M-mode and S-mode
  reg        mstatus_sie_r;   // [1] - Supervisor Interrupt Enable
  reg        mstatus_mie_r;   // [3] - Machine Interrupt Enable
  reg        mstatus_spie_r;  // [5] - Supervisor Previous Interrupt Enable
  reg        mstatus_mpie_r;  // [7] - Machine Previous Interrupt Enable
  reg        mstatus_spp_r;   // [8] - Supervisor Previous Privilege (0=U, 1=S)
  reg [1:0]  mstatus_mpp_r;   // [12:11] - Machine Previous Privilege (00=U, 01=S, 11=M)
  reg        mstatus_sum_r;   // [18] - Supervisor User Memory access
  reg        mstatus_mxr_r;   // [19] - Make eXecutable Readable

  // Machine ISA Register (misa) - read-only
  // RV32: [31:30] = 2'b01 (MXL=1), [25:0] = extensions (bit 8 = I)
  // RV64: [63:62] = 2'b10 (MXL=2), [25:0] = extensions (bit 8 = I)
  generate
    if (XLEN == 32) begin : gen_misa_rv32
      wire [31:0] misa = {2'b01, 4'b0, 26'b00000000000000000100000000};
    end else begin : gen_misa_rv64
      wire [63:0] misa = {2'b10, 36'b0, 26'b00000000000000000100000000};
    end
  endgenerate

  // Machine Interrupt Enable (mie) - not fully implemented yet
  reg [XLEN-1:0] mie_r;

  // Machine Trap-Vector Base Address (mtvec)
  reg [XLEN-1:0] mtvec_r;

  // Machine Scratch Register (mscratch) - software use
  reg [XLEN-1:0] mscratch_r;

  // Machine Exception Program Counter (mepc)
  reg [XLEN-1:0] mepc_r;

  // Machine Cause Register (mcause)
  // [XLEN-1] = interrupt flag, [XLEN-2:0] = exception code
  reg [XLEN-1:0] mcause_r;

  // Machine Trap Value (mtval)
  reg [XLEN-1:0] mtval_r;

  // Machine Interrupt Pending (mip) - not fully implemented yet
  reg [XLEN-1:0] mip_r;

  // Floating-Point CSRs
  reg [4:0] fflags_r;  // Floating-point exception flags: [4] NV, [3] DZ, [2] OF, [1] UF, [0] NX
  reg [2:0] frm_r;     // Floating-point rounding mode

  // Supervisor Address Translation and Protection (SATP)
  reg [XLEN-1:0] satp_r;

  // Supervisor Trap Handling Registers
  reg [XLEN-1:0] stvec_r;      // Supervisor trap vector
  reg [XLEN-1:0] sscratch_r;   // Supervisor scratch register
  reg [XLEN-1:0] sepc_r;       // Supervisor exception PC
  reg [XLEN-1:0] scause_r;     // Supervisor exception cause
  reg [XLEN-1:0] stval_r;      // Supervisor trap value

  // Machine Trap Delegation Registers
  reg [XLEN-1:0] medeleg_r;    // Machine exception delegation to S-mode
  reg [XLEN-1:0] mideleg_r;    // Machine interrupt delegation to S-mode

  // =========================================================================
  // Read-Only CSRs (hardwired)
  // =========================================================================

  // Vendor ID: 0 = not implemented
  wire [31:0] mvendorid = 32'h0000_0000;

  // Architecture ID: 0 = not implemented
  wire [31:0] marchid = 32'h0000_0000;

  // Implementation ID: 1 = RV1 implementation
  wire [31:0] mimpid = 32'h0000_0001;

  // Hardware Thread ID: 0 = single-threaded
  wire [31:0] mhartid = 32'h0000_0000;

  // =========================================================================
  // CSR Read Logic
  // =========================================================================

  // Construct mstatus from individual fields
  // RV32: Standard layout with fields at [19:18], [12:11], [8], [7], [5], [3], [1]
  // RV64: Same fields, but wider register (upper bits reserved)
  generate
    if (XLEN == 32) begin : gen_mstatus_rv32
      wire [31:0] mstatus_value = {
        12'b0,                // [31:20] Reserved
        mstatus_mxr_r,        // [19] MXR
        mstatus_sum_r,        // [18] SUM
        5'b0,                 // [17:13] Reserved
        mstatus_mpp_r,        // [12:11] MPP
        2'b0,                 // [10:9] Reserved
        mstatus_spp_r,        // [8] SPP
        mstatus_mpie_r,       // [7] MPIE
        1'b0,                 // [6] Reserved
        mstatus_spie_r,       // [5] SPIE
        1'b0,                 // [4] Reserved
        mstatus_mie_r,        // [3] MIE
        1'b0,                 // [2] Reserved
        mstatus_sie_r,        // [1] SIE
        1'b0                  // [0] Reserved
      };
    end else begin : gen_mstatus_rv64
      wire [63:0] mstatus_value = {
        44'b0,                // [63:20] Reserved
        mstatus_mxr_r,        // [19] MXR
        mstatus_sum_r,        // [18] SUM
        5'b0,                 // [17:13] Reserved
        mstatus_mpp_r,        // [12:11] MPP
        2'b0,                 // [10:9] Reserved
        mstatus_spp_r,        // [8] SPP
        mstatus_mpie_r,       // [7] MPIE
        1'b0,                 // [6] Reserved
        mstatus_spie_r,       // [5] SPIE
        1'b0,                 // [4] Reserved
        mstatus_mie_r,        // [3] MIE
        1'b0,                 // [2] Reserved
        mstatus_sie_r,        // [1] SIE
        1'b0                  // [0] Reserved
      };
    end
  endgenerate

  // Construct sstatus as read-only subset of mstatus
  // SSTATUS provides restricted view: only S-mode relevant fields visible
  generate
    if (XLEN == 32) begin : gen_sstatus_rv32
      wire [31:0] sstatus_value = {
        12'b0,                // [31:20] Reserved
        mstatus_mxr_r,        // [19] MXR
        mstatus_sum_r,        // [18] SUM
        5'b0,                 // [17:13] Reserved
        2'b00,                // [12:11] Reserved (MPP not visible in S-mode)
        2'b0,                 // [10:9] Reserved
        mstatus_spp_r,        // [8] SPP
        1'b0,                 // [7] Reserved (MPIE not visible in S-mode)
        1'b0,                 // [6] Reserved
        mstatus_spie_r,       // [5] SPIE
        1'b0,                 // [4] Reserved
        1'b0,                 // [3] Reserved (MIE not visible in S-mode)
        1'b0,                 // [2] Reserved
        mstatus_sie_r,        // [1] SIE
        1'b0                  // [0] Reserved
      };
    end else begin : gen_sstatus_rv64
      wire [63:0] sstatus_value = {
        44'b0,                // [63:20] Reserved
        mstatus_mxr_r,        // [19] MXR
        mstatus_sum_r,        // [18] SUM
        5'b0,                 // [17:13] Reserved
        2'b00,                // [12:11] Reserved (MPP not visible)
        2'b0,                 // [10:9] Reserved
        mstatus_spp_r,        // [8] SPP
        1'b0,                 // [7] Reserved (MPIE not visible)
        1'b0,                 // [6] Reserved
        mstatus_spie_r,       // [5] SPIE
        1'b0,                 // [4] Reserved
        1'b0,                 // [3] Reserved (MIE not visible)
        1'b0,                 // [2] Reserved
        mstatus_sie_r,        // [1] SIE
        1'b0                  // [0] Reserved
      };
    end
  endgenerate

  // SIE and SIP are subsets of MIE and MIP
  // Supervisor-level interrupts use bits: SEIP(9), STIP(5), SSIP(1)
  wire [XLEN-1:0] sie_value = mie_r & {{(XLEN-10){1'b0}}, 1'b1, 3'b0, 1'b1, 3'b0, 1'b1, 1'b0};  // Mask bits [9,5,1]
  wire [XLEN-1:0] sip_value = mip_r & {{(XLEN-10){1'b0}}, 1'b1, 3'b0, 1'b1, 3'b0, 1'b1, 1'b0};  // Mask bits [9,5,1]

  // CSR read multiplexer
  // Note: Access to generate block signals must be inside generate blocks for Verilator
  wire [XLEN-1:0] mstatus_value;
  wire [XLEN-1:0] sstatus_value;
  wire [XLEN-1:0] misa_value;
  generate
    if (XLEN == 32) begin : gen_csr_access
      assign mstatus_value = gen_mstatus_rv32.mstatus_value;
      assign sstatus_value = gen_sstatus_rv32.sstatus_value;
      assign misa_value = gen_misa_rv32.misa;
    end else begin : gen_csr_access
      assign mstatus_value = gen_mstatus_rv64.mstatus_value;
      assign sstatus_value = gen_sstatus_rv64.sstatus_value;
      assign misa_value = gen_misa_rv64.misa;
    end
  endgenerate

  always @(*) begin
    case (csr_addr)
      // Machine-mode CSRs
      CSR_MSTATUS:   csr_rdata = mstatus_value;
      CSR_MISA:      csr_rdata = misa_value;
      CSR_MEDELEG:   csr_rdata = medeleg_r;
      CSR_MIDELEG:   csr_rdata = mideleg_r;
      CSR_MIE:       csr_rdata = mie_r;
      CSR_MTVEC:     csr_rdata = mtvec_r;
      CSR_MSCRATCH:  csr_rdata = mscratch_r;
      CSR_MEPC:      csr_rdata = mepc_r;
      CSR_MCAUSE:    csr_rdata = mcause_r;
      CSR_MTVAL:     csr_rdata = mtval_r;
      CSR_MIP:       csr_rdata = mip_r;
      CSR_MVENDORID: csr_rdata = {{(XLEN-32){1'b0}}, mvendorid};  // Zero-extend to XLEN
      CSR_MARCHID:   csr_rdata = {{(XLEN-32){1'b0}}, marchid};    // Zero-extend to XLEN
      CSR_MIMPID:    csr_rdata = {{(XLEN-32){1'b0}}, mimpid};     // Zero-extend to XLEN
      CSR_MHARTID:   csr_rdata = {{(XLEN-32){1'b0}}, mhartid};    // Zero-extend to XLEN
      // Supervisor-mode CSRs
      CSR_SSTATUS:   csr_rdata = sstatus_value;
      CSR_SIE:       csr_rdata = sie_value;
      CSR_STVEC:     csr_rdata = stvec_r;
      CSR_SSCRATCH:  csr_rdata = sscratch_r;
      CSR_SEPC:      csr_rdata = sepc_r;
      CSR_SCAUSE:    csr_rdata = scause_r;
      CSR_STVAL:     csr_rdata = stval_r;
      CSR_SIP:       csr_rdata = sip_value;
      CSR_SATP:      csr_rdata = satp_r;
      // Floating-point CSRs
      CSR_FFLAGS:    csr_rdata = {{(XLEN-5){1'b0}}, fflags_r};    // Zero-extend to XLEN
      CSR_FRM:       csr_rdata = {{(XLEN-3){1'b0}}, frm_r};       // Zero-extend to XLEN
      CSR_FCSR:      csr_rdata = {{(XLEN-8){1'b0}}, frm_r, fflags_r};  // {frm[7:5], fflags[4:0]}
      default:       csr_rdata = {XLEN{1'b0}};  // Return 0 for unknown CSRs
    endcase
  end

  // =========================================================================
  // CSR Write Logic
  // =========================================================================

  // =========================================================================
  // CSR Privilege Checking (Phase 2)
  // =========================================================================
  // CSR address encoding: [11:10] = read-only flag, [9:8] = privilege level
  // 00 = User, 01 = Supervisor, 10 = Reserved, 11 = Machine

  wire [1:0] csr_priv_level = csr_addr[9:8];  // Extract privilege level from address
  wire       csr_read_only_bit = (csr_addr[11:10] == 2'b11);  // Read-only if top 2 bits are 11

  // Check if current privilege can access this CSR
  // Rule: Current privilege must be >= CSR privilege level
  wire csr_priv_ok = (current_priv >= csr_priv_level);

  // Determine if CSR is read-only (either by address encoding or specific CSR)
  wire csr_read_only = csr_read_only_bit ||
                       (csr_addr == CSR_MISA) ||
                       (csr_addr == CSR_MVENDORID) ||
                       (csr_addr == CSR_MARCHID) ||
                       (csr_addr == CSR_MIMPID) ||
                       (csr_addr == CSR_MHARTID);

  // Test/Debug CSRs (used by some test frameworks for output)
  // Addresses 0x700-0x7FF are sometimes used for test output
  wire csr_is_test = (csr_addr[11:8] == 4'b0111);  // 0x700-0x7FF range

  // Determine if CSR exists (is valid)
  // Check if CSR is in our implemented set
  wire csr_exists = (csr_addr == CSR_MSTATUS) ||
                    (csr_addr == CSR_MISA) ||
                    (csr_addr == CSR_MEDELEG) ||
                    (csr_addr == CSR_MIDELEG) ||
                    (csr_addr == CSR_MIE) ||
                    (csr_addr == CSR_MTVEC) ||
                    (csr_addr == CSR_MSCRATCH) ||
                    (csr_addr == CSR_MEPC) ||
                    (csr_addr == CSR_MCAUSE) ||
                    (csr_addr == CSR_MTVAL) ||
                    (csr_addr == CSR_MIP) ||
                    (csr_addr == CSR_MVENDORID) ||
                    (csr_addr == CSR_MARCHID) ||
                    (csr_addr == CSR_MIMPID) ||
                    (csr_addr == CSR_MHARTID) ||
                    (csr_addr == CSR_SSTATUS) ||
                    (csr_addr == CSR_SIE) ||
                    (csr_addr == CSR_STVEC) ||
                    (csr_addr == CSR_SSCRATCH) ||
                    (csr_addr == CSR_SEPC) ||
                    (csr_addr == CSR_SCAUSE) ||
                    (csr_addr == CSR_STVAL) ||
                    (csr_addr == CSR_SIP) ||
                    (csr_addr == CSR_SATP) ||
                    (csr_addr == CSR_FFLAGS) ||
                    (csr_addr == CSR_FRM) ||
                    (csr_addr == CSR_FCSR) ||
                    csr_is_test;  // Accept test CSRs

  // Illegal CSR access conditions:
  // 1. CSR doesn't exist
  // 2. Privilege level too low to access CSR
  // 3. Attempting to write to read-only CSR
  //
  // Note: We only check writes here (csr_we). Read privilege is implicitly checked
  // because CSR instructions that read also write (even CSRRS/CSRRC with rs1=x0).
  // The control unit sets csr_we=1 for all CSR instructions, so privilege is always checked.
  assign illegal_csr = csr_we && ((!csr_exists) || (!csr_priv_ok) || csr_read_only);

  // Compute CSR write value based on operation
  reg [XLEN-1:0] csr_write_value;
  always @(*) begin
    case (csr_op)
      CSR_RW, CSR_RWI: csr_write_value = csr_wdata;                    // Write
      CSR_RS, CSR_RSI: csr_write_value = csr_rdata | csr_wdata;        // Set bits
      CSR_RC, CSR_RCI: csr_write_value = csr_rdata & ~csr_wdata;       // Clear bits
      default:         csr_write_value = csr_rdata;                    // No change
    endcase
  end

  // CSR write (synchronous)
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset all CSRs
      mstatus_sie_r  <= 1'b0;           // Supervisor interrupt disabled
      mstatus_mie_r  <= 1'b0;           // Machine interrupt disabled
      mstatus_spie_r <= 1'b0;           // Supervisor previous IE = 0
      mstatus_mpie_r <= 1'b0;           // Machine previous IE = 0
      mstatus_spp_r  <= 1'b0;           // Supervisor previous privilege = U
      mstatus_mpp_r  <= 2'b11;          // Machine previous privilege = M-mode
      mstatus_sum_r  <= 1'b0;           // Supervisor User Memory access disabled
      mstatus_mxr_r  <= 1'b0;           // Make eXecutable Readable disabled
      mie_r          <= {XLEN{1'b0}};
      mtvec_r        <= {XLEN{1'b0}};   // Trap vector at address 0
      mscratch_r     <= {XLEN{1'b0}};
      mepc_r         <= {XLEN{1'b0}};
      mcause_r       <= {XLEN{1'b0}};
      mtval_r        <= {XLEN{1'b0}};
      mip_r          <= {XLEN{1'b0}};
      satp_r         <= {XLEN{1'b0}};   // No translation (bare mode)
      // Reset floating-point CSRs
      fflags_r       <= 5'b0;            // No exceptions
      frm_r          <= 3'b000;          // RNE (Round to Nearest, ties to Even)
      // Reset supervisor CSRs
      stvec_r        <= {XLEN{1'b0}};   // Supervisor trap vector at address 0
      sscratch_r     <= {XLEN{1'b0}};
      sepc_r         <= {XLEN{1'b0}};
      scause_r       <= {XLEN{1'b0}};
      stval_r        <= {XLEN{1'b0}};
      // Reset trap delegation registers
      medeleg_r      <= {XLEN{1'b0}};   // No delegation by default
      mideleg_r      <= {XLEN{1'b0}};   // No delegation by default
    end else begin
      // Trap entry has priority over CSR writes and SRET/MRET
      if (trap_entry) begin
        // Determine target privilege level
        if (trap_target_priv == 2'b11) begin
          // Machine-mode trap
          mepc_r  <= trap_pc;
          mcause_r <= {{(XLEN-5){1'b0}}, trap_cause};
          mtval_r  <= trap_val;
          mstatus_mpie_r <= mstatus_mie_r;  // Save current MIE
          mstatus_mie_r  <= 1'b0;           // Disable interrupts
          mstatus_mpp_r  <= current_priv;   // Save current privilege
        end else if (trap_target_priv == 2'b01) begin
          // Supervisor-mode trap
          sepc_r  <= trap_pc;
          scause_r <= {{(XLEN-5){1'b0}}, trap_cause};
          stval_r  <= trap_val;
          mstatus_spie_r <= mstatus_sie_r;  // Save current SIE
          mstatus_sie_r  <= 1'b0;           // Disable supervisor interrupts
          mstatus_spp_r  <= current_priv[0]; // Save current privilege (0=U, 1=S)
        end
      end else if (mret) begin
        // MRET: Return from machine-mode trap
        mstatus_mie_r  <= mstatus_mpie_r;   // Restore interrupt enable
        mstatus_mpie_r <= 1'b1;             // Set MPIE to 1
        mstatus_mpp_r  <= 2'b11;            // Set MPP to M-mode
      end else if (sret) begin
        // SRET: Return from supervisor-mode trap
        mstatus_sie_r  <= mstatus_spie_r;   // Restore supervisor interrupt enable
        mstatus_spie_r <= 1'b1;             // Set SPIE to 1
        mstatus_spp_r  <= 1'b0;             // Set SPP to U-mode
      end else if (csr_we && !csr_read_only) begin
        // Normal CSR write
        case (csr_addr)
          CSR_MSTATUS: begin
            mstatus_sie_r  <= csr_write_value[1];
            mstatus_mie_r  <= csr_write_value[3];
            mstatus_spie_r <= csr_write_value[5];
            mstatus_mpie_r <= csr_write_value[7];
            mstatus_spp_r  <= csr_write_value[8];
            mstatus_mpp_r  <= csr_write_value[12:11];
            mstatus_sum_r  <= csr_write_value[18];
            mstatus_mxr_r  <= csr_write_value[19];
          end
          CSR_MIE:      mie_r      <= csr_write_value;
          CSR_MTVEC:    mtvec_r    <= {csr_write_value[XLEN-1:2], 2'b00};  // Align to 4 bytes
          CSR_MSCRATCH: mscratch_r <= csr_write_value;
          CSR_MEPC:     mepc_r     <= {csr_write_value[XLEN-1:2], 2'b00};  // Align to 4 bytes
          CSR_MCAUSE:   mcause_r   <= csr_write_value;
          CSR_MTVAL:    mtval_r    <= csr_write_value;
          CSR_MIP:      mip_r      <= csr_write_value;
          CSR_MEDELEG:  medeleg_r  <= csr_write_value;
          CSR_MIDELEG:  mideleg_r  <= csr_write_value;
          CSR_SATP:     satp_r     <= csr_write_value;
          // Supervisor CSRs
          CSR_SSTATUS: begin
            // SSTATUS is a restricted view of MSTATUS
            // Only allow writes to S-mode visible fields
            mstatus_sie_r  <= csr_write_value[1];
            mstatus_spie_r <= csr_write_value[5];
            mstatus_spp_r  <= csr_write_value[8];
            mstatus_sum_r  <= csr_write_value[18];
            mstatus_mxr_r  <= csr_write_value[19];
          end
          CSR_SIE: begin
            // SIE is a subset of MIE - only write S-mode interrupt bits [9,5,1]
            mie_r[9] <= csr_write_value[9];  // SEIE
            mie_r[5] <= csr_write_value[5];  // STIE
            mie_r[1] <= csr_write_value[1];  // SSIE
          end
          CSR_STVEC:    stvec_r    <= {csr_write_value[XLEN-1:2], 2'b00};  // Align to 4 bytes
          CSR_SSCRATCH: sscratch_r <= csr_write_value;
          CSR_SEPC:     sepc_r     <= {csr_write_value[XLEN-1:2], 2'b00};  // Align to 4 bytes
          CSR_SCAUSE:   scause_r   <= csr_write_value;
          CSR_STVAL:    stval_r    <= csr_write_value;
          CSR_SIP: begin
            // SIP is a subset of MIP - only write S-mode interrupt bits [9,5,1]
            // Note: typically only SSIP (bit 1) is writable from software
            mip_r[1] <= csr_write_value[1];  // SSIP (software interrupt)
          end
          // Floating-point CSRs
          CSR_FFLAGS:   fflags_r   <= csr_write_value[4:0];  // Write exception flags
          CSR_FRM:      frm_r      <= csr_write_value[2:0];  // Write rounding mode
          CSR_FCSR: begin
            frm_r    <= csr_write_value[7:5];  // Upper 3 bits = rounding mode
            fflags_r <= csr_write_value[4:0];  // Lower 5 bits = exception flags
          end
          default: begin
            // No write for unknown or read-only CSRs
          end
        endcase
      end

      // Floating-point flag accumulation (OR operation, independent of CSR writes)
      // This allows FPU to accumulate exception flags without a CSR instruction
      // Flags are sticky - once set, they remain until explicitly cleared via CSR write
      if (fflags_we) begin
        fflags_r <= fflags_r | fflags_in;  // Accumulate (bitwise OR)
      end
    end
  end

  // =========================================================================
  // Trap Target Privilege Determination (Phase 2)
  // =========================================================================
  // Determine trap target privilege based on delegation and current privilege
  // Logic:
  // 1. If current privilege is M-mode, trap goes to M-mode (no delegation)
  // 2. If exception is delegated (medeleg bit set) and privilege < M-mode, trap goes to S-mode
  // 3. Otherwise, trap goes to M-mode

  function [1:0] get_trap_target_priv;
    input [4:0] cause;
    input [1:0] curr_priv;
    input [XLEN-1:0] medeleg;
    begin
      // M-mode traps never delegate
      if (curr_priv == 2'b11) begin
        get_trap_target_priv = 2'b11;  // M-mode
      end
      // Check if exception is delegated to S-mode
      else if (medeleg[cause] && (curr_priv <= 2'b01)) begin
        get_trap_target_priv = 2'b01;  // S-mode
      end
      else begin
        get_trap_target_priv = 2'b11;  // M-mode (default)
      end
    end
  endfunction

  assign trap_target_priv = get_trap_target_priv(trap_cause, current_priv, medeleg_r);

  // =========================================================================
  // Output Assignments
  // =========================================================================

  // Select trap vector based on target privilege
  assign trap_vector = (trap_target_priv == 2'b01) ? stvec_r : mtvec_r;
  assign mepc_out    = mepc_r;
  assign sepc_out    = sepc_r;
  assign mstatus_mie = mstatus_mie_r;

  // Privilege mode outputs
  assign mpp_out     = mstatus_mpp_r;
  assign spp_out     = mstatus_spp_r;

  // MMU-related outputs
  assign satp_out    = satp_r;
  assign mstatus_sum = mstatus_sum_r;
  assign mstatus_mxr = mstatus_mxr_r;

  // Floating-point CSR outputs
  assign frm_out     = frm_r;
  assign fflags_out  = fflags_r;

endmodule
