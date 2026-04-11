`default_nettype none

// =============================================================================
// tt_um_top — Tiny Tapeout top-level, two-project static select
//
// Pin allocation
//   uio[7]       — project select: 0 = Bernoulli, 1 = LIF
//
//   BERNOULLI (uio[7]=0):
//     ui_in[7:4]   — top    (4-bit operand)
//     ui_in[3:0]   — bottom (4-bit operand)
//     uo_out[7:0]  — count[7:0]
//
//   LIF (uio[7]=1):
//     ui_in[7:0]   — input_val (run mode, every cycle)
//     uio[6]       — wr_en (1 = config write this cycle)
//     uio[5:3]     — reg_addr (config register select)
//     uo_out[7:0]  — {membrane[7:1], spike}
//
//   LIF register address map (uio[5:3])
//     3'h0 : input_val  — not written via reg file, comes from ui_in directly
//     3'h1 : decay_val  signed [7:0]
//     3'h2 : threshold  signed [7:0]
//     3'h3 : v_reset    signed [7:0]
//     3'h4 : mode_ctrl  [1:0] = {mode_decay, mode_add}
// =============================================================================

module tt_um_bn_lif_evan (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output  wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire        ena,
    input  wire       clk,
    input  wire       rst_n
);

    // -------------------------------------------------------------------------
    // Pin decode
    // -------------------------------------------------------------------------
    wire        proj_sel = uio_in[7];   // 0=Bernoulli, 1=LIF
    wire        lif_wr   = uio_in[6];   // LIF config write strobe
    wire [2:0]  reg_addr = uio_in[5:3]; // LIF config register address

    // uio is input-only from the DUT's perspective
    // Leave uio undriven (TB drives it, DUT only reads)

    // -------------------------------------------------------------------------
    // Block 0: bm_project (Bernoulli multiplier)
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
    // Block 1: linear_lif
    // -------------------------------------------------------------------------

    // Config registers — written once at startup, stable during run
    logic signed [7:0] lif_decay_val;
    logic signed [7:0] lif_threshold;
    logic signed [7:0] lif_v_reset;
    logic              lif_mode_add;
    logic              lif_mode_decay;

    // Config writes: only when LIF selected and wr_en asserted
    wire lif_cfg_wr = proj_sel & lif_wr;

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

    // input_val comes directly from ui_in every cycle when LIF is selected
    wire signed [7:0] lif_input_val = ui_in;

    wire        lif_spike;
    wire signed [7:0] lif_membrane;

    linear_lif #(
        .DATA_WIDTH  (8),
        .DECAY_WIDTH (8)
    ) u_lif (
        .clk        (clk),
        .rst_n      (rst_n),
        .en         (proj_sel & ~lif_wr),  // run only when selected and not writing config
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
    // Output mux
    // -------------------------------------------------------------------------
    assign uo_out = proj_sel ? lif_uo : bm_uo;

endmodule