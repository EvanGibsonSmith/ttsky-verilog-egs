`default_nettype none

// Linear Leaky Integrate-and-Fire Neuron
// Membrane dynamics:
//   - accumulate mode: v <= sat(v + input)
//   - decay  mode:     v <= sat(v - decay_val)
// Fires (spike=1) when v >= threshold, then resets to v_reset.
//
// Parameters
//   DATA_WIDTH   : bit-width of membrane and weights (integer arithmetic)
//   DECAY_WIDTH  : bit-width of the decay constant
//
// Ports
//   clk          : clock
//   rst_n        : active-low synchronous reset
//   en           : global enable
//   mode_add     : when high, add input_val to membrane
//   mode_decay   : when high, subtract decay_val from membrane
//   input_val    : signed integer to accumulate (weight * spike product)
//   decay_val    : signed integer decay amount (positive = subtracts)
//   threshold    : signed firing threshold
//   v_reset      : signed reset potential after spike
//   spike        : output spike
//   membrane     : current membrane value (for readout / debug)
//
// Notes
//   - mode_add and mode_decay can be asserted simultaneously; add runs first,
//     decay second (net: v + input - decay).
//   - Saturation is symmetric: clamps to [-(2^(DATA_WIDTH-1)), 2^(DATA_WIDTH-1)-1].
//   - Spike is registered: appears the cycle AFTER threshold is crossed.

module linear_lif #(
    parameter int DATA_WIDTH  = 8,
    parameter int DECAY_WIDTH = 8
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          en,

    input  logic                          mode_add,
    input  logic                          mode_decay,

    input  logic signed [DATA_WIDTH-1:0]  input_val,
    input  logic signed [DECAY_WIDTH-1:0] decay_val,
    input  logic signed [DATA_WIDTH-1:0]  threshold,
    input  logic signed [DATA_WIDTH-1:0]  v_reset,

    output logic                          spike,
    output logic signed [DATA_WIDTH-1:0]  membrane
);

    localparam int WIDE = DATA_WIDTH + 1;

    logic signed [WIDE-1:0] v_wide;
    logic signed [WIDE-1:0] v_after_add;
    logic signed [WIDE-1:0] v_after_decay;
    logic signed [WIDE-1:0] v_next_wide;
    logic signed [DATA_WIDTH-1:0] v_next;

    localparam logic signed [WIDE-1:0] SAT_MAX =  (1 <<< (DATA_WIDTH-1)) - 1;
    localparam logic signed [WIDE-1:0] SAT_MIN = -(1 <<< (DATA_WIDTH-1));

    assign v_wide = {{1{membrane[DATA_WIDTH-1]}}, membrane};

    assign v_after_add = mode_add
        ? v_wide + {{(WIDE-DATA_WIDTH){input_val[DATA_WIDTH-1]}}, input_val}
        : v_wide;

    assign v_after_decay = mode_decay
        ? v_after_add - {{(WIDE-DECAY_WIDTH){decay_val[DECAY_WIDTH-1]}}, decay_val}
        : v_after_add;

    assign v_next_wide = v_after_decay;
    assign v_next      = (v_next_wide > SAT_MAX) ? SAT_MAX[DATA_WIDTH-1:0] :
                         (v_next_wide < SAT_MIN) ? SAT_MIN[DATA_WIDTH-1:0] :
                                                   v_next_wide[DATA_WIDTH-1:0];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            membrane <= '0;
            spike    <= 1'b0;
        end else if (en) begin
            spike <= (v_next >= threshold);
            if (v_next >= threshold)
                membrane <= v_reset;
            else
                membrane <= v_next;
        end else begin
            spike <= 1'b0;
        end
    end

endmodule