`default_nettype none

// Stochastic (Bernoulli) 4x4 multiplier.
//
// Interprets ui_in[7:4] and ui_in[3:0] as 4-bit values a, b.
// Represents each as a probability p = x/16 in [0, 1].
// Two independent LFSR8 instances (different seeds, same polynomial,
// so same sequence phase-shifted) generate uniform random 4-bit thresholds.
// stream = 1 iff a >= rand_a AND b >= rand_b, giving P(stream=1) ≈ (a/16)*(b/16).
// count accumulates stream over time; count/W estimates the product probability.
//
// Note: uses >= so p=15/16 is achievable; p=16/16=1 requires a=16 which is
// out of range, so full probability 1 is not representable with 4-bit inputs.

module bm_project (
    input  wire  [7:0]  ui_in,
    output wire  [7:0]  uo_out,
    output wire  [15:0] count,
    output wire         stream,
    input  wire         clk,
    input  wire         rst_n
);

    logic [15:0] count_r;

    // Two LFSR instances — same polynomial, different seeds (phase offset)
    logic [7:0] q_top_full;
    logic [7:0] q_bot_full;

    lfsr8 #(.SEED(8'hA7)) u_lfsr_top (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (1'b1),
        .q     (q_top_full)
    );

    lfsr8 #(.SEED(8'h1)) u_lfsr_bot (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (1'b1),
        .q     (q_bot_full)
    );

    // Use upper 4 bits of each LFSR for consistent period behaviour
    logic [3:0] rand_top;
    logic [3:0] rand_bot;
    assign rand_top = q_top_full[7:4];
    assign rand_bot = q_bot_full[7:4];

    logic [3:0] top;
    logic [3:0] bottom;
    assign top    = ui_in[7:4];
    assign bottom = ui_in[3:0];

    // >= so that input=15 gives P=15/16 (maximum representable probability)
    assign stream = (top >= rand_top) & (bottom >= rand_bot);

    always_ff @(posedge clk) begin
        if (!rst_n)
            count_r <= 16'd0;
        else
            count_r <= count_r + {15'd0, stream};
    end

    assign count  = count_r;
    assign uo_out = count_r[7:0];

endmodule
