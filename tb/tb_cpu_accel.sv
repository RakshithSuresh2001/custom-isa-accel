// =============================================================================
// tb_cpu_accel.sv — CPU-level testbench for custom ISA accelerator extension
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_cpu_accel;

    reg clk, rst_n;
    reg [31:0] imem [0:255];
    reg [31:0] dmem [0:255];

    wire [31:0] imem_addr;
    wire [31:0] dmem_addr, dmem_wdata;
    wire        dmem_wr_en;
    wire [31:0] axil_awaddr;
    wire        axil_awvalid;
    wire [31:0] axil_wdata;
    wire        axil_wvalid;
    wire        axil_araddr;
    wire        axil_arvalid;
    wire        accel_done;

    cpu_top u_cpu (
        .clk          (clk),
        .rst_n        (rst_n),
        .imem_addr    (imem_addr),
        .imem_data    (imem[imem_addr[9:2]]),
        .dmem_addr    (dmem_addr),
        .dmem_wdata   (dmem_wdata),
        .dmem_wr_en   (dmem_wr_en),
        .dmem_rdata   (dmem[dmem_addr[9:2]]),
        .axil_awaddr  (axil_awaddr),
        .axil_awvalid (axil_awvalid),
        .axil_wdata   (axil_wdata),
        .axil_wvalid  (axil_wvalid),
        .axil_araddr  (axil_araddr),
        .axil_arvalid (axil_arvalid),
        .accel_done   (accel_done)
    );

    accel_wrapper #(.DATA_W(8),.ACC_W(32),.ROWS(8),.COLS(8)) u_accel (
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

    always_ff @(posedge clk)
        if (dmem_wr_en) dmem[dmem_addr[9:2]] <= dmem_wdata;

    always #5 clk = ~clk;

    integer pass, fail, i, j;

    `define CHECK(label, got, exp) \
        if ((got) === (exp)) begin \
            $display("  PASS %s = %0d", label, got); pass = pass + 1; \
        end else begin \
            $display("  FAIL %s got=%0d exp=%0d", label, got, exp); fail = fail + 1; \
        end

    // Instruction encoding
    // MLOAD  {7'b0, rs2, rs1, 3'b000, 5'b0, 7'b0001011}
    // MMUL   {7'b0, 5'b0, 5'b0, 3'b001, 5'b0, 7'b0001011}
    // MSTORE {7'b0, 5'b0, rs1, 3'b010, 5'b0, 7'b0001011}

    initial begin
        $dumpfile("waves_accel.vcd");
        $dumpvars(0, tb_cpu_accel);

        clk   = 0;
        rst_n = 0;
        pass  = 0;
        fail  = 0;

        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 32'b0;
        end

        // addi x1, x0, 0  — base addr
        imem[0] = 32'h00000093;
        // addi x2, x0, 0  — matrix_id A
        imem[1] = 32'h00000113;
        // addi x3, x0, 1  — matrix_id B
        imem[2] = 32'h00100193;
        // MLOAD x1, x2  (rs1=x1=5'd1, rs2=x2=5'd2)
        imem[3] = {7'b0, 5'd2, 5'd1, 3'b000, 5'b0, 7'b0001011};
        // MLOAD x1, x3  (rs1=x1=5'd1, rs2=x3=5'd3)
        imem[4] = {7'b0, 5'd3, 5'd1, 3'b000, 5'b0, 7'b0001011};
        // MMUL
        imem[5] = {7'b0, 5'b0, 5'b0, 3'b001, 5'b0, 7'b0001011};
        // MSTORE x1
        imem[6] = {7'b0, 5'b0, 5'd1, 3'b010, 5'b0, 7'b0001011};
        // Pipeline resume check
        imem[7]  = 32'h00500413; // addi x8, x0, 5
        imem[8]  = 32'h00300493; // addi x9, x0, 3
        imem[9]  = 32'h00940533; // add  x10, x8, x9  -> 8
        imem[10] = 32'h00000013;
        imem[11] = 32'h00000013;
        imem[12] = 32'h00000013;
        imem[13] = 32'h00000013;
        imem[14] = 32'h00000013;

        rst_n = 0;
        repeat(2) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // Backdoor preload: identity weights, activations 1..8
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                u_accel.u_scratchpad.mem_b[i*8+j] = (i==j) ? 8'd1 : 8'd0;
                u_accel.u_scratchpad.mem_a[i*8+j] = 8'(i+1);
            end

        $display("[TB] Scratchpad preloaded: identity weights, activations 1..8");
        $display("[TB] Running CPU with MLOAD/MMUL/MSTORE...");

        repeat(600) @(posedge clk);

        $display("\n=== CPU Accelerator Extension Test ===");

        $display("\n-- Accelerator results: psum[c] = c+1 --");
        `CHECK("mem_c[0]", u_accel.u_scratchpad.mem_c[0], 32'd1)
        `CHECK("mem_c[1]", u_accel.u_scratchpad.mem_c[1], 32'd2)
        `CHECK("mem_c[2]", u_accel.u_scratchpad.mem_c[2], 32'd3)
        `CHECK("mem_c[3]", u_accel.u_scratchpad.mem_c[3], 32'd4)
        `CHECK("mem_c[4]", u_accel.u_scratchpad.mem_c[4], 32'd5)
        `CHECK("mem_c[5]", u_accel.u_scratchpad.mem_c[5], 32'd6)
        `CHECK("mem_c[6]", u_accel.u_scratchpad.mem_c[6], 32'd7)
        `CHECK("mem_c[7]", u_accel.u_scratchpad.mem_c[7], 32'd8)

        $display("\n-- Pipeline resume after MSTORE --");
        `CHECK("x8  (addi 5)", u_cpu.u_regfile.regs[8],  32'd5)
        `CHECK("x9  (addi 3)", u_cpu.u_regfile.regs[9],  32'd3)
        `CHECK("x10 (add 8)",  u_cpu.u_regfile.regs[10], 32'd8)

        $display("\n=== Total: %0d PASS, %0d FAIL ===\n", pass, fail);
        $finish;
    end

    initial begin
        forever @(posedge clk)
            if (u_cpu.u_regfile.wr_en && u_cpu.u_regfile.rd_addr != 0)
                $display("RTL rd=x%0d val=0x%08x",
                    u_cpu.u_regfile.rd_addr,
                    u_cpu.u_regfile.rd_data);
    end

    initial begin
        forever @(posedge clk)
            if (accel_done)
                $display("[TB] accel_done pulsed at t=%0t", $time);
    end

    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
`default_nettype wire
