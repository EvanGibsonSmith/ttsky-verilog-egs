`timescale 1ns/1ps
`default_nettype none

module tb_top;

    logic       clk = 0;
    logic       rst_n;
    logic [7:0] ui_in;
    logic [7:0] uo_out;
    logic [7:0] uio_driven;
    wire  [7:0] uio;

    assign uio = uio_driven;

    top dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .ui_in  (ui_in),
        .uo_out (uo_out),
        .uio    (uio)
    );

    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    task automatic reset_dut();
        rst_n      = 0;
        ui_in      = 0;
        uio_driven = 0;
        repeat (3) tick();
        rst_n = 1;
        tick();
    endtask

    // Select Bernoulli project
    task automatic sel_bernoulli();
        uio_driven[7] = 0;
    endtask

    // Select LIF project
    task automatic sel_lif();
        uio_driven[7] = 1;
        uio_driven[6] = 0; // not writing config
    endtask

    // Write a LIF config register
    // ui_in[7:0] = data, uio[5:3] = addr, uio[6] = wr_en, uio[7] = 1
    task automatic lif_write(input [2:0] addr, input [7:0] data);
        ui_in      = data;
        uio_driven = {1'b1, 1'b1, addr, 3'b0}; // proj_sel=1, wr_en=1, addr
        tick();
        uio_driven[6] = 0; // deassert wr_en, stay on LIF
    endtask

    // -------------------------------------------------------------------------
    // BLOCK 0: Bernoulli multiplier
    // -------------------------------------------------------------------------
    task automatic test_bernoulli();
        integer i;
        integer prev;
        integer delta;

        $display("\n===== BLOCK 0: BERNOULLI MULTIPLIER =====");

        reset_dut();
        sel_bernoulli();

        // top=8, bottom=8 — expect ~200*(8/16)*(8/16) = 50 counts
        ui_in = 8'b1000_1000;
        prev  = dut.u_bm.count_r;

        for (i = 0; i < 200; i++) begin
            tick();
            delta = dut.u_bm.count_r - prev;
            prev  = dut.u_bm.count_r;
            if (i < 10)
                $display("cycle=%0d count=%0d stream=%0b delta=%0d",
                         i, dut.u_bm.count_r, dut.u_bm.stream, delta);
        end

        $display("Final count=%0d (expect ~%0d)",
                 dut.u_bm.count_r, 200 * 8 * 8 / (16 * 16));
    endtask

    // -------------------------------------------------------------------------
    // BLOCK 1: LIF neuron
    // -------------------------------------------------------------------------
    task automatic test_lif();
        integer i;

        $display("\n===== BLOCK 1: LIF NEURON =====");

        reset_dut();

        // Configure: threshold=32, v_reset=0, decay=2, mode_add+decay
        lif_write(3'h2, 8'sh20);  // threshold = 32
        lif_write(3'h3, 8'sh00);  // v_reset   = 0
        lif_write(3'h1, 8'sh02);  // decay_val = 2
        lif_write(3'h4, 8'h03);   // mode_add=1, mode_decay=1

        // Switch to run mode: sel_lif with no wr_en
        sel_lif();

        // input_val = 8 each cycle (net +6 after decay)
        // expect spike every ~ceil(32/6) = 6 cycles
        $display("Integrating LIF for 20 cycles (input_val=8, decay=2, threshold=32)...");
        for (i = 0; i < 20; i++) begin
            ui_in = 8'sh08;
            tick();
            $display("cycle=%0d membrane=%0d spike=%0b uo_out=0x%0h",
                     i, dut.u_lif.membrane, dut.lif_spike, uo_out);
        end
    endtask

    // -------------------------------------------------------------------------
    // MUX SWITCH TEST
    // Verify state is preserved when switching between projects
    // -------------------------------------------------------------------------
    task automatic test_mux_switch();
        integer i;
        integer bm_count_before;
        integer bm_count_after;

        $display("\n===== MUX SWITCH TEST =====");

        // --- Start on Bernoulli, accumulate for 500 cycles ---
        reset_dut();
        sel_bernoulli();
        ui_in = 8'b1000_1000; // top=8, bottom=8

        repeat (500) tick();
        bm_count_before = dut.u_bm.count_r;
        $display("Bernoulli count after 500 cycles: %0d (expect ~%0d)",
                 bm_count_before, 500 * 8 * 8 / (16 * 16));

        // --- Switch to LIF, configure and run 10 cycles ---
        lif_write(3'h2, 8'sh20);
        lif_write(3'h3, 8'sh00);
        lif_write(3'h1, 8'sh02);
        lif_write(3'h4, 8'h03);
        sel_lif();

        $display("Switched to LIF:");
        for (i = 0; i < 10; i++) begin
            ui_in = 8'sh08;
            tick();
            $display("  cycle=%0d membrane=%0d spike=%0b",
                     i, dut.u_lif.membrane, dut.lif_spike);
        end

        // --- Switch back to Bernoulli ---
        sel_bernoulli();
        ui_in = 8'b1000_1000;
        repeat (5) tick();

        bm_count_after = dut.u_bm.count_r;
        $display("Switched back to Bernoulli:");
        $display("  count before LIF phase : %0d", bm_count_before);
        $display("  count after  LIF phase : %0d", bm_count_after);
        $display("  delta (should be ~0-2) : %0d", bm_count_after - bm_count_before);
        // bm_project has no enable gate so it keeps counting during LIF phase.
        // Delta covers ~15 config write cycles + 10 LIF run cycles = ~25 cycles
        // at (8/16)*(8/16) = 0.25 rate -> expect ~6 extra counts
        $display("  (note: bm counts during LIF phase too — no enable gate)");
    endtask

    // -------------------------------------------------------------------------
    // MAIN
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("project_tb.vcd");
        $dumpvars(0, tb_top);

        ui_in      = 0;
        uio_driven = 0;
        rst_n      = 0;

        test_bernoulli();
        test_lif();
        test_mux_switch();

        $display("\nDONE");
        $finish;
    end

endmodule