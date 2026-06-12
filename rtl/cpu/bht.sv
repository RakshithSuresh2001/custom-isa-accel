// Branch History Table: 2-bit saturating counter, 16-entry, PC-indexed
`timescale 1ns/1ps
`default_nettype none
module bht #(
    parameter ENTRIES = 16,
    parameter IDX_W   = 4       // log2(ENTRIES)
) (
    input  wire        clk,
    input  wire        rst_n,
    // Predict (fetch stage)
    input  wire [31:0] pc_fetch,
    output wire        predict_taken,
    // Update (execute stage)
    input  wire        update_en,
    input  wire [31:0] pc_ex,
    input  wire        actual_taken
);
    reg [1:0] bht_mem [0:ENTRIES-1];
    wire [IDX_W-1:0] fetch_idx = pc_fetch[IDX_W+1:2];
    wire [IDX_W-1:0] ex_idx    = pc_ex[IDX_W+1:2];

    // Predict: taken if MSB set (11 or 10)
    assign predict_taken = bht_mem[fetch_idx][1];

    // Update: saturating increment/decrement
    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < ENTRIES; i++)
                bht_mem[i] <= 2'b01; // Weakly not-taken
        end else if (update_en) begin
            case (bht_mem[ex_idx])
                2'b00: bht_mem[ex_idx] <= actual_taken ? 2'b01 : 2'b00;
                2'b01: bht_mem[ex_idx] <= actual_taken ? 2'b11 : 2'b00;
                2'b11: bht_mem[ex_idx] <= actual_taken ? 2'b11 : 2'b10;
                2'b10: bht_mem[ex_idx] <= actual_taken ? 2'b11 : 2'b00;
            endcase
        end
    end
endmodule
`default_nettype wire
