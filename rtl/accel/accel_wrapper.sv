// =============================================================================
// accel_wrapper.sv — Top-level accelerator: accel_top + scratchpad
// -----------------------------------------------------------------------------
// Instantiates accel_top (FSM + systolic array) and scratchpad (three SRAMs).
// This is what cpu_top connects to via AXI-Lite.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module accel_wrapper #(
    parameter DATA_W = 8,
    parameter ACC_W  = 32,
    parameter ROWS   = 8,
    parameter COLS   = 8
)(
    input  wire        clk,
    input  wire        rst_n,

    // AXI-Lite slave (from CPU execute stage)
    input  wire [31:0] axil_awaddr,
    input  wire        axil_awvalid,
    input  wire [31:0] axil_wdata,
    input  wire        axil_wvalid,
    input  wire        axil_araddr,
    input  wire        axil_arvalid,

    // Done pulse back to CPU
    output wire        accel_done
);

    // -------------------------------------------------------------------------
    // Internal scratchpad wires
    // -------------------------------------------------------------------------
    wire [5:0]  sram_a_addr;
    wire        sram_a_ren;
    wire [7:0]  sram_a_rdata;

    wire [5:0]  sram_b_addr;
    wire        sram_b_ren;
    wire [7:0]  sram_b_rdata;

    wire [2:0]  sram_c_addr;
    wire        sram_c_wen;
    wire [31:0] sram_c_wdata;

    // -------------------------------------------------------------------------
    // accel_top
    // -------------------------------------------------------------------------
    accel_top #(
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W),
        .ROWS   (ROWS),
        .COLS   (COLS)
    ) u_accel_top (
        .clk          (clk),
        .rst_n        (rst_n),
        .axil_awaddr  (axil_awaddr),
        .axil_awvalid (axil_awvalid),
        .axil_wdata   (axil_wdata),
        .axil_wvalid  (axil_wvalid),
        .axil_araddr  (axil_araddr),
        .axil_arvalid (axil_arvalid),
        .accel_done   (accel_done),
        .sram_a_addr  (sram_a_addr),
        .sram_a_ren   (sram_a_ren),
        .sram_a_rdata (sram_a_rdata),
        .sram_b_addr  (sram_b_addr),
        .sram_b_ren   (sram_b_ren),
        .sram_b_rdata (sram_b_rdata),
        .sram_c_addr  (sram_c_addr),
        .sram_c_wen   (sram_c_wen),
        .sram_c_wdata (sram_c_wdata)
    );

    // -------------------------------------------------------------------------
    // Scratchpad
    // -------------------------------------------------------------------------
    scratchpad u_scratchpad (
        .clk          (clk),
        .rst_n        (rst_n),
        // SRAM A
        .sram_a_addr  (sram_a_addr),
        .sram_a_ren   (sram_a_ren),
        .sram_a_wen   (1'b0),          // writes handled externally via DMA later
        .sram_a_wdata (8'b0),
        .sram_a_rdata (sram_a_rdata),
        // SRAM B
        .sram_b_addr  (sram_b_addr),
        .sram_b_ren   (sram_b_ren),
        .sram_b_wen   (1'b0),
        .sram_b_wdata (8'b0),
        .sram_b_rdata (sram_b_rdata),
        // SRAM C
        .sram_c_addr  (sram_c_addr),
        .sram_c_ren   (1'b0),
        .sram_c_wen   (sram_c_wen),
        .sram_c_wdata (sram_c_wdata),
        .sram_c_rdata ()               // unconnected until CPU readback is added
    );

endmodule
`default_nettype wire
