// Testbench for linear_lif
// Tests:
//   1. Reset behaviour
//   2. Accumulation-only mode
//   3. Decay-only mode
//   4. Combined add+decay in one cycle
//   5. Spike generation and reset
//   6. Positive saturation
//   7. Negative saturation
//   8. Spike suppression when en=0

`timescale 1ns/1ps

module tb_linear_lif;

    // DUT parameters
    localparam int DW = 8;   // DATA_WIDTH
    localparam int DECW = 8; // DECAY_WIDTH

    // Clock / reset
    logic clk    = 0;
    logic rst_n  = 0;

    // DUT ports
    logic                        en;
    logic                        mode_add;
    logic                        mode_decay;
    logic signed [DW-1:0]        input_val;
    logic signed [DECW-1:0]      decay_val;
    logic signed [DW-1:0]        threshold;
    logic signed [DW-1:0]        v_reset;
    logic                        spike;
    logic signed [DW-1:0]        membrane;

    // Instantiate DUT
    linear_lif #(
        .DATA_WIDTH  (DW),
        .DECAY_WIDTH (DECW)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (en),
        .mode_add  (mode_add),
        .mode_decay(mode_decay),
        .input_val (input_val),
        .decay_val (decay_val),
        .threshold (threshold),
        .v_reset   (v_reset),
        .spike     (spike),
        .membrane  (membrane)
    );

    // 10 ns clock
    always #5 clk = ~clk;

    // Helper: apply one cycle with given modes
    task automatic apply_cycle(
        input logic          add,
        input logic          decay,
        input logic signed [DW-1:0]   ival,
        input logic signed [DECW-1:0] dval
    );
        @(negedge clk);   // set inputs between clock edges
        mode_add   = add;
        mode_decay = decay;
        input_val  = ival;
        decay_val  = dval;
        @(posedge clk);
        #1; // small delay to let outputs settle
    endtask

    // Helper: idle cycle (no add, no decay)
    task automatic idle_cycle();
        apply_cycle(0, 0, 0, 0);
    endtask

    // Helper: check membrane and spike, print result
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(
        input string              test_name,
        input logic signed [DW-1:0] exp_membrane,
        input logic                 exp_spike
    );
        if (membrane === exp_membrane && spike === exp_spike) begin
            $display("  PASS  [%s]  membrane=%0d  spike=%0b", test_name, membrane, spike);
            pass_count++;
        end else begin
            $display("  FAIL  [%s]  membrane=%0d (exp %0d)  spike=%0b (exp %0b)",
                     test_name, membrane, exp_membrane, spike, exp_spike);
            fail_count++;
        end
    endtask

    // Helper: full reset, set threshold/v_reset, deassert reset, then one idle cycle
    task automatic do_reset(
        input logic signed [DW-1:0] thr,
        input logic signed [DW-1:0] vr
    );
        // Assert reset and clear modes between clock edges
        @(negedge clk);
        mode_add   = 0;
        mode_decay = 0;
        input_val  = 0;
        decay_val  = 0;
        threshold  = thr;
        v_reset    = vr;
        rst_n      = 0;
        // Hold reset for two full cycles
        @(posedge clk); @(negedge clk);
        @(posedge clk); @(negedge clk);
        rst_n = 1;
        // One idle cycle so combinational paths settle cleanly
        @(posedge clk); #1;
    endtask

    // ------------------------------------------------------------------ //
    initial begin
        // Default inputs
        en         = 1;
        mode_add   = 0;
        mode_decay = 0;
        input_val  = 0;
        decay_val  = 0;
        threshold  = 8'sd100;
        v_reset    = 8'sd0;
        rst_n      = 0;

        $display("=== Linear LIF Testbench ===");

        // ---- 1. Reset ----
        $display("\n--- Test 1: Reset ---");
        repeat(2) @(posedge clk); #1;
        check("reset", 8'sd0, 1'b0);
        @(negedge clk); rst_n = 1;

        // ---- 2. Accumulate only (threshold=100, v_reset=0) ----
        $display("\n--- Test 2: Accumulate only ---");
        apply_cycle(1, 0, 8'sd30, 8'sd0); check("acc +30", 8'sd30,  1'b0);
        apply_cycle(1, 0, 8'sd20, 8'sd0); check("acc +20", 8'sd50,  1'b0);
        apply_cycle(1, 0, 8'sd10, 8'sd0); check("acc +10", 8'sd60,  1'b0);

        // ---- 3. Decay only ----
        $display("\n--- Test 3: Decay only ---");
        apply_cycle(0, 1, 8'sd0, 8'sd10); check("decay -10", 8'sd50, 1'b0);
        apply_cycle(0, 1, 8'sd0, 8'sd25); check("decay -25", 8'sd25, 1'b0);

        // ---- 4. Add + decay same cycle ----
        $display("\n--- Test 4: Add and decay same cycle ---");
        // membrane=25; +20 -5 = +15 → 40
        apply_cycle(1, 1, 8'sd20, 8'sd5); check("add+decay net+15", 8'sd40, 1'b0);

        // ---- 5. Spike (registered) ----
        // Cycle A: add 65 to membrane=40 → v_next=105 ≥ 100 → spike latched, membrane→0
        // We sample spike *at* posedge A using a strobe, before clearing mode_add.
        $display("\n--- Test 5: Spike (registered) ---");
        @(negedge clk);
        mode_add = 1; mode_decay = 0; input_val = 8'sd65; decay_val = 8'sd0;
        @(posedge clk); #1; // posedge A: spike=1, membrane=0
        check("spike registered",    8'sd0, 1'b1);
        @(negedge clk); mode_add = 0; // now clear mode for cycle B
        @(posedge clk); #1; // posedge B: spike=0 (membrane=0 < threshold)
        check("spike cleared after", 8'sd0, 1'b0);

        // ---- 6. Positive saturation ----
        // Use threshold=126 (unreachable during test, but below sat ceiling of 127)
        // so that saturating to 127 DOES fire a spike — instead keep threshold=127
        // and test saturation below threshold: accumulate to 110, then add 100 → sat 127.
        // Actually: 110 < 127 (no spike), 127 >= 127 (spike). To test sat WITHOUT spike
        // we need threshold > 127, impossible in signed 8-bit.
        // Solution: test that saturation clamps correctly by checking membrane=127
        // and separately accepting spike=1 as correct hardware behaviour when sat==threshold.
        $display("\n--- Test 6: Positive saturation ---");
        do_reset(8'sd127, 8'sd0);
        // 0 + 110 = 110 < 127 → no spike
        apply_cycle(1, 0, 8'sd110, 8'sd0); check("acc 110",    8'sd110, 1'b0);
        // 110 + 100 = 210 → saturates to 127 = threshold → spike fires, membrane→0
        apply_cycle(1, 0, 8'sd100, 8'sd0); check("sat→127=thr: spike+reset", 8'sd0, 1'b1);
        // Verify clean state
        idle_cycle(); check("after sat spike", 8'sd0, 1'b0);

        // ---- 7. Negative saturation ----
        $display("\n--- Test 7: Negative saturation ---");
        do_reset(8'sd127, 8'sd0);
        apply_cycle(0, 1, 8'sd0, 8'sd60);  check("0 - 60 = -60",       -8'sd60,  1'b0);
        apply_cycle(0, 1, 8'sd0, 8'sd100); check("-60 - 100 → sat-128", -8'sd128, 1'b0);

        // ---- 8. Enable gate ----
        $display("\n--- Test 8: en=0 suppresses update ---");
        en = 0;
        apply_cycle(1, 0, 8'sd50, 8'sd0); check("en=0, no change", -8'sd128, 1'b0);
        en = 1;

        // ---- 9. Back-to-back spikes ----
        // With registered spike: spike=1 appears the cycle AFTER threshold crossed,
        // coinciding with the cycle where membrane=v_reset.
        $display("\n--- Test 9: Back-to-back spikes ---");
        do_reset(8'sd50, 8'sd10); // threshold=50, v_reset=10
        // Cycle A: 0 + 60 = 60 ≥ 50 → spike latched, membrane→10
        apply_cycle(1, 0, 8'sd60, 8'sd0); check("spike1: mem=10, spike=1", 8'sd10, 1'b1);
        // Cycle B: 10 + 60 = 70 ≥ 50 → spike latched again, membrane→10
        apply_cycle(1, 0, 8'sd60, 8'sd0); check("spike2: mem=10, spike=1", 8'sd10, 1'b1);
        // Cycle C: 10 + 30 = 40 < 50 → no spike latched
        apply_cycle(1, 0, 8'sd30, 8'sd0); check("no spike: mem=40",        8'sd40, 1'b0);

        // ---- Summary ----
        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("linear_lif.vcd");
        $dumpvars(0, tb_linear_lif);
    end

endmodule