// CSR (Control and Status Register) File
// Implements Machine-mode CSRs for RISC-V RV32I
// Supports CSR instructions: CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
// Supports trap handling: exception entry and MRET

module csr_file (
  input  wire        clk,
  input  wire        reset_n,

  // CSR read/write interface
  input  wire [11:0] csr_addr,       // CSR address
  input  wire [31:0] csr_wdata,      // Write data (from rs1 or uimm)
  input  wire [2:0]  csr_op,         // CSR operation (funct3)
  input  wire        csr_we,         // CSR write enable
  output reg  [31:0] csr_rdata,      // Read data

  // Trap handling interface
  input  wire        trap_entry,     // Trap is occurring
  input  wire [31:0] trap_pc,        // PC to save in mepc
  input  wire [4:0]  trap_cause,     // Exception cause code
  input  wire [31:0] trap_val,       // mtval value (bad address, instruction, etc.)
  output wire [31:0] trap_vector,    // mtvec value (trap handler address)

  // MRET (trap return)
  input  wire        mret,           // MRET instruction
  output wire [31:0] mepc_out,       // mepc for return

  // Status outputs
  output wire        mstatus_mie,    // Global interrupt enable
  output wire        illegal_csr     // Invalid CSR access
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
  // We only implement the fields we need for M-mode
  reg        mstatus_mie_r;   // [3] - Machine Interrupt Enable
  reg        mstatus_mpie_r;  // [7] - Machine Previous Interrupt Enable
  reg [1:0]  mstatus_mpp_r;   // [12:11] - Machine Previous Privilege (always 2'b11)

  // Machine ISA Register (misa) - read-only
  // [31:30] = 2'b01 (MXL=1 for RV32)
  // [25:0] = extensions bitmap (bit 8 = I extension)
  wire [31:0] misa = {2'b01, 4'b0, 26'b00000000000000000100000000};

  // Machine Interrupt Enable (mie) - not fully implemented yet
  reg [31:0] mie_r;

  // Machine Trap-Vector Base Address (mtvec)
  reg [31:0] mtvec_r;

  // Machine Scratch Register (mscratch) - software use
  reg [31:0] mscratch_r;

  // Machine Exception Program Counter (mepc)
  reg [31:0] mepc_r;

  // Machine Cause Register (mcause)
  reg [31:0] mcause_r;

  // Machine Trap Value (mtval)
  reg [31:0] mtval_r;

  // Machine Interrupt Pending (mip) - not fully implemented yet
  reg [31:0] mip_r;

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
  wire [31:0] mstatus_value = {
    19'b0,                // [31:13] Reserved
    mstatus_mpp_r,        // [12:11] MPP
    3'b0,                 // [10:8] Reserved
    mstatus_mpie_r,       // [7] MPIE
    3'b0,                 // [6:4] Reserved
    mstatus_mie_r,        // [3] MIE
    3'b0                  // [2:0] Reserved
  };

  // CSR read multiplexer
  always @(*) begin
    case (csr_addr)
      CSR_MSTATUS:   csr_rdata = mstatus_value;
      CSR_MISA:      csr_rdata = misa;
      CSR_MIE:       csr_rdata = mie_r;
      CSR_MTVEC:     csr_rdata = mtvec_r;
      CSR_MSCRATCH:  csr_rdata = mscratch_r;
      CSR_MEPC:      csr_rdata = mepc_r;
      CSR_MCAUSE:    csr_rdata = mcause_r;
      CSR_MTVAL:     csr_rdata = mtval_r;
      CSR_MIP:       csr_rdata = mip_r;
      CSR_MVENDORID: csr_rdata = mvendorid;
      CSR_MARCHID:   csr_rdata = marchid;
      CSR_MIMPID:    csr_rdata = mimpid;
      CSR_MHARTID:   csr_rdata = mhartid;
      default:       csr_rdata = 32'h0;  // Return 0 for unknown CSRs
    endcase
  end

  // =========================================================================
  // CSR Write Logic
  // =========================================================================

  // Determine if CSR is read-only
  wire csr_read_only = (csr_addr == CSR_MISA) ||
                       (csr_addr == CSR_MVENDORID) ||
                       (csr_addr == CSR_MARCHID) ||
                       (csr_addr == CSR_MIMPID) ||
                       (csr_addr == CSR_MHARTID);

  // Determine if CSR is valid
  wire csr_valid = (csr_addr == CSR_MSTATUS) ||
                   (csr_addr == CSR_MISA) ||
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
                   (csr_addr == CSR_MHARTID);

  // Illegal CSR access: invalid CSR or write to read-only CSR
  assign illegal_csr = (!csr_valid) || (csr_we && csr_read_only);

  // Compute CSR write value based on operation
  reg [31:0] csr_write_value;
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
      mstatus_mie_r  <= 1'b0;
      mstatus_mpie_r <= 1'b0;
      mstatus_mpp_r  <= 2'b11;      // M-mode
      mie_r          <= 32'h0;
      mtvec_r        <= 32'h0;      // Trap vector at address 0
      mscratch_r     <= 32'h0;
      mepc_r         <= 32'h0;
      mcause_r       <= 32'h0;
      mtval_r        <= 32'h0;
      mip_r          <= 32'h0;
    end else begin
      // Trap entry has priority over CSR writes
      if (trap_entry) begin
        // Save PC and cause
        mepc_r  <= trap_pc;
        mcause_r <= {27'b0, trap_cause};  // [31]=0 for exception
        mtval_r  <= trap_val;

        // Save and update status
        mstatus_mpie_r <= mstatus_mie_r;  // Save current MIE
        mstatus_mie_r  <= 1'b0;           // Disable interrupts
        mstatus_mpp_r  <= 2'b11;          // Save privilege (M-mode)
      end else if (mret) begin
        // Restore interrupt enable
        mstatus_mie_r  <= mstatus_mpie_r;
        mstatus_mpie_r <= 1'b1;
        // Privilege stays M-mode (mstatus_mpp_r unchanged)
      end else if (csr_we && !csr_read_only) begin
        // Normal CSR write
        case (csr_addr)
          CSR_MSTATUS: begin
            mstatus_mie_r  <= csr_write_value[3];
            mstatus_mpie_r <= csr_write_value[7];
            mstatus_mpp_r  <= csr_write_value[12:11];
          end
          CSR_MIE:      mie_r      <= csr_write_value;
          CSR_MTVEC:    mtvec_r    <= {csr_write_value[31:2], 2'b00};  // Align to 4 bytes
          CSR_MSCRATCH: mscratch_r <= csr_write_value;
          CSR_MEPC:     mepc_r     <= {csr_write_value[31:2], 2'b00};  // Align to 4 bytes
          CSR_MCAUSE:   mcause_r   <= csr_write_value;
          CSR_MTVAL:    mtval_r    <= csr_write_value;
          CSR_MIP:      mip_r      <= csr_write_value;
          default: begin
            // No write for unknown or read-only CSRs
          end
        endcase
      end
    end
  end

  // =========================================================================
  // Output Assignments
  // =========================================================================

  assign trap_vector = mtvec_r;
  assign mepc_out    = mepc_r;
  assign mstatus_mie = mstatus_mie_r;

endmodule
