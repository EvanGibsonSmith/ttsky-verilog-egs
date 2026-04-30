`default_nettype none

// 8-bit maximal-length LFSR
// Primitive polynomial: x^8 + x^6 + x^5 + x^4 + 1
// Taps (0-indexed): 7, 5, 4, 3
// Period: 255 (all non-zero states)
// SEED must be non-zero.

module lfsr8 #(
    parameter logic [7:0] SEED = 8'h1
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       en,
    output logic [7:0] q
);

    logic [7:0] state;
    logic       feedback;

    assign feedback = state[7] ^ state[5] ^ state[4] ^ state[3];

    always_ff @(posedge clk) begin
        if (!rst_n)
            state <= SEED;
        else if (en)
            state <= {state[6:0], feedback};
    end

    assign q = state;

endmodule
