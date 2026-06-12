// =============================================================================
// accel_wrapper_tb.sv — Unit-level testbench for accel_wrapper
// -----------------------------------------------------------------------------
// Test: 8x8 identity weight matrix, known activation input
// Expected: psum_out[col] = act_in[col] (identity passthrough)
//
// Identity matrix: weight[row][col] = 1 if row==col, else 0
// Activations: act[row] = row+1 (i.e. 1,2,3,4,5,6,7,8)
// Expected result: psum_out[col] = col+1
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module accel_wrapper_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam DATA_W   = 8;
    localparam ACC_W    = 32;
    localparam ROWS     = 8;
    localparam COLS     = 8;
    localparam CLK_HALF = 5; // 100MHz

    // AXI-Lite addresses
    localparam [31:0] AXIL_MLOAD_ADDR  = 32'hA000_0000;
    localparam [31:0] AXIL_MMUL_KICK   = 32'hA000_0004;
    localparam [31:0] AXIL_MSTORE_ADDR = 32'hA000_0008;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;
    reg  [31:0] axil_awaddr;
    reg         axil_awvalid;
    reg  [31:0] axil_wdata;
    reg         axil_wvalid;
    reg         axil_araddr;
    reg         axil_arvalid;
    wire        accel_done;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    accel_wrapper #(
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W),
        .ROWS   (ROWS),
        .COLS   (COLS)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .axil_awaddr  (axil_awaddr),
        .axil_awvalid (axil_awvalid),
        .axil_wdata   (axil_wdata),
        .axil_wvalid  (axil_wvalid),
        .axil_araddr  (axil_araddr),
        .axil_arvalid (axil_arvalid),
        .accel_done   (accel_done)
    );

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #CLK_HALF clk = ~clk;

    // -------------------------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------------------------
    initial begin
        #10000;
        $display("TIMEOUT: accel_done never asserted");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------
    task axil_write(input [31:0] addr, input [31:0] data);
        @(negedge clk);
        axil_awaddr  = addr;
        axil_awvalid = 1'b1;
        axil_wdata   = data;
        axil_wvalid  = 1'b1;
        @(negedge clk);
        axil_awvalid = 1'b0;
        axil_wvalid  = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Directly preload scratchpad memories
    // Identity weights: mem_b[row*8 + col] = (row==col) ? 1 : 0
    // Activations:      mem_a[row*8 + col] = row+1 (same value across cols)
    // -------------------------------------------------------------------------
    task preload_memories;
        integer row, col;
        begin
            for (row = 0; row < ROWS; row = row + 1) begin
                for (col = 0; col < COLS; col = col + 1) begin
                    // Identity weight matrix
                    u_dut.u_scratchpad.mem_b[row * COLS + col] =
                        (row == col) ? 8'd1 : 8'd0;
                    // Activations: row value = row+1, same across all cols
                    u_dut.u_scratchpad.mem_a[row * COLS + col] =
                        8'(row + 1);
                end
            end
            $display("[TB] Scratchpad preloaded: identity weights, activations 1..8");
        end
    endtask

    // -------------------------------------------------------------------------
    // Result checker
    // Expected: psum_out[col] = col+1
    // -------------------------------------------------------------------------
    task check_results;
        integer col;
        reg [31:0] expected;
        reg [31:0] got;
        integer pass_cnt;
        begin
            pass_cnt = 0;
            for (col = 0; col < COLS; col = col + 1) begin
                expected = col + 1;
                got      = u_dut.u_scratchpad.mem_c[col];
                if (got === expected) begin
                    $display("[PASS] mem_c[%0d] = %0d (expected %0d)", col, got, expected);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] mem_c[%0d] = %0d (expected %0d)", col, got, expected);
                end
            end
            $display("-----------------------------");
            $display("Results: %0d/8 passed", pass_cnt);
            if (pass_cnt == 8)
                $display("ALL TESTS PASSED");
            else
                $display("TESTS FAILED");
        end
    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin
        // Init signals
        rst_n        = 1'b0;
        axil_awaddr  = 32'b0;
        axil_awvalid = 1'b0;
        axil_wdata   = 32'b0;
        axil_wvalid  = 1'b0;
        axil_araddr  = 1'b0;
        axil_arvalid = 1'b0;

        // Reset
        repeat(4) @(negedge clk);
        rst_n = 1'b1;
        repeat(2) @(negedge clk);

        // Preload scratchpad directly
        preload_memories();

        // Kick MMUL via AXI-Lite
        $display("[TB] Kicking MMUL");
        axil_write(AXIL_MMUL_KICK, 32'h1);

        // Wait for done
        @(posedge accel_done);
        $display("[TB] accel_done received at time %0t", $time);
        repeat(2) @(negedge clk);

        // Check results
        check_results();

        $finish;
    end

    // -------------------------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("accel_wrapper_tb.vcd");
        $dumpvars(0, accel_wrapper_tb);
    end

endmodule
`default_nettype wire

// =============================================================================
// Test 2: All-ones weight matrix, activations 1..8
// Every PE weight = 1, so each column accumulates all 8 activations
// psum[col] = sum(act[0..7]) = 1+2+3+4+5+6+7+8 = 36 for all cols
// =============================================================================
module accel_wrapper_tb2;

    localparam DATA_W   = 8;
    localparam ACC_W    = 32;
    localparam ROWS     = 8;
    localparam COLS     = 8;
    localparam CLK_HALF = 5;
    localparam EXPECTED = 36;

    localparam [31:0] AXIL_MMUL_KICK = 32'hA000_0004;

    reg         clk;
    reg         rst_n;
    reg  [31:0] axil_awaddr;
    reg         axil_awvalid;
    reg  [31:0] axil_wdata;
    reg         axil_wvalid;
    reg         axil_araddr;
    reg         axil_arvalid;
    wire        accel_done;

    accel_wrapper #(
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W),
        .ROWS   (ROWS),
        .COLS   (COLS)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .axil_awaddr  (axil_awaddr),
        .axil_awvalid (axil_awvalid),
        .axil_wdata   (axil_wdata),
        .axil_wvalid  (axil_wvalid),
        .axil_araddr  (axil_araddr),
        .axil_arvalid (axil_arvalid),
        .accel_done   (accel_done)
    );

    initial clk = 0;
    always #CLK_HALF clk = ~clk;

    initial begin
        #20000;
        $display("[TB2] TIMEOUT");
        $finish;
    end

    task axil_write(input [31:0] addr, input [31:0] data);
        @(negedge clk);
        axil_awaddr  = addr; axil_awvalid = 1'b1;
        axil_wdata   = data; axil_wvalid  = 1'b1;
        @(negedge clk);
        axil_awvalid = 1'b0; axil_wvalid  = 1'b0;
    endtask

    task preload_memories;
        integer row, col;
        begin
            for (row = 0; row < ROWS; row = row + 1)
                for (col = 0; col < COLS; col = col + 1) begin
                    // All-ones weight matrix
                    u_dut.u_scratchpad.mem_b[row * COLS + col] = 8'd1;
                    // Activations: act[row] = row+1
                    u_dut.u_scratchpad.mem_a[row * COLS + col] = 8'(row + 1);
                end
            $display("[TB2] Scratchpad preloaded: all-ones weights, activations 1..8");
        end
    endtask

    task check_results;
        integer col;
        reg [31:0] got;
        integer pass_cnt;
        begin
            pass_cnt = 0;
            for (col = 0; col < COLS; col = col + 1) begin
                got = u_dut.u_scratchpad.mem_c[col];
                if (got === EXPECTED) begin
                    $display("[PASS] mem_c[%0d] = %0d (expected %0d)", col, got, EXPECTED);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] mem_c[%0d] = %0d (expected %0d)", col, got, EXPECTED);
                end
            end
            $display("-----------------------------");
            $display("Results: %0d/8 passed", pass_cnt);
            if (pass_cnt == 8)
                $display("ALL TESTS PASSED");
            else
                $display("TESTS FAILED");
        end
    endtask

    initial begin
        rst_n        = 1'b0;
        axil_awaddr  = 32'b0;
        axil_awvalid = 1'b0;
        axil_wdata   = 32'b0;
        axil_wvalid  = 1'b0;
        axil_araddr  = 1'b0;
        axil_arvalid = 1'b0;

        repeat(4) @(negedge clk);
        rst_n = 1'b1;
        repeat(2) @(negedge clk);

        preload_memories();

        $display("[TB2] Kicking MMUL");
        axil_write(AXIL_MMUL_KICK, 32'h1);

        @(posedge accel_done);
        $display("[TB2] accel_done received at time %0t", $time);
        repeat(2) @(negedge clk);

        check_results();
        $finish;
    end

    initial begin
        $dumpfile("accel_wrapper_tb2.vcd");
        $dumpvars(0, accel_wrapper_tb2);
    end

endmodule
