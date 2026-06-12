// systolic_array_wrap.sv
// Flat-port wrapper around systolic_array for iverilog compatibility
`timescale 1ns/1ps
`default_nettype none

module systolic_array_wrap #(
    parameter ROWS   = 8,
    parameter COLS   = 8,
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      weight_load,
    input  wire [2:0]                weight_row,
    input  wire [COLS*DATA_W-1:0]    weight_data_flat,
    input  wire [ROWS*DATA_W-1:0]    act_in_flat,
    output wire [COLS*ACC_W-1:0]     psum_out_flat
);

    // Unpack flat buses into packed 2D for systolic_array ports
    logic [COLS-1:0][DATA_W-1:0] weight_data_2d;
    logic [ROWS-1:0][DATA_W-1:0] act_in_2d;
    logic [COLS-1:0][ACC_W-1:0]  psum_out_2d;

    genvar i;
    generate
        for (i = 0; i < COLS; i++) begin : unpack_w
            assign weight_data_2d[i] = weight_data_flat[i*DATA_W +: DATA_W];
        end
        for (i = 0; i < ROWS; i++) begin : unpack_a
            assign act_in_2d[i] = act_in_flat[i*DATA_W +: DATA_W];
        end
        for (i = 0; i < COLS; i++) begin : pack_p
            assign psum_out_flat[i*ACC_W +: ACC_W] = psum_out_2d[i];
        end
    endgenerate

    systolic_array #(
        .ROWS   (ROWS),
        .COLS   (COLS),
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W)
    ) u_sys (
        .clk         (clk),
        .rst_n       (rst_n),
        .weight_load (weight_load),
        .weight_row  (weight_row),
        .weight_data (weight_data_2d),
        .act_in      (act_in_2d),
        .psum_out    (psum_out_2d)
    );

endmodule
`default_nettype wire
