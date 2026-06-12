// =============================================================================
// scratchpad.sv — Register-based scratchpad memories for NN accelerator
// -----------------------------------------------------------------------------
// Three separate memories:
//   SRAM A : 64 x 8-bit  — input activations (matrix A)
//   SRAM B : 64 x 8-bit  — weights (matrix B)
//   SRAM C :  8 x 32-bit — results (matrix C, psum outputs)
//
// All synchronous, single-port, active-low reset.
// Swap internals to Fakeram macros for ASAP7 PD flow.
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module scratchpad (
    input  wire        clk,
    input  wire        rst_n,

    // SRAM A — activation matrix (64 x 8)
    input  wire [5:0]  sram_a_addr,
    input  wire        sram_a_ren,
    input  wire        sram_a_wen,
    input  wire [7:0]  sram_a_wdata,
    output reg  [7:0]  sram_a_rdata,

    // SRAM B — weight matrix (64 x 8)
    input  wire [5:0]  sram_b_addr,
    input  wire        sram_b_ren,
    input  wire        sram_b_wen,
    input  wire [7:0]  sram_b_wdata,
    output reg  [7:0]  sram_b_rdata,

    // SRAM C — result matrix (8 x 32)
    input  wire [2:0]  sram_c_addr,
    input  wire        sram_c_ren,
    input  wire        sram_c_wen,
    input  wire [31:0] sram_c_wdata,
    output reg  [31:0] sram_c_rdata
);

    // -------------------------------------------------------------------------
    // Register arrays
    // -------------------------------------------------------------------------
    reg [7:0]  mem_a [0:63];
    reg [7:0]  mem_b [0:63];
    reg [31:0] mem_c [0:7];

    integer i;

    // -------------------------------------------------------------------------
    // SRAM A
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 64; i = i + 1)
                mem_a[i] <= 8'b0;
            sram_a_rdata <= 8'b0;
        end else begin
            if (sram_a_wen)
                mem_a[sram_a_addr] <= sram_a_wdata;
            if (sram_a_ren)
                sram_a_rdata <= mem_a[sram_a_addr];
        end
    end

    // -------------------------------------------------------------------------
    // SRAM B
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 64; i = i + 1)
                mem_b[i] <= 8'b0;
            sram_b_rdata <= 8'b0;
        end else begin
            if (sram_b_wen)
                mem_b[sram_b_addr] <= sram_b_wdata;
            if (sram_b_ren)
                sram_b_rdata <= mem_b[sram_b_addr];
        end
    end

    // -------------------------------------------------------------------------
    // SRAM C
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1)
                mem_c[i] <= 32'b0;
            sram_c_rdata <= 32'b0;
        end else begin
            if (sram_c_wen)
                mem_c[sram_c_addr] <= sram_c_wdata;
            if (sram_c_ren)
                sram_c_rdata <= mem_c[sram_c_addr];
        end
    end

endmodule
`default_nettype wire
