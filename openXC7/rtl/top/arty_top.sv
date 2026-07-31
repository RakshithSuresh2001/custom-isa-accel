`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// arty_top.sv - Top-level wrapper for Arty A7 FPGA (MicroBlaze-free, openXC7)
// -----------------------------------------------------------------------------
// Instantiates:
//   - cpu_top: RV32I pipeline with custom ISA extension
//   - accel_wrapper: systolic array accelerator over AXI-Lite
//   - imem: instruction memory (BRAM-inferred, initialized from hex file)
//   - dmem: data memory (BRAM-inferred)
//
// Scratchpad preload (sram_a/b) is tied off since MicroBlaze (proprietary
// Xilinx IP) cannot be ported through the openXC7 flow. External write
// ports are unused in this variant.
//
// Arty A7-100T board connections:
//   - sys_clk: 100 MHz onboard clock (pin E3)
//   - sys_rst_n: ck_rst, active-low on Arty A7 (pin C2)
//   - led[3:0]: status LEDs
// =============================================================================

module arty_top (
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    output reg  [3:0]  led
);

    wire clk   = sys_clk;
    wire rst_n = sys_rst_n;    // ck_rst is already active-low on Arty A7, no inversion needed

    // -------------------------------------------------------------------------
    // Instruction memory (BRAM-inferred, 256 x 32-bit)
    // -------------------------------------------------------------------------
    reg [31:0] imem [0:255];
    initial $readmemh("imem.hex", imem);

    wire [31:0] imem_addr;
    wire [31:0] imem_data;
    assign imem_data = imem[imem_addr[9:2]];

    // -------------------------------------------------------------------------
    // Data memory (BRAM-inferred, 256 x 32-bit)
    // -------------------------------------------------------------------------
    reg [31:0] dmem [0:255];
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire        dmem_wr_en;
    wire [31:0] dmem_rdata;

    always_ff @(posedge clk) begin
        if (dmem_wr_en)
            dmem[dmem_addr[9:2]] <= dmem_wdata;
    end
    assign dmem_rdata = dmem[dmem_addr[9:2]];

    // -------------------------------------------------------------------------
    // AXI-Lite wires between cpu_top and accel_wrapper
    // -------------------------------------------------------------------------
    wire [31:0] axil_awaddr;
    wire        axil_awvalid;
    wire [31:0] axil_wdata;
    wire        axil_wvalid;
    wire        axil_araddr;
    wire        axil_arvalid;
    wire        accel_done;

    // -------------------------------------------------------------------------
    // Scratchpad external write ports - tied off (no MicroBlaze in this flow)
    // -------------------------------------------------------------------------
    wire [5:0]  sram_a_addr_mb = 6'd0;
    wire        sram_a_wen_mb  = 1'b0;
    wire [7:0]  sram_a_wdata_mb = 8'd0;
    wire [5:0]  sram_b_addr_mb = 6'd0;
    wire        sram_b_wen_mb  = 1'b0;
    wire [7:0]  sram_b_wdata_mb = 8'd0;

    // -------------------------------------------------------------------------
    // cpu_top instantiation
    // -------------------------------------------------------------------------
    cpu_top u_cpu (
        .clk          (clk),
        .rst_n        (rst_n),
        .imem_addr    (imem_addr),
        .imem_data    (imem_data),
        .dmem_addr    (dmem_addr),
        .dmem_wdata   (dmem_wdata),
        .dmem_wr_en   (dmem_wr_en),
        .dmem_rdata   (dmem_rdata),
        .axil_awaddr  (axil_awaddr),
        .axil_awvalid (axil_awvalid),
        .axil_wdata   (axil_wdata),
        .axil_wvalid  (axil_wvalid),
        .axil_araddr  (axil_araddr),
        .axil_arvalid (axil_arvalid),
        .accel_done   (accel_done)
    );

    // -------------------------------------------------------------------------
    // accel_wrapper instantiation
    // -------------------------------------------------------------------------
    accel_wrapper #(
        .DATA_W (8),
        .ACC_W  (32),
        .ROWS   (8),
        .COLS   (8)
    ) u_accel (
        .clk              (clk),
        .rst_n            (rst_n),
        .axil_awaddr      (axil_awaddr),
        .axil_awvalid     (axil_awvalid),
        .axil_wdata       (axil_wdata),
        .axil_wvalid      (axil_wvalid),
        .axil_araddr      (axil_araddr),
        .axil_arvalid     (axil_arvalid),
        .accel_done       (accel_done),
        .sram_a_addr_ext  (sram_a_addr_mb),
        .sram_a_wen_ext   (sram_a_wen_mb),
        .sram_a_wdata_ext (sram_a_wdata_mb),
        .sram_b_addr_ext  (sram_b_addr_mb),
        .sram_b_wen_ext   (sram_b_wen_mb),
        .sram_b_wdata_ext (sram_b_wdata_mb)
    );

    // -------------------------------------------------------------------------
    // Status LEDs
    // [0] reset active, [1] accel_done latched, [3] heartbeat
    // -------------------------------------------------------------------------
    reg [26:0] heartbeat_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            heartbeat_cnt <= 0;
            led           <= 4'b0001;
        end else begin
            heartbeat_cnt <= heartbeat_cnt + 1;
            led[0] <= ~rst_n;
            led[3] <= heartbeat_cnt[26];
            if (accel_done) led[1] <= 1'b1;
        end
    end

endmodule

`default_nettype wire
