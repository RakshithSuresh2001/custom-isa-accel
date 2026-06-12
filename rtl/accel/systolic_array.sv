// =============================================================================
// systolic_array.sv — 8x8 Weight-Stationary Systolic Array (Top-Level)
// -----------------------------------------------------------------------------
// Author      : Rakshith Suresh
// Affiliation : MS Electrical Engineering 
//               University of Southern California, Viterbi School of Engineering
// Email       : rsuresh@usc.edu
// GitHub      : https://github.com/RakshithSuresh2001
// -----------------------------------------------------------------------------
// Description:
//   Top-level module instantiating an 8x8 grid of PE modules with
//   weight-stationary dataflow. Designed for AI/ML inference acceleration.
//
// Dataflow:
//   Activations  →  [PE00][PE01]...[PE07]  → (discarded)
//   (left edge)     [PE10][PE11]...[PE17]
//                   ...
//                   [PE70][PE71]...[PE77]
//                      ↓    ↓         ↓
//                   psum[0] psum[1] ... psum[7]  (bottom edge outputs)
//
// Pipeline: 12 registered stages total
//   Stages 1-2  : Input activation registers
//   Stages 3-10 : 8 PE rows (each row adds 1 psum register stage)
//   Stages 11-12: Output psum registers
//
// Timing:
//   First valid output at col[0]: cycle 20 after activations begin
//   Skew: col[k] peaks 1 cycle after col[k-1] due to horizontal propagation
//
// Weight Loading:
//   Serial, one row per cycle via weight_load + weight_row interface
//
// Tool Flow:
//   Simulation : ModelSim / QuestaSim (SystemVerilog)
//   Synthesis  : Yosys 0.44 → SkyWater 130nm HD standard cell library
//   P&R        : OpenROAD v2.0 (floorplan, place, CTS, route)
//   GDS        : KLayout merge → 6_final.gds
//   PDK        : SkyWater sky130hd (TT corner, 025C, 1V80)
//   Instances  : 25,030 standard cell instances post-synthesis
// =============================================================================

module systolic_array #(
    parameter ROWS   = 8,
    parameter COLS   = 8,
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  logic                          clk,
    input  logic                          rst_n,

    // Weight load interface — one row at a time
    input  logic                          weight_load,
    input  logic [$clog2(ROWS)-1:0]       weight_row,
    input  logic [COLS-1:0][DATA_W-1:0]   weight_data,

    // Activation inputs — one value per row, fed into left edge
    input  logic [ROWS-1:0][DATA_W-1:0]   act_in,

    // Partial sum outputs — one per column, from bottom row
    output logic [COLS-1:0][ACC_W-1:0]    psum_out
);

    // ── Stages 1 & 2: Input pipeline registers ──────────────────────────────
    logic [ROWS-1:0][DATA_W-1:0] act_s1, act_s2;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            act_s1 <= '0;
            act_s2 <= '0;
        end else begin
            act_s1 <= act_in;
            act_s2 <= act_s1;
        end
    end

    // ── PE array internal wiring ─────────────────────────────────────────────
    // act_h[row][col]  : horizontal activation signal entering each PE
    //                    col 0 = registered input; col COLS = discarded
    // psum_v[row][col] : vertical partial sum signal entering each PE
    //                    row 0 = zeros (top boundary); row ROWS = output
    logic [ROWS-1:0][COLS:0][DATA_W-1:0]  act_h;
    logic [ROWS:0][COLS-1:0][ACC_W-1:0]   psum_v;

    // Feed registered activations into left edge of each row
    genvar r;
    generate
        for (r = 0; r < ROWS; r++) begin : act_feed
            assign act_h[r][0] = act_s2[r];
        end
    endgenerate

    // Top row receives zero partial sums
    assign psum_v[0] = '0;

    // ── 8x8 PE grid instantiation ────────────────────────────────────────────
    genvar row, col;
    generate
        for (row = 0; row < ROWS; row++) begin : gen_row
            for (col = 0; col < COLS; col++) begin : gen_col
                pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_pe (
                    .clk         (clk),
                    .rst_n       (rst_n),
                    // Weight load enabled only for the target row
                    .weight_load (weight_load && (weight_row == row)),
                    .weight_in   (weight_data[col]),
                    // Horizontal activation chain
                    .act_in      (act_h[row][col]),
                    .act_out     (act_h[row][col+1]),
                    // Vertical partial sum chain
                    .psum_in     (psum_v[row][col]),
                    .psum_out    (psum_v[row+1][col])
                );
            end
        end
    endgenerate

    // ── Stages 11 & 12: Output pipeline registers ────────────────────────────
    logic [COLS-1:0][ACC_W-1:0] psum_s11;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            psum_s11 <= '0;
            psum_out <= '0;
        end else begin
            psum_s11 <= psum_v[ROWS];
            psum_out <= psum_s11;
        end
    end

endmodule
