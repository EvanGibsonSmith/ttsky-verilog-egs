`timescale 1ns/1ps
`default_nettype none

// =============================================================================
// tb_top — testbench for tt_um_bn_lif_evan
//
// proj_sel encoding (uio_in[7:6]):
//   2'b00 = Bernoulli multiplier
//   2'b01 = LIF neuron
//   2'b10 = Conventional multiplier
// =============================================================================

module tb_top;

    logic       clk = 0;
    logic       rst_n;
    logic [7:0] ui_in;
    logic [7:0] uo_out;
    logic [7:0] uio_in;
    wire  [7:0] uio_out;
    wire  [7:0] uio_oe;

    tt_um_bn_lif_evan dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (1'b1)
    );

    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    task automatic tick();
        @(posedge clk); #1;
    endtask

    task automatic reset_dut();
        rst_n  = 0;
        ui_in  = 0;
        uio_in = 0;
        repeat(3) tick();
        rst_n = 1;
        tick();
    endtask

    task automatic sel_bernoulli();
        uio_in[7:6] = 2'b00;
    endtask

    task automatic sel_lif();
        uio_in[7:6] = 2'b01;
        uio_in[5]   = 0;   // not writing config
    endtask

    task automatic sel_mult();
        uio_in[7:6] = 2'b10;
    endtask

    // Write a LIF config register
    task automatic lif_write(input [2:0] addr, input [7:0] data);
        ui_in      = data;
        uio_in     = {2'b01, 1'b1, addr, 2'b0};  // proj_sel=01, wr_en=1, addr
        tick();
        uio_in[5]  = 0;  // deassert wr_en, stay on LIF
    endtask

    // -------------------------------------------------------------------------
    // BLOCK 0: Bernoulli multiplier
    // -------------------------------------------------------------------------
    task automatic test_bernoulli();
        int i;
        int count_before, count_after;
        real est, true_p;

        $display("\n===== BLOCK 0: BERNOULLI MULTIPLIER =====");
        reset_dut();
        sel_bernoulli();

        // top=8, bottom=8 -> true product = (8/16)*(8/16) = 0.25
        // expect ~50 counts after 200 cycles
        ui_in    = 8'b1000_1000;
        true_p   = (8.0/16.0) * (8.0/16.0);

        count_before = dut.u_bm.count_r;  // read internal count directly in sim

        for (i = 0; i < 200; i++) begin
            tick();
            if (i < 10)
                $display("cycle=%0d count=%0d stream=%0b",
                         i, dut.u_bm.count_r, dut.u_bm.stream);
        end

        count_after = dut.u_bm.count_r;
        est = real'(count_after - count_before) / 200.0;
        $display("Estimate=%.4f  True=%.4f  Error=%+.4f  (full count=%0d)",
                 est, true_p, est - true_p, count_after);
    endtask

    // -------------------------------------------------------------------------
    // BLOCK 1: LIF neuron
    // -------------------------------------------------------------------------
    task automatic test_lif();
        int i;

        $display("\n===== BLOCK 1: LIF NEURON =====");
        reset_dut();

        lif_write(3'h2, 8'sh20);  // threshold = 32
        lif_write(3'h3, 8'sh00);  // v_reset   = 0
        lif_write(3'h1, 8'sh02);  // decay_val = 2
        lif_write(3'h4, 8'h03);   // mode_add=1, mode_decay=1

        sel_lif();

        // input=8, decay=2 -> net +6 per cycle, spike every ~ceil(32/6)=6 cycles
        $display("Integrating LIF (input_val=8, decay=2, threshold=32, v_reset=0):");
        $display("  cycle | membrane | spike | uo_out");
        for (i = 0; i < 20; i++) begin
            ui_in = 8'sh08;
            tick();
            $display("  %5d | %8d | %5b | 0x%02h",
                     i, dut.u_lif.membrane, dut.lif_spike, uo_out);
        end
    endtask

    // -------------------------------------------------------------------------
    // BLOCK 2: Conventional multiplier — comparison against Bernoulli
    // -------------------------------------------------------------------------
    task automatic test_mult();
        int i;
        logic [3:0] a, b;
        logic [7:0] exact;
        real exact_fp, bern_est, true_p, error;

        $display("\n===== BLOCK 2: CONVENTIONAL MULTIPLIER vs BERNOULLI =====");
        $display("%-4s | %-4s | %-8s | %-10s | %-10s | %-10s | %-10s",
                 "a", "b", "Exact", "Exact/256", "True p", "Bern W=256", "Bern Error");
        $display("----------------------------------------------------------------------");

        // Sweep representative input pairs via indexed case
        for (i = 0; i < 6; i++) begin
            case (i)
                0: begin a = 4'd4;  b = 4'd4;  end
                1: begin a = 4'd8;  b = 4'd8;  end
                2: begin a = 4'd8;  b = 4'd12; end
                3: begin a = 4'd12; b = 4'd12; end
                4: begin a = 4'd15; b = 4'd15; end
                5: begin a = 4'd10; b = 4'd6;  end
                default: begin a = 4'd0; b = 4'd0; end
            endcase

            // --- Exact result ---
            sel_mult();
            ui_in = {a, b};
            tick();
            exact    = uo_out;
            exact_fp = real'(exact) / 256.0;
            true_p   = (real'(a)/16.0) * (real'(b)/16.0);

            // --- Bernoulli estimate over W=256 cycles ---
            reset_dut();
            sel_bernoulli();
            ui_in = {a, b};
            repeat(256) tick();
            bern_est = real'(dut.u_bm.count_r) / 256.0;
            error    = bern_est - true_p;

            $display("%-4d | %-4d | %-8d | %-10.4f | %-10.4f | %-10.4f | %+.4f",
                     a, b, exact, exact_fp, true_p, bern_est, error);

            reset_dut();
        end
    endtask

    // -------------------------------------------------------------------------
    // MUX SWITCH TEST
    // -------------------------------------------------------------------------
    task automatic test_mux_switch();
        int bm_count_before, bm_count_after;

        $display("\n===== MUX SWITCH TEST =====");

        reset_dut();
        sel_bernoulli();
        ui_in = 8'b1000_1000;
        repeat(500) tick();

        bm_count_before = dut.u_bm.count_r;
        $display("Bernoulli count after 500 cycles: %0d (expect ~%0d)",
                 bm_count_before, 500 * 8 * 8 / (16 * 16));

        // Switch to mult, verify output changes immediately
        sel_mult();
        tick();
        $display("Switched to mult: uo_out=0x%02h (expect 0x%02h for 8*8=64)",
                 uo_out, 8'd64);

        // Switch to LIF
        lif_write(3'h2, 8'sh20);
        lif_write(3'h3, 8'sh00);
        lif_write(3'h1, 8'sh02);
        lif_write(3'h4, 8'h03);
        sel_lif();
        repeat(10) begin ui_in = 8'sh08; tick(); end
        $display("Switched to LIF: membrane=%0d spike=%0b",
                 dut.u_lif.membrane, dut.lif_spike);

        // Switch back to Bernoulli
        sel_bernoulli();
        ui_in = 8'b1000_1000;
        repeat(5) tick();
        bm_count_after = dut.u_bm.count_r;

        $display("Back to Bernoulli: count=%0d (bm keeps counting, delta=%0d expected ~6)",
                 bm_count_after, bm_count_after - bm_count_before);
    endtask

    // -------------------------------------------------------------------------
    // MAIN
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tt_sim.vcd");
        $dumpvars(0, tb_top);

        ui_in  = 0;
        uio_in = 0;
        rst_n  = 0;

        test_bernoulli();
        test_lif();
        test_mult();
        test_mux_switch();

        $display("\nDONE");
        $finish;
    end

endmodule