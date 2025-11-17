// ptw.v - 页表遍历器 (PTW)
// 共享的页表遍历单元，同时服务于 I-TLB 和 D-TLB
// 实现 RISC-V Sv32 (RV32) 与 Sv39 (RV64) 页表遍历
// 作者：RV1 项目组
// 日期：2025-11-08 (Session 125)

`include "config/rv_config.vh"

module ptw #(
  parameter XLEN = `XLEN
) (
  input  wire             clk,
  input  wire             reset_n,

  // 来自 TLB 的 PTW 请求
  input  wire             req_valid,         // PTW 请求有效
  input  wire [XLEN-1:0]  req_vaddr,         // 虚拟地址
  input  wire             req_is_store,      // 1=写存储(store)，0=读(load)
  input  wire             req_is_fetch,      // 1=取指(fetch)，0=数据访问
  output reg              req_ready,         // PTW 完成（单拍脉冲）
  output reg              req_page_fault,    // 页错误
  output reg  [XLEN-1:0]  req_fault_vaddr,   // 产生错误的虚拟地址

  // 提供给 TLB 更新的 PTW 结果
  output reg              result_valid,      // 结果有效（触发 TLB 更新）
  output reg  [XLEN-1:0]  result_vpn,        // 虚拟页号
  output reg  [XLEN-1:0]  result_ppn,        // 物理页号
  output reg  [7:0]       result_pte,        // PTE 标志位
  output reg  [XLEN-1:0]  result_level,      // 页级别

  // 页表遍历使用的内存接口
  output reg              mem_req_valid,     // 读 PTE 的内存请求
  output reg  [XLEN-1:0]  mem_req_addr,      // PTE 的物理地址
  input  wire             mem_req_ready,     // 内存端准备好
  input  wire [XLEN-1:0]  mem_resp_data,     // PTE 数据
  input  wire             mem_resp_valid,    // PTE 响应有效

  // CSR 接口
  input  wire [XLEN-1:0]  satp,              // SATP 寄存器
  input  wire [1:0]       privilege_mode,    // 当前特权级
  input  wire             mstatus_sum,       // SUM 位
  input  wire             mstatus_mxr        // MXR 位
);

  // =========================================================================
  // RISC-V 虚拟内存参数
  // =========================================================================

  localparam PAGE_SHIFT = 12;  // 4KB 页

  // Sv32 (RV32) 的页表层数
  localparam SV32_LEVELS = 2;

  // Sv39 (RV64) 的页表层数
  localparam SV39_LEVELS = 3;

  // PTE 位编码
  localparam PTE_V = 0;
  localparam PTE_R = 1;
  localparam PTE_W = 2;
  localparam PTE_X = 3;
  localparam PTE_U = 4;
  localparam PTE_G = 5;
  localparam PTE_A = 6;
  localparam PTE_D = 7;

  // =========================================================================
  // SATP 解码
  // =========================================================================

  wire [XLEN-1:0] satp_ppn;

  generate
    if (XLEN == 32) begin : gen_satp_sv32
      assign satp_ppn = {{10{1'b0}}, satp[21:0]};  // 22-bit PPN
    end else begin : gen_satp_sv39
      assign satp_ppn = {{20{1'b0}}, satp[43:0]};  // 44-bit PPN
    end
  endgenerate

  // =========================================================================
  // VPN 提取
  // =========================================================================

  function [XLEN-1:0] extract_vpn;
    input [XLEN-1:0] vaddr;
    input integer level;
    begin
      if (XLEN == 32) begin
        // Sv32: VPN[1] = bits[31:22], VPN[0] = bits[21:12]
        case (level)
          0: extract_vpn = vaddr[21:12];
          1: extract_vpn = vaddr[31:22];
          default: extract_vpn = 0;
        endcase
      end else begin
        // Sv39: VPN[2] = bits[38:30], VPN[1] = bits[29:21], VPN[0] = bits[20:12]
        case (level)
          0: extract_vpn = vaddr[20:12];
          1: extract_vpn = vaddr[29:21];
          2: extract_vpn = vaddr[38:30];
          default: extract_vpn = 0;
        endcase
      end
    end
  endfunction

  function [XLEN-1:0] get_full_vpn;
    input [XLEN-1:0] vaddr;
    begin
      if (XLEN == 32) begin
        get_full_vpn = {{(XLEN-20){1'b0}}, vaddr[31:12]};
      end else begin
        get_full_vpn = {{(XLEN-27){1'b0}}, vaddr[38:12]};
      end
    end
  endfunction

  // =========================================================================
  // 权限检查
  // =========================================================================

  function check_permission;
    input [7:0] pte_flags;
    input is_store;
    input is_fetch;
    input [1:0] priv_mode;
    input sum;
    input mxr;
    begin
      check_permission = 1;

      if (!pte_flags[PTE_V]) begin
        check_permission = 0;
      end
      else if (!pte_flags[PTE_R] && !pte_flags[PTE_W] && !pte_flags[PTE_X]) begin
        check_permission = 0;
      end
      else if (pte_flags[PTE_W] && !pte_flags[PTE_R]) begin
        check_permission = 0;
      end
      else if (priv_mode == 2'b00) begin
        if (!pte_flags[PTE_U]) begin
          check_permission = 0;
        end
      end
      else if (priv_mode == 2'b01) begin
        if (pte_flags[PTE_U] && !sum) begin
          check_permission = 0;
        end
      end

      if (check_permission) begin
        if (is_fetch) begin
          check_permission = pte_flags[PTE_X];
        end else if (is_store) begin
          check_permission = pte_flags[PTE_W];
        end else begin
          check_permission = pte_flags[PTE_R] || (pte_flags[PTE_X] && mxr);
        end
      end
    end
  endfunction

  // =========================================================================
  // PTW 状态机
  // =========================================================================

  localparam PTW_IDLE       = 3'b000;
  localparam PTW_LEVEL_0    = 3'b001;
  localparam PTW_LEVEL_1    = 3'b010;
  localparam PTW_LEVEL_2    = 3'b011;
  localparam PTW_UPDATE_TLB = 3'b100;
  localparam PTW_FAULT      = 3'b101;

  reg [2:0] ptw_state;
  reg [2:0] ptw_level;
  reg [XLEN-1:0] ptw_pte_addr;
  reg [XLEN-1:0] ptw_pte_data;
  reg [XLEN-1:0] ptw_vpn_save;
  reg [XLEN-1:0] ptw_vaddr_save;
  reg ptw_is_store_save;
  reg ptw_is_fetch_save;
  reg [1:0] ptw_priv_save;
  reg ptw_sum_save;
  reg ptw_mxr_save;

  wire [XLEN-1:0] max_levels = (XLEN == 32) ? SV32_LEVELS : SV39_LEVELS;

  integer i;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      ptw_state <= PTW_IDLE;
      ptw_level <= 0;
      ptw_pte_addr <= 0;
      ptw_pte_data <= 0;
      ptw_vpn_save <= 0;
      ptw_vaddr_save <= 0;
      ptw_is_store_save <= 0;
      ptw_is_fetch_save <= 0;
      ptw_priv_save <= 0;
      ptw_sum_save <= 0;
      ptw_mxr_save <= 0;
      mem_req_valid <= 0;
      mem_req_addr <= 0;
      req_ready <= 0;
      req_page_fault <= 0;
      req_fault_vaddr <= 0;
      result_valid <= 0;
      result_vpn <= 0;
      result_ppn <= 0;
      result_pte <= 0;
      result_level <= 0;
    end else begin
      // 默认：单拍输出清零
      req_ready <= 0;
      req_page_fault <= 0;
      result_valid <= 0;

      case (ptw_state)
        PTW_IDLE: begin
          if (req_valid) begin
            // 开始一次新的页表遍历
            $display("PTW: 开始页表遍历 VA=0x%h (fetch=%b store=%b)",
                     req_vaddr, req_is_fetch, req_is_store);
            ptw_vpn_save <= get_full_vpn(req_vaddr);
            ptw_vaddr_save <= req_vaddr;
            ptw_is_store_save <= req_is_store;
            ptw_is_fetch_save <= req_is_fetch;
            ptw_priv_save <= privilege_mode;
            ptw_sum_save <= mstatus_sum;
            ptw_mxr_save <= mstatus_mxr;
            ptw_level <= max_levels - 1;

            // 计算第一个 PTE 地址（顶层页表）
            if (XLEN == 32) begin
              ptw_pte_addr <= (satp_ppn << PAGE_SHIFT) +
                              (extract_vpn(req_vaddr, max_levels - 1) << 2);
            end else begin
              ptw_pte_addr <= (satp_ppn << PAGE_SHIFT) +
                              (extract_vpn(req_vaddr, max_levels - 1) << 3);
            end

            // 跳转到对应层的状态
            case (max_levels - 1)
              2: ptw_state <= PTW_LEVEL_2;
              1: ptw_state <= PTW_LEVEL_1;
              default: ptw_state <= PTW_LEVEL_0;
            endcase
          end
        end

        PTW_LEVEL_0, PTW_LEVEL_1, PTW_LEVEL_2: begin
          // 发起 PTE 内存请求
          if (!mem_req_valid) begin
            $display("PTW: Level %0d - 读取 PTE 地址=0x%h", ptw_level, ptw_pte_addr);
            mem_req_valid <= 1;
            mem_req_addr <= ptw_pte_addr;
          end else if (mem_req_ready && mem_resp_valid) begin
            // 收到 PTE 响应
            $display("PTW: Level %0d - 收到 PTE=0x%h V=%b R=%b W=%b X=%b U=%b",
                     ptw_level, mem_resp_data, mem_resp_data[PTE_V],
                     mem_resp_data[PTE_R], mem_resp_data[PTE_W],
                     mem_resp_data[PTE_X], mem_resp_data[PTE_U]);
            ptw_pte_data <= mem_resp_data;
            mem_req_valid <= 0;

            // 检查 PTE 是否有效
            if (!mem_resp_data[PTE_V]) begin
              $display("PTW: 错误 - 无效的 PTE (V=0)");
              ptw_state <= PTW_FAULT;
            end
            // 检查是否为叶子 PTE
            else if (mem_resp_data[PTE_R] || mem_resp_data[PTE_X]) begin
              // 叶子 PTE - 检查权限
              if (check_permission(mem_resp_data[7:0], ptw_is_store_save, ptw_is_fetch_save,
                                   ptw_priv_save, ptw_sum_save, ptw_mxr_save)) begin
                $display("PTW: 叶子 PTE 找到，权限检查通过");
                ptw_state <= PTW_UPDATE_TLB;
              end else begin
                $display("PTW: 错误 - 权限被拒绝");
                ptw_state <= PTW_FAULT;
              end
            end
            // 在 level 0 遇到非叶子 PTE 视为错误
            else if (ptw_level == 0) begin
              $display("PTW: 错误 - Level 0 遇到非叶子 PTE");
              ptw_state <= PTW_FAULT;
            end
            // 非叶子 PTE，继续向下一级页表
            else begin
              $display("PTW: 非叶子 PTE，下降到级别 %0d", ptw_level - 1);
              ptw_level <= ptw_level - 1;

              // 计算下一层 PTE 地址
              if (XLEN == 32) begin
                ptw_pte_addr <= (mem_resp_data[31:10] << PAGE_SHIFT) +
                                (extract_vpn(ptw_vaddr_save, ptw_level - 1) << 2);
              end else begin
                ptw_pte_addr <= (mem_resp_data[53:10] << PAGE_SHIFT) +
                                (extract_vpn(ptw_vaddr_save, ptw_level - 1) << 3);
              end

              // 切换到下一层状态
              case (ptw_level)
                2: ptw_state <= PTW_LEVEL_1;
                1: ptw_state <= PTW_LEVEL_0;
                default: ptw_state <= PTW_FAULT;
              endcase
            end
          end else begin
            // 等待内存响应，保持请求有效
            mem_req_valid <= 1;
          end
        end

        PTW_UPDATE_TLB: begin
          // 将结果发送给 TLB 做更新
          result_valid <= 1;
          result_vpn <= ptw_vpn_save;
          if (XLEN == 32) begin
            result_ppn <= {{10{1'b0}}, ptw_pte_data[31:10]};
          end else begin
            result_ppn <= {{20{1'b0}}, ptw_pte_data[53:10]};
          end
          result_pte <= ptw_pte_data[7:0];
          result_level <= ptw_level;
          $display("PTW: 状态 PTW_UPDATE_TLB - 发送 result_valid");

          // 再次基于当前访问类型做权限检查
          if (check_permission(ptw_pte_data[7:0], ptw_is_store_save, ptw_is_fetch_save,
                               ptw_priv_save, ptw_sum_save, ptw_mxr_save)) begin
            $display("PTW: 完成 - VA=0x%h 翻译成功", ptw_vaddr_save);
            req_ready <= 1;
          end else begin
            $display("PTW: 错误 - 权限被拒绝 VA=0x%h", ptw_vaddr_save);
            req_page_fault <= 1;
            req_fault_vaddr <= ptw_vaddr_save;
            req_ready <= 1;
          end

          ptw_state <= PTW_IDLE;
          $display("PTW: 状态 PTW_UPDATE_TLB -> PTW_IDLE");
        end

        PTW_FAULT: begin
          // 页错误 - 如 PTE 仍然有效，可选地更新 TLB 以缓存错误翻译
          if (ptw_pte_data[PTE_V]) begin
            result_valid <= 1;
            result_vpn <= ptw_vpn_save;
            if (XLEN == 32) begin
              result_ppn <= {{10{1'b0}}, ptw_pte_data[31:10]};
            end else begin
              result_ppn <= {{20{1'b0}}, ptw_pte_data[53:10]};
            end
            result_pte <= ptw_pte_data[7:0];
            result_level <= ptw_level;
          end

          req_page_fault <= 1;
          req_fault_vaddr <= ptw_vaddr_save;
          req_ready <= 1;
          ptw_state <= PTW_IDLE;
        end

        default: ptw_state <= PTW_IDLE;
      endcase
    end
  end

endmodule
