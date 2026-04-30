`default_nettype none

// =============================================================================
// tt_um_bn_lif_evan — Tiny Tapeout top-level, three-block static select
//
// Pin allocation
// --------------
//   ui_in[7:0]   — shared data input to all blocks
//
//   uio_in[7:6]  — 2-bit project select
//                    2'b00 = Bernoulli stochastic multiplier
//                    2'b01 = LIF neuron
//                    2'b10 = Conventional 4x4 multiplier
//                    2'b11 = reserved
//   uio_in[5]    — LIF wr_en  (config write strobe, LIF mode only)
//   uio_in[4:2]  — LIF reg_addr (config register select, LIF mode only)
//   uio_in[1:0]  — unused / reserved
//
//   uo_out[7:0]  — output, meaning depends on project select:
//                    00: Bernoulli count[7:0]  (lower byte of 16-bit accumulator)
//                    01: {membrane[7:1], spike}
//                    10: exact product a*b [7:0]  (8-bit, interpret as fixed-point /256)
//
//   uio_out[7:0] — Bernoulli count[15:8] (upper byte, always valid, all modes)
//                  Gives full 16-bit Bernoulli count across uo_out + uio_out
//                  when proj_sel=00. Stable but present regardless of sel.
//
// LIF register address map (uio_in[4:2])
//   3'h1 : decay_val  signed [7:0]
//   3'h2 : threshold  signed [7:0]
//   3'h3 : v_reset    signed [7:0]
//   3'h4 : mode_ctrl  [1:0] = {mode_decay, mode_add}
// =============================================================================

module tt_um_bn_lif_evan (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // -------------------------------------------------------------------------
    // Pin decode
    // -------------------------------------------------------------------------
    wire [1:0] proj_sel  = uio_in[7:6];
    wire       lif_wr    = uio_in[5];
    wire [2:0] reg_addr  = uio_in[4:2];

    // -------------------------------------------------------------------------
    // Block 0: Bernoulli stochastic multiplier
    // -------------------------------------------------------------------------
    wire [7:0]  bm_uo;
    wire [15:0] bm_count;
    wire        bm_stream;

    bm_project u_bm (
        .ui_in  (ui_in),
        .uo_out (bm_uo),
        .count  (bm_count),
        .stream (bm_stream),
        .clk    (clk),
        .rst_n  (rst_n)
    );

    // -------------------------------------------------------------------------
    // Block 1: Linear LIF neuron
    // -------------------------------------------------------------------------
    logic signed [7:0] lif_decay_val;
    logic signed [7:0] lif_threshold;
    logic signed [7:0] lif_v_reset;
    logic              lif_mode_add;
    logic              lif_mode_decay;

    wire lif_cfg_wr = (proj_sel == 2'b01) & lif_wr;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            lif_decay_val  <= 8'sh01;
            lif_threshold  <= 8'sh40;
            lif_v_reset    <= 8'sh00;
            lif_mode_add   <= 1'b1;
            lif_mode_decay <= 1'b0;
        end else if (lif_cfg_wr) begin
            case (reg_addr)
                3'h1: lif_decay_val            <= ui_in;
                3'h2: lif_threshold            <= ui_in;
                3'h3: lif_v_reset              <= ui_in;
                3'h4: {lif_mode_decay,
                        lif_mode_add}          <= ui_in[1:0];
                default: ;
            endcase
        end
    end

    wire signed [7:0] lif_input_val = ui_in;
    wire              lif_spike;
    wire signed [7:0] lif_membrane;

    linear_lif #(
        .DATA_WIDTH  (8),
        .DECAY_WIDTH (8)
    ) u_lif (
        .clk        (clk),
        .rst_n      (rst_n),
        .en         ((proj_sel == 2'b01) & ~lif_wr),
        .mode_add   (lif_mode_add),
        .mode_decay (lif_mode_decay),
        .input_val  (lif_input_val),
        .decay_val  (lif_decay_val),
        .threshold  (lif_threshold),
        .v_reset    (lif_v_reset),
        .spike      (lif_spike),
        .membrane   (lif_membrane)
    );

    wire [7:0] lif_uo = {lif_membrane[7:1], lif_spike};

    // -------------------------------------------------------------------------
    // Block 2: Conventional 4x4 unsigned multiplier
    // -------------------------------------------------------------------------
    wire [7:0] mult_uo;

    mult4 u_mult (
        .ui_in  (ui_in),
        .uo_out (mult_uo)
    );

    // -------------------------------------------------------------------------
    // Output mux
    // -------------------------------------------------------------------------
    assign uo_out = (proj_sel == 2'b00) ? bm_uo   :
                    (proj_sel == 2'b01) ? lif_uo   :
                    (proj_sel == 2'b10) ? mult_uo  :
                                          8'b0;

    // uio_out: upper byte of Bernoulli count always present for readout
    assign uio_out = bm_count[15:8];
    assign uio_oe  = 8'hFF;  // all uio pins driven as outputs

    wire _unused = &{ena, uio_in[1:0], bm_stream, lif_membrane};

endmodule
