
module acc (
    input  logic clk,
    input  logic rst_n,

    input  logic start,   // reset counter when high
    input  logic din,     // stream bit

    output logic [7:0] count
);

    always_ff @(posedge clk) begin
        if (!rst_n || start)
            count <= 0;
        else
            count <= count + din;  // adds 1 if din=1, else adds 0
    end

endmodule