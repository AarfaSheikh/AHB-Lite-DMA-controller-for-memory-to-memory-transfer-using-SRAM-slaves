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

    input logic [dma_defs_pkg::DATA_W-1:0] HRDATA,
    input logic HREADY,
    input logic HRESP,

    output logic [dma_defs_pkg::ADDR_W-1:0] HADDR,
    output logic [1:0] HTRANS,
    output logic HWRITE,
    output logic [2:0] HSIZE,
    output logic [2:0] HBURST, // 000- Single, 011 - 4-beat, 101 - 8-beat, 111 - 16-beat
    output logic [dma_defs_pkg::DATA_W-1:0] HWDATA,

    // Configuration signals
    input logic dma_start,
    input logic dma_irq_en,
    input logic dma_abort,
    input logic dma_mode, // 0 - single transfer, 1 - burst transfer
    input logic [2:0] burst_length_cfg, // Valid if dma_mode = 1; Encodings: 000- 4-beat, 001 - 8-beat, 010 - 16-beat
    input logic [dma_defs_pkg::ADDR_W-1:0] src_addr_cfg,
    input logic [dma_defs_pkg::ADDR_W-1:0] dst_addr_cfg,
    input logic [dma_defs_pkg::DATA_W-1:0] length_cfg, // Number of 32-bit words to transfer
    
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
                if (dma_mode == DMA_MODE_SINGLE)
                HBURST = 3'b000;
                else begin
                        case (burst_length_cfg)
                                3'b000:  HBURST = 3'b011;
                                3'b001:  HBURST = 3'b101;
                                3'b010:  HBURST = 3'b111;
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
                        HTRANS = dma_mode ? HTRANS_SEQ : HTRANS_NONSEQ;
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
                        HTRANS = dma_mode ? HTRANS_SEQ : HTRANS_NONSEQ;
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
        | remaining == 0 ? ------ yes ---> DMA_DONE ---> DMA_IDLE
        | no
        v
        DMA_READ_ADDR ...

        DMA_ERROR ---> DMA_IDLE

        */
        always_comb begin
                next_state = current_state;

                case (current_state)

                DMA_IDLE:
                        if (dma_start) next_state = DMA_SETUP;

                DMA_SETUP: begin
                        if (dma_abort) 
                                next_state = DMA_ERROR;
                        else begin
                                if(length_cfg == 0) next_state = DMA_ERROR; 
                                else if (!addr_in_range(src_addr_cfg, SRAM0_BASE, SRAM_SIZE) || !addr_in_range(dst_addr_cfg, SRAM1_BASE, SRAM_SIZE)) next_state = DMA_ERROR;
                                else if (!is_word_aligned(src_addr_cfg) || !is_word_aligned(dst_addr_cfg)) next_state = DMA_ERROR;
                                else next_state = DMA_READ_ADDR;
                        end
                end

                DMA_READ_ADDR: begin
                        // if (dma_abort) 
                        //         next_state = DMA_ERROR;
                        // else
                        next_state = DMA_READ_WAIT;
                end

                DMA_READ_WAIT: begin
                        if (HREADY)
                                next_state = DMA_WRITE_ADDR;
                end

                DMA_WRITE_ADDR: begin
                        // if (dma_abort) 
                        //         next_state = DMA_ERROR;
                        // else        
                                next_state = DMA_WRITE_WAIT;
                end

                DMA_WRITE_WAIT: begin
                        if (HREADY)
                                next_state = DMA_UPDATE;
                end

                DMA_UPDATE: begin
                        // if (dma_abort) begin
                        //         next_state = DMA_ERROR; end
                        // else begin
                        if (remaining == 0) // if only 1 word (4 bytes) left to transfer, this transfer will complete the entire transaction, so next state is DONE; otherwise, there are more transfers to do, so next state is READ_ADDR to start the next read
                                next_state = DMA_DONE;
                        else
                                next_state = DMA_READ_ADDR;
                        // end
                end

                DMA_DONE:
                        next_state = DMA_IDLE;

                DMA_ERROR:
                        next_state = DMA_IDLE;

                default:
                        next_state = current_state;

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
                err_code_r <= DMA_ERR_NONE;
                end
                else begin
                        current_state <= next_state;
                        irq_r <= 0;

                        if (dma_abort &&
                                (current_state != DMA_IDLE) &&
                                (current_state != DMA_DONE) &&
                                (current_state != DMA_ERROR)) begin
                                busy_r     <= 1'b0;
                                error_r    <= 1'b1;
                                err_code_r <= DMA_ERR_ABORT;
                        end
                        else begin
                                case (current_state)

                                        DMA_IDLE: begin
                                                busy_r <= 0;

                                                if (dma_start) begin
                                                        done_r <= 0;
                                                        error_r <= 0;
                                                        err_code_r <= DMA_ERR_NONE;
                                                        src_addr  <= src_addr_cfg;
                                                        dst_addr  <= dst_addr_cfg;
                                                        remaining <= length_cfg;
                                                end
                                        end

                                        DMA_SETUP: begin
                                                busy_r <= 1;

                                                if (length_cfg == 0) begin
                                                        busy_r     <= 1'b0;
                                                        error_r    <= 1'b1;
                                                        err_code_r <= DMA_ERR_ZERO_LEN;
                                                end
                                                else if (!is_word_aligned(src_addr_cfg)) begin
                                                        busy_r     <= 1'b0;
                                                        error_r    <= 1'b1;
                                                        err_code_r <= DMA_ERR_SRC_ALIGN;
                                                end
                                                else if (!is_word_aligned(dst_addr_cfg)) begin
                                                        busy_r     <= 1'b0;
                                                        error_r    <= 1'b1;
                                                        err_code_r <= DMA_ERR_DST_ALIGN;
                                                end
                                                else if (!addr_in_range(src_addr_cfg, SRAM0_BASE, SRAM_SIZE) ||
                                                        !addr_in_range(dst_addr_cfg, SRAM1_BASE, SRAM_SIZE)) begin
                                                        busy_r     <= 1'b0;
                                                        error_r    <= 1'b1;
                                                        err_code_r <= DMA_ERR_OUT_OF_RANGE;
                                                end
                                        end

                                        DMA_READ_WAIT: begin
                                                if (dma_abort) begin
                                                        busy_r     <= 1'b0;
                                                        error_r    <= 1'b1;
                                                        err_code_r <= DMA_ERR_ABORT;
                                                end
                                                else if (HRESP == HRESP_ERROR) begin
                                                        busy_r     <= 1'b0;
                                                        error_r    <= 1'b1;
                                                        err_code_r <= DMA_ERR_SLV_RESP;
                                                end
                                                else if (HREADY) begin
                                                        data_reg <= HRDATA; // capture read data into register to be used for write transaction
                                                end
                                        end

                                        DMA_WRITE_WAIT: begin
                                                if (dma_abort) begin
                                                        busy_r     <= 1'b0;
                                                        error_r    <= 1'b1;
                                                        err_code_r <= DMA_ERR_ABORT;
                                                end
                                                else if (HRESP == HRESP_ERROR) begin
                                                        busy_r     <= 1'b0;
                                                        error_r    <= 1'b1;
                                                        err_code_r <= DMA_ERR_SLV_RESP;
                                                end
                                                else if (HREADY) begin
                                                        // After write completes, update source/destination addresses and remaining length for next transfer
                                                        src_addr <= src_addr + 4; // increment source address by word size (4 bytes)
                                                        dst_addr <= dst_addr + 4; // increment destination address by word size (4 bytes)
                                                        remaining <= remaining - 1; // decrement remaining length by word size (4 bytes)
                                                end
                                        end

                                        DMA_UPDATE: begin
                                                // This state is just for updating addresses and counters; no need to set control signals here since the next state will set them as needed based on dma_mode
                                        end

                                        DMA_DONE: begin
                                                busy_r <= 0;
                                                done_r <= 1;
                                                if (dma_irq_en) irq_r <= 1;
                                        end

                                        DMA_ERROR: begin
                                                busy_r <= 0;
                                                error_r <= 1;
                                                if (dma_irq_en) irq_r <= 1;
                                        end

                                        default: begin
                                                // hold
                                        end

                                endcase
                        end
                end
        end

endmodule