`timescale 1ns/1ps
`default_nettype none

module bm_project_tb;

    logic [7:0] ui_in;
    logic [7:0] uo_out;
    logic [15:0] count;
    logic        stream;
    logic        clk, rst_n;

    bm_project dut (
        .ui_in  (ui_in),
        .uo_out (uo_out),
        .count  (count),
        .stream (stream),
        .clk    (clk),
        .rst_n  (rst_n)
    );

    always #5 clk = ~clk;

    localparam int NUM_TRIALS = 200;
    localparam int NUM_W      = 6;
    localparam int W_EXAMPLE  = 32;

    int W_VALUES[0:NUM_W-1];

    real estimates[0:NUM_W-1][0:NUM_TRIALS-1];
    real means[0:NUM_W-1];
    real variances[0:NUM_W-1];

    task automatic reset_dut();
        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask

    // Measure one W-window without resetting the DUT.
    // Snapshots count at start and end to isolate this window.
    task automatic run_trial(input int W, output real estimate);
        int count_start, count_end;
        count_start = dut.count;
        repeat(W) @(posedge clk);
        count_end = dut.count;
        estimate = real'(count_end - count_start) / real'(W);
    endtask

    // Verbose single run: prints cycle-by-cycle for small W
    task automatic run_example(
        input logic [3:0] top_val,
        input logic [3:0] bot_val,
        input int W
    );
        real true_p, est;
        true_p = (real'(top_val) / 16.0) * (real'(bot_val) / 16.0);

        reset_dut();
        ui_in = {top_val, bot_val};

        $display("\n--- Example: top=%0d/16 * bot=%0d/16 = %.4f, W=%0d ---",
                 top_val, bot_val, true_p, W);
        $display("  cycle | rand_top | rand_bot | stream | count | running_est");

        for (int i = 0; i < W; i++) begin
            @(posedge clk);
            $display("  %5d |    %2d    |    %2d    |   %0b    | %5d | %.4f",
                     i+1,
                     dut.rand_top, dut.rand_bot,
                     dut.stream,
                     dut.count,
                     real'(dut.count) / real'(i+1));
        end

        est = real'(dut.count) / real'(W);
        $display("  => Estimate: %.4f  True: %.4f  Error: %+.4f",
                 est, true_p, est - true_p);
    endtask

    // Variance sweep parameters
    localparam logic [3:0] TOP_VAL    = 4'd10;
    localparam logic [3:0] BOTTOM_VAL = 4'd6;

    int    w_idx, t;
    real   est, sum, sq_sum, mean, variance, true_p;

    initial begin
        $dumpfile("bm_sim.vcd");
        $dumpvars(0, bm_project_tb);

        clk   = 0;
        rst_n = 0;
        ui_in = 0;

        W_VALUES[0] = 16;
        W_VALUES[1] = 32;
        W_VALUES[2] = 64;
        W_VALUES[3] = 128;
        W_VALUES[4] = 256;
        W_VALUES[5] = 512;

        // --- Verbose examples ---
        run_example(4'd8,  4'd8,  W_EXAMPLE);   // 0.5   * 0.5   = 0.2500
        run_example(4'd12, 4'd8,  W_EXAMPLE);   // 0.75  * 0.5   = 0.3750
        run_example(4'd15, 4'd15, W_EXAMPLE);   // 0.9375* 0.9375= 0.8789
        run_example(4'd4,  4'd4,  W_EXAMPLE);   // 0.25  * 0.25  = 0.0625

        // --- Variance sweep: top=10/16, bot=6/16, true product = 60/256 = 0.2344 ---
        $display("\n\n=== Variance Sweep: top=%0d/16, bot=%0d/16 ===", TOP_VAL, BOTTOM_VAL);
        true_p = (real'(TOP_VAL)/16.0) * (real'(BOTTOM_VAL)/16.0);
        $display("True product: %.4f", true_p);
        $display("%-8s | %-10s | %-10s | %-10s | %-14s",
                 "W", "Mean", "Variance", "Std", "Predicted Std");
        $display("------------------------------------------------------------");

        for (w_idx = 0; w_idx < NUM_W; w_idx++) begin
            sum    = 0.0;
            sq_sum = 0.0;
            reset_dut();
            ui_in = {TOP_VAL, BOTTOM_VAL};

            for (t = 0; t < NUM_TRIALS; t++) begin
                run_trial(W_VALUES[w_idx], est);
                estimates[w_idx][t] = est;
                sum    += est;
                sq_sum += est * est;
            end

            mean     = sum / real'(NUM_TRIALS);
            variance = (sq_sum / real'(NUM_TRIALS)) - (mean * mean);
            means[w_idx]     = mean;
            variances[w_idx] = variance;

            $display("%-8d | %-10.4f | %-10.6f | %-10.6f | %-14.6f",
                     W_VALUES[w_idx], mean, variance, $sqrt(variance),
                     $sqrt(true_p * (1.0 - true_p) / real'(W_VALUES[w_idx])));
        end

        $display("\nDone.");
        $finish;
    end

endmodule
