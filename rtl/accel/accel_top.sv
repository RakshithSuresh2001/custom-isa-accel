`timescale 1ns/1ps
`default_nettype none

module accel_top #(
    parameter DATA_W = 8,
    parameter ACC_W  = 32,
    parameter ROWS   = 8,
    parameter COLS   = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] axil_awaddr,
    input  wire        axil_awvalid,
    input  wire [31:0] axil_wdata,
    input  wire        axil_wvalid,
    input  wire        axil_araddr,
    input  wire        axil_arvalid,
    output reg         accel_done,
    output reg  [5:0]  sram_a_addr,
    output reg         sram_a_ren,
    input  wire [7:0]  sram_a_rdata,
    output reg  [5:0]  sram_b_addr,
    output reg         sram_b_ren,
    input  wire [7:0]  sram_b_rdata,
    output reg  [2:0]  sram_c_addr,
    output reg         sram_c_wen,
    output reg  [31:0] sram_c_wdata
);

    reg [31:0] reg_mload, reg_mmul, reg_mstore, reg_status;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_mload <= 0; reg_mmul <= 0; reg_mstore <= 0;
        end else if (axil_awvalid && axil_wvalid) begin
            case (axil_awaddr[3:0])
                4'h0: reg_mload  <= axil_wdata;
                4'h4: reg_mmul   <= axil_wdata;
                4'h8: reg_mstore <= axil_wdata;
                default: begin end
            endcase
        end
    end

    reg [DATA_W-1:0] weight_data_arr [0:COLS-1];
    reg [DATA_W-1:0] act_buf         [0:ROWS-1];
    reg [DATA_W-1:0] act_in_arr      [0:ROWS-1];

    wire [COLS*DATA_W-1:0] weight_data_flat;
    wire [ROWS*DATA_W-1:0] act_in_flat;
    wire [COLS*ACC_W-1:0]  psum_out_w;

    genvar gi;
    generate
        for (gi = 0; gi < COLS; gi++) begin : pack_w
            assign weight_data_flat[gi*DATA_W +: DATA_W] = weight_data_arr[gi];
        end
        for (gi = 0; gi < ROWS; gi++) begin : pack_a
            assign act_in_flat[gi*DATA_W +: DATA_W] = act_in_arr[gi];
        end
    endgenerate

    reg       weight_load;
    reg [2:0] weight_row;

    systolic_array_wrap #(.ROWS(ROWS),.COLS(COLS),.DATA_W(DATA_W),.ACC_W(ACC_W)) u_systolic (
        .clk              (clk),
        .rst_n            (rst_n),
        .weight_load      (weight_load),
        .weight_row       (weight_row),
        .weight_data_flat (weight_data_flat),
        .act_in_flat      (act_in_flat),
        .psum_out_flat    (psum_out_w)
    );

    reg mmul_prev;
    wire mmul_kick = reg_mmul[0] && !mmul_prev;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) mmul_prev <= 0;
        else        mmul_prev <= reg_mmul[0];
    end

    // States
    // SRAM read = 3 cycles: REQ (ren+addr), WAIT, LAT (rdata valid)
    // Weight fire = 1 extra cycle after LAT col7 so weight_data_arr[7]
    // is stable before weight_load pulses
    localparam IDLE        = 4'd0;
    localparam LOAD_W_REQ  = 4'd1;
    localparam LOAD_W_WAIT = 4'd2;
    localparam LOAD_W_LAT  = 4'd3;
    localparam LOAD_W_FIRE = 4'd4; // weight_load pulse, all cols stable
    localparam LOAD_A_REQ  = 4'd5;
    localparam LOAD_A_WAIT = 4'd6;
    localparam LOAD_A_LAT  = 4'd7;
    localparam COMPUTE     = 4'd8;
    localparam DONE        = 4'd9;

    reg [3:0]  state;
    reg [3:0]  row_cnt, col_cnt;
    reg [3:0]  latch_row, latch_col;
    reg [4:0]  compute_cnt;
    integer    k;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            row_cnt      <= 0; col_cnt   <= 0;
            latch_row    <= 0; latch_col <= 0;
            compute_cnt  <= 0;
            weight_load  <= 0; weight_row <= 0;
            accel_done   <= 0;
            sram_a_addr  <= 0; sram_a_ren  <= 0;
            sram_b_addr  <= 0; sram_b_ren  <= 0;
            sram_c_addr  <= 0; sram_c_wen  <= 0; sram_c_wdata <= 0;
            reg_status   <= 0;
            for (k = 0; k < COLS; k++) weight_data_arr[k] <= 0;
            for (k = 0; k < ROWS; k++) act_buf[k]         <= 0;
            for (k = 0; k < ROWS; k++) act_in_arr[k]      <= 0;
        end else begin
            weight_load <= 0;
            sram_a_ren  <= 0;
            sram_b_ren  <= 0;
            sram_c_wen  <= 0;
            accel_done  <= 0;

            case (state)
                IDLE: begin
                    reg_status <= 0;
                    if (mmul_kick) begin
                        state         <= LOAD_W_REQ;
                        row_cnt       <= 0; col_cnt <= 0;
                        reg_status[0] <= 1;
                    end
                end

                // Cycle 1: assert ren + addr, save indices
                LOAD_W_REQ: begin
                    sram_b_addr <= {row_cnt[2:0], col_cnt[2:0]};
                    sram_b_ren  <= 1;
                    latch_col   <= col_cnt;
                    latch_row   <= row_cnt;
                    weight_row  <= row_cnt[2:0];
                    state       <= LOAD_W_WAIT;
                end

                // Cycle 2: rdata arriving
                LOAD_W_WAIT: begin
                    state <= LOAD_W_LAT;
                end

                // Cycle 3: rdata valid, write to array
                LOAD_W_LAT: begin
                    weight_data_arr[latch_col] <= sram_b_rdata;
                    if (latch_col == COLS - 1) begin
                        // All cols written this cycle — go to FIRE
                        // so weight_data_arr[COLS-1] is stable next cycle
                        state <= LOAD_W_FIRE;
                    end else begin
                        col_cnt <= latch_col + 1;
                        state   <= LOAD_W_REQ;
                    end
                end

                // Cycle 4: weight_data_arr fully stable, pulse weight_load
                LOAD_W_FIRE: begin
                    weight_load <= 1;
                    // weight_row already set in REQ, stable since then
                    if (latch_row == ROWS - 1) begin
                        row_cnt <= 0;
                        col_cnt <= 0;
                        state   <= LOAD_A_REQ;
                    end else begin
                        row_cnt <= latch_row + 1;
                        col_cnt <= 0;
                        state   <= LOAD_W_REQ;
                    end
                end

                // Cycle 1: assert ren + addr, save row
                LOAD_A_REQ: begin
                    sram_a_addr <= {row_cnt[2:0], 3'b0};
                    sram_a_ren  <= 1;
                    latch_row   <= row_cnt;
                    state       <= LOAD_A_WAIT;
                end

                // Cycle 2: rdata arriving
                LOAD_A_WAIT: begin
                    state <= LOAD_A_LAT;
                end

                // Cycle 3: rdata valid, capture
                LOAD_A_LAT: begin
                    act_buf[latch_row] <= sram_a_rdata;
                    if (latch_row == ROWS - 1) begin
                        state       <= COMPUTE;
                        compute_cnt <= 0;
                        for (k = 0; k < ROWS; k++) act_in_arr[k] <= 0;
                    end else begin
                        row_cnt <= latch_row + 1;
                        state   <= LOAD_A_REQ;
                    end
                end

                // Diagonal feed: cnt c -> act_in_arr[c] = act_buf[c]
                // psum col[c] peaks at compute_cnt == 12+c
                COMPUTE: begin
                    for (k = 0; k < ROWS; k++) act_in_arr[k] <= 0;
                    if (compute_cnt < ROWS)
                        act_in_arr[compute_cnt[2:0]] <= act_buf[compute_cnt[2:0]];

                    if (compute_cnt >= 5'd13 && compute_cnt <= 5'd20) begin
                        sram_c_addr  <= compute_cnt[4:0] - 5'd13;
                        sram_c_wen   <= 1;
                        sram_c_wdata <= psum_out_w[(compute_cnt - 5'd13) * ACC_W +: ACC_W];
                    end

                    if (compute_cnt == 5'd20)
                        state <= DONE;
                    else
                        compute_cnt <= compute_cnt + 1;
                end

                DONE: begin
                    accel_done    <= 1;
                    reg_status[0] <= 0;
                    reg_status[1] <= 1;
                    reg_mmul      <= 0;
                    state         <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire
