`default_nettype none

module bm_project (
    input  wire        [7:0]  ui_in,
    output wire        [7:0]  uo_out,
    output wire        [15:0] count,
    output wire               stream,
    input  wire               clk,
    input  wire               rst_n
);

    logic [15:0] count_r;  // internal register

    logic [7:0] q;

    logic [3:0] top, bottom;
    logic [3:0] rand_top, rand_bottom;
    logic [7:0] q_top_full;
    logic [7:0] q_bot_full;
    logic [3:0] q_top;
    logic [3:0] q_bot;

    lfsr8 #(.SEED(8'hA7)) u_lfsr_top (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (1'b1),
        .q     (q_top_full)
    );

    lfsr8 u_lfsr_bot (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (1'b1),
        .q     (q_bot_full)
    );

    assign q_top = q_top_full[7:4];
    assign q_bot = q_bot_full[3:0];

    assign rand_top    = q_top;
    assign rand_bottom = q_bot;

    assign top    = ui_in[7:4];
    assign bottom = ui_in[3:0];

    assign stream = (top > rand_top) & (bottom > rand_bottom);

    always_ff @(posedge clk) begin
        if (!rst_n)
            count_r <= 0;
        else
            count_r <= count_r + stream;
    end

    assign count  = count_r;
    assign uo_out = count[7:0];

endmodule