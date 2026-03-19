// Integrates DMA + SRAM + wiring for the top level system

module top_level_system (
    input logic HCLK,
    input logic HRESETn,

    input logic dma_start,
    input logic dma_irq_en,
    input logic dma_abort,
    input logic dma_mode, // 0 - single transfer, 1 - burst transfer
    input logic [2:0] burst_length_cfg, // Valid if dma_mode = 1; Encodings: 000- 4-beat, 001 - 8-beat, 010 - 16-beat
    input logic [dma_defs_pkg::ADDR_W-1:0] src_addr_cfg,
    input logic [dma_defs_pkg::ADDR_W-1:0] dst_addr_cfg,
    input logic [dma_defs_pkg::DATA_W-1:0] length_cfg, // Number of bytes to transfer
    
    // DMA Status outputs
    output logic dma_busy,
    output logic dma_done,
    output logic dma_error,
    output logic [3:0] dma_error_code,
    output logic dma_irq
);

    import dma_defs_pkg::*;

    // ============================================================
    // DMA master-side AHB signals
    // ============================================================
    logic [ADDR_W-1:0] HADDR;
    logic [1:0]        HTRANS;
    logic              HWRITE;
    logic [2:0]        HSIZE;
    logic [2:0]        HBURST;
    logic [DATA_W-1:0] HWDATA;

    logic [DATA_W-1:0] HRDATA;
    logic              HREADY;
    logic              HRESP;

    // ============================================================
    // SRAM0 slave outputs
    // ============================================================
    logic [DATA_W-1:0] HRDATA_sram0;
    logic              HREADY_sram0;
    logic              HRESP_sram0;

    // ============================================================
    // SRAM1 slave outputs
    // ============================================================
    logic [DATA_W-1:0] HRDATA_sram1;
    logic              HREADY_sram1;
    logic              HRESP_sram1;

    // ============================================================
    // Slave select signals
    // ============================================================
    logic sel_sram0, sel_sram1;

    assign sel_sram0 = addr_in_range(HADDR, SRAM0_BASE, SRAM_SIZE);
    assign sel_sram1 = addr_in_range(HADDR, SRAM1_BASE, SRAM_SIZE);

    // Instantiate DMA controller
    dma_controller u_dma_controller (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HRDATA           (HRDATA),
        .HREADY           (HREADY),
        .HRESP            (HRESP),

        .HADDR            (HADDR),
        .HTRANS           (HTRANS),
        .HWRITE           (HWRITE),
        .HSIZE            (HSIZE),
        .HBURST           (HBURST),
        .HWDATA           (HWDATA),

        .dma_start        (dma_start),
        .dma_irq_en       (dma_irq_en),
        .dma_abort        (dma_abort),
        .dma_mode         (dma_mode),
        .burst_length_cfg (burst_length_cfg),
        .src_addr_cfg     (src_addr_cfg),
        .dst_addr_cfg     (dst_addr_cfg),
        .length_cfg       (length_cfg),  
        .dma_busy         (dma_busy),
        .dma_done         (dma_done),
        .dma_error        (dma_error),
        .dma_error_code   (dma_error_code),
        .dma_irq          (dma_irq)
    );

    // ============================================================
    // SRAM0 Instance
    // ============================================================
    sram_ahb_subsystem #(
        .SRAM_BASE(SRAM0_BASE)
    ) u_sram0 (
        .HCLK    (HCLK),
        .HRESETn (HRESETn),

        .HADDR   (HADDR),
        .HWDATA  (HWDATA),
        .HWRITE  (HWRITE),
        .HTRANS  (HTRANS),
        .HSIZE   (HSIZE),

        .HRDATA  (HRDATA_sram0),
        .HREADY  (HREADY_sram0),
        .HRESP   (HRESP_sram0)
    );

    // ============================================================
    // SRAM1 Instance
    // ============================================================
    sram_ahb_subsystem #(
        .SRAM_BASE(SRAM1_BASE)
    ) u_sram1 (
        .HCLK    (HCLK),
        .HRESETn (HRESETn),

        .HADDR   (HADDR),
        .HWDATA  (HWDATA),
        .HWRITE  (HWRITE),
        .HTRANS  (HTRANS),
        .HSIZE   (HSIZE),

        .HRDATA  (HRDATA_sram1),
        .HREADY  (HREADY_sram1),
        .HRESP   (HRESP_sram1)
    );

    // ============================================================
    // Return path mux: selected slave drives DMA inputs
    // ============================================================
    always_comb begin
        HRDATA = '0;
        HREADY = 1'b1;
        HRESP  = HRESP_OKAY;

        if (sel_sram0) begin
            HRDATA = HRDATA_sram0;
            HREADY = HREADY_sram0;
            HRESP  = HRESP_sram0;
        end
        else if (sel_sram1) begin
            HRDATA = HRDATA_sram1;
            HREADY = HREADY_sram1;
            HRESP  = HRESP_sram1;
        end
        else begin
            // No valid slave selected
            HRDATA = '0;
            HREADY = 1'b1;
            HRESP  = HRESP_ERROR;
        end
    end

endmodule