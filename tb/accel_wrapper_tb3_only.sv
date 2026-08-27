`timescale 1ns/1ps
`default_nettype none
module accel_wrapper_tb3;

    localparam DATA_W   = 8;
    localparam ACC_W    = 32;
    localparam ROWS     = 8;
    localparam COLS     = 8;
    localparam CLK_HALF = 5;

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
        .accel_done   (accel_done),
        .sram_a_addr_ext  (6'b0),
        .sram_a_wen_ext   (1'b0),
        .sram_a_wdata_ext (8'b0),
        .sram_b_addr_ext  (6'b0),
        .sram_b_wen_ext   (1'b0),
        .sram_b_wdata_ext (8'b0)
    );

    initial clk = 0;
    always #CLK_HALF clk = ~clk;

    initial begin
        #10000;
        $display("[TB3] TIMEOUT: accel_done never asserted");
        $finish;
    end

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

    reg [7:0]  weight_mem   [0:63];
    reg [7:0]  act_mem      [0:7];
    reg [31:0] expected_mem [0:7];

    task load_vectors;
        begin
            $readmemh("weights.hex", weight_mem);
            $readmemh("activations.hex", act_mem);
            $readmemh("expected.hex", expected_mem);
        end
    endtask

    task preload_memories;
        integer row, col;
        begin
            load_vectors();
            for (row = 0; row < ROWS; row = row + 1) begin
                for (col = 0; col < COLS; col = col + 1) begin
                    u_dut.u_scratchpad.mem_b[row * COLS + col] = weight_mem[row * COLS + col];
                    u_dut.u_scratchpad.mem_a[row * COLS + col] = act_mem[row];
                end
            end
            $display("[TB3] Scratchpad preloaded from PyTorch-generated vectors");
        end
    endtask

    task check_results;
        integer col;
        reg [31:0] got, expected;
        integer pass_cnt;
        begin
            pass_cnt = 0;
            for (col = 0; col < COLS; col = col + 1) begin
                expected = expected_mem[col];
                got      = u_dut.u_scratchpad.mem_c[col];
                if (got === expected) begin
                    $display("[PASS] mem_c[%0d] = %0d (expected %0d)", col, got, expected);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] mem_c[%0d] = %0d (expected %0d)", col, got, expected);
                end
            end
            $display("-----------------------------");
            $display("Results: %0d/8 passed (PyTorch reference check)", pass_cnt);
        end
    endtask

    initial begin
        rst_n = 0;
        repeat(4) @(negedge clk);
        rst_n = 1;

        preload_memories();

        $display("[TB3] Kicking MMUL");
        axil_write(AXIL_MMUL_KICK, 32'h1);

        @(posedge accel_done);
        $display("[TB3] accel_done received at time %0t", $time);
        repeat(2) @(negedge clk);

        check_results();
        $finish;
    end

    initial begin
        $dumpfile("accel_wrapper_tb3.vcd");
        $dumpvars(0, accel_wrapper_tb3);
    end

endmodule
