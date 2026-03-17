// Contains SRAM + AHB slave logic

module sram_ahb_subsystem #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter MEM_SIZE = 1024
) (
    input wire clk,
    input wire rst_n,
    // AHB-Lite slave interface
    input wire [ADDR_WIDTH-1:0] ahb_addr,
    input wire [DATA_WIDTH-1:0] ahb_data_in,
    output wire [DATA_WIDTH-1:0] ahb_data_out,
    input wire ahb_write_en,
    input wire ahb_sel,
    output wire ahb_ready
);

    // Internal signals
    reg [DATA_WIDTH-1:0] sram [0:MEM_SIZE-1];
    reg [DATA_WIDTH-1:0] data_out;
    
    // AHB-Lite slave logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= 0;
            ahb_ready <= 0;
        end else if (ahb_sel) begin
            if (ahb_write_en) begin
                sram[ahb_addr] <= ahb_data_in; // Write to SRAM
                ahb_ready <= 1; // Acknowledge write
            end else begin
                data_out <= sram[ahb_addr]; // Read from SRAM
                ahb_ready <= 1; // Acknowledge read
            end
        end else begin
            ahb_ready <= 0; // Not selected, not ready
        end
    end

    assign ahb_data_out = data_out;

endmodule