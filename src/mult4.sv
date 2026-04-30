`default_nettype none

// Exact 4x4 unsigned multiplier.
//
// Takes the same ui_in[7:4] and ui_in[3:0] inputs as bm_project.
// Produces the exact 8-bit product a*b in [0, 225].
//
// For apples-to-apples comparison with the Bernoulli multiplier:
//   - Bernoulli output: count/W, a probability estimate in [0, 1]
//   - This output:      a*b / 256, interpreting the 8-bit result as
//     fixed-point in [0, 1] with 8 bits of precision
//
// The conventional multiplier is the ground truth the Bernoulli estimate
// is measured against. Area and timing differences are visible in synthesis.

module mult4 (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out
);

    wire [3:0] a = ui_in[7:4];
    wire [3:0] b = ui_in[3:0];

    // Full 8-bit product — synthesiser will infer an efficient multiplier
    wire [7:0] product = a * b;

    assign uo_out = product;

endmodule
