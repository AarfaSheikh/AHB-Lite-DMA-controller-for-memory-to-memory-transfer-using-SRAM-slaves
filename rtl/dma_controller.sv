// DMA (Direct Memory Access) Engine Logic (FSM + AHB master interface logic) 
/*******************************************************************************
Read data from Source SRAM
        ↓
Hold data in register
        ↓
Write data to Destination SRAM
        ↓
Update addresses and counters
        ↓
Repeat until length = 0
********************************************************************************
*/

/* 
Features: 
        * single-channel
        * memory-to-memory
        * word-only
        * supports single and burst mode
        * AHB-Lite master side
        * no FIFO
*/

module dma_controller (
    input logic HCLK, 
    input logic HRESETn,

    input logic [DATA_W-1:0] HRDATA,
    input logic HREADY,
    input logic HRESP,

    output logic [ADDR_W-1:0] HADDR,
    output logic [1:0] HTRANS,
    output logic HWRITE,
    output logic [2:0] HSIZE,
    output logic [2:0] HBURST, // 000- Single, 011 - 4-beat, 101 - 8-beat, 111 - 16-beat
    output logic [DATA_W-1:0] HWDATA

    // Configuration signals
    input logic dma_start,
    input logic dma_irq_en,
    input logic dma_abort,
    input logic dma_mode, // 0 - single transfer, 1 - burst transfer
    input logic [2:0] burst_length_cfg, // Valid if dma_mode = 1; Encodings: 000- 4-beat, 001 - 8-beat, 010 - 16-beat
    input logic [ADDR_W-1:0] src_addr_cfg,
    input logic [ADDR_W-1:0] dst_addr_cfg,
    input logic [15:0] length_cfg, // Number of bytes to transfer
    
    // Status outputs
    output logic dma_busy,
    output logic dma_done,
    output logic dma_error,
    output logic [3:0] dma_error_code,
    output logic dma_irq
);

        import dma_defs_pkg::*;

        dma_state_t current_state, next_state;

        logic [ADDR_W-1:0] src_addr, dst_addr; // current source and destination addresses, where dma reads from and writes to; initialized from src_addr_cfg and dst_addr_cfg at the start of a transfer
        logic [DATA_W-1:0] remaining; // number of bytes left to transfer; initialized from length_cfg at the start of a transfer; decremented as transfers complete; when it reaches 0, the transfer is done
        logic [DATA_W-1:0] data_reg; // temporary register to hold data read from source before writing to destination; used in single transfer mode; in burst mode

        logic busy_r, done_r, error_r, irq_r;
        logic [3:0] err_code_r;

        assign dma_busy     = busy_r;
        assign dma_done     = done_r;
        assign dma_error    = error_r;
        assign dma_error_code = err_code_r;
        assign dma_irq      = irq_r;

        assign HSIZE = HSIZE_WORD;

        // ============================================================
        // HBURST logic
        // ============================================================
        always_comb begin
                if (mode == DMA_MODE_SINGLE)
                HBURST = 3'b000;
                else begin
                        case (burst_len)
                                4:  HBURST = 3'b011;
                                8:  HBURST = 3'b101;
                                16: HBURST = 3'b111;
                                default: HBURST = 3'b000;
                        endcase
                end
        end

        // ============================================================
        // AHB signals
        // ============================================================
        always_comb begin
        HADDR  = '0;
        HTRANS = HTRANS_IDLE;
        HWRITE = 0;
        HWDATA = '0;

                case (current_state)

                DMA_READ_ADDR: begin // Put source address on bus and start read transaction
                        HADDR  = src_addr;
                        HTRANS = HTRANS_NONSEQ;
                        HWRITE = 0; // read operation
                end

                DMA_READ_WAIT: begin // Wait for read data to be ready; keep address and control signals stable until then
                        HADDR  = src_addr;
                        HTRANS = mode ? HTRANS_SEQ : HTRANS_NONSEQ;
                        HWRITE = 0;
                end

                DMA_WRITE_ADDR: begin // Put write address on bus, data to be written on HWDATA, and start write transaction
                        HADDR  = dst_addr;
                        HTRANS = HTRANS_NONSEQ;
                        HWRITE = 1; // write operation
                        HWDATA = data_reg;
                end

                DMA_WRITE_WAIT: begin // Wait for write to complete; keep address, data, and control signals stable until then
                        HADDR  = dst_addr;
                        HTRANS = mode ? HTRANS_SEQ : HTRANS_NONSEQ;
                        HWRITE = 1;
                        HWDATA = data_reg;
                end

                endcase
        end

        // ============================================================
        // FSM
        // ============================================================
        /* 

        DMA_IDLE
        |
        | start = 1
        v
        DMA_SETUP
        |
        v
        DMA_READ_ADDR
        |
        v
        DMA_READ_WAIT
        |
        | HREADY = 1
        v
        DMA_WRITE_ADDR
        |
        v
        DMA_WRITE_WAIT
        |
        | HREADY = 1
        v
        DMA_UPDATE
        |
        | remaining == 1 ? ------ yes ---> DMA_DONE ---> DMA_IDLE
        | no
        v
        DMA_READ_ADDR ...

        DMA_ERROR ---> DMA_IDLE

        */
        always_comb begin
                next_state = current_state;

                case (current_state)

                DMA_IDLE:
                        if (start) next_state = DMA_SETUP;

                DMA_SETUP:
                        next_state = DMA_READ_ADDR;

                DMA_READ_ADDR:
                        next_state = DMA_READ_WAIT;

                DMA_READ_WAIT:
                        if (HREADY) next_state = DMA_WRITE_ADDR;

                DMA_WRITE_ADDR:
                        next_state = DMA_WRITE_WAIT;

                DMA_WRITE_WAIT:
                        if (HREADY) next_state = DMA_UPDATE;

                DMA_UPDATE:
                        if (remaining == 1) // if only 1 word (4 bytes) left to transfer, this transfer will complete the entire transaction, so next state is DONE; otherwise, there are more transfers to do, so next state is READ_ADDR to start the next read
                                next_state = DMA_DONE;
                        else
                                next_state = DMA_READ_ADDR;

                DMA_DONE:
                        next_state = DMA_IDLE;

                DMA_ERROR:
                        next_state = DMA_IDLE;

                endcase
        end

        // ============================================================
        // Sequential
        // ============================================================
        always_ff @(posedge HCLK or negedge HRESETn) begin
                if (!HRESETn) begin
                current_state     <= DMA_IDLE;
                src_addr  <= '0;
                dst_addr  <= '0;
                remaining <= '0;
                data_reg  <= '0;

                busy_r  <= 0;
                done_r  <= 0;
                error_r <= 0;
                irq_r   <= 0;
                end
                else begin
                        current_state <= next_state;
                        irq_r <= 0;

                        case (current_state)

                                DMA_IDLE: begin
                                        busy_r <= 0;
                                        done_r <= 0;

                                        if (start) begin
                                                src_addr  <= src_addr_cfg;
                                                dst_addr  <= dst_addr_cfg;
                                                remaining <= len_cfg;
                                        end
                                end

                                DMA_SETUP: begin
                                        busy_r <= 1;
                                end

                                DMA_READ_WAIT: begin
                                        if (HREADY)
                                        data_reg <= HRDATA;
                                end

                                DMA_WRITE_WAIT: begin
                                        if (HREADY) begin
                                                src_addr  <= src_addr + DATA_W/8;
                                                dst_addr  <= dst_addr + DATA_W/8;
                                                remaining <= remaining - 1; // remaining length counts in number of words, not bytes; length_cfg should be initialized accordingly by software (length in bytes / (DATA_W/8))
                                        end
                                end

                                DMA_DONE: begin
                                        busy_r <= 0;
                                        done_r <= 1;
                                        if (irq_en) irq_r <= 1;
                                end

                        endcase
                end
        end

endmodule