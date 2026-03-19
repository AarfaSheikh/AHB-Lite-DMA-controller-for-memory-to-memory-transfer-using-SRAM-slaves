/*
    1. apply reset
    2. initialize source SRAM with known values
    3. program DMA inputs
    4. pulse dma_start
    5. wait for dma_done
    6. check destination SRAM contents
*/

`timescale 1ns/1ps

module tb_top_level_system;

import dma_defs_pkg::*;

    // Clock and reset
    logic HCLK;
    logic HRESETn;

    // DMA control signals
    logic dma_start;
    logic dma_irq_en;
    logic dma_abort;
    logic dma_mode; // 0 - single transfer, 1 - burst transfer
    logic [2:0] burst_length_cfg; // Valid if dma_mode = 1; Encodings: 000- 4-beat, 001 - 8-beat, 010 - 16-beat
    logic [ADDR_W-1:0] src_addr_cfg;
    logic [ADDR_W-1:0] dst_addr_cfg;
    logic [DATA_W-1:0] length_cfg; // Number of bytes to transfer
    
    // DMA Status outputs
    logic dma_busy;
    logic dma_done;
    logic dma_error;
    logic [3:0] dma_error_code;
    logic dma_irq;

    // Instantiate the top-level system
    top_level_system dut (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .dma_start(dma_start),
        .dma_irq_en(dma_irq_en),
        .dma_abort(dma_abort),
        .dma_mode(dma_mode),
        .burst_length_cfg(burst_length_cfg),
        .src_addr_cfg(src_addr_cfg),
        .dst_addr_cfg(dst_addr_cfg),
        .length_cfg(length_cfg),
        .dma_busy(dma_busy),
        .dma_done(dma_done),
        .dma_error(dma_error),
        .dma_error_code(dma_error_code),
        .dma_irq(dma_irq)
    );

    // Clock generation
    initial begin
        HCLK = 0;
        forever #5 HCLK = ~HCLK; // 100MHz clock
    end

    // Reset task
    task apply_reset;
        begin
            HRESETn = 1'b0;
            dma_start = 1'b0;
            dma_irq_en = 1'b0;
            dma_abort = 1'b0;
            dma_mode = 1'b0;
            burst_length_cfg = 3'b000;
            src_addr_cfg = '0;
            dst_addr_cfg = '0;
            length_cfg = '0;

            repeat (3) @(posedge HCLK);
            HRESETn = 1'b1;
            @(posedge HCLK);
        end
    endtask

    // ============================================================
    // Initialize source SRAM
    // ============================================================
    task init_source_sram(input int num_words);
        int i;
        begin
            for (i = 0; i < num_words; i++) begin
                dut.u_sram0.sram[i] = 32'hA5000000 + i;
                dut.u_sram1.sram[i] = 32'h00000000;
            end
        end
    endtask

    // ============================================================
    // Start DMA transfer
    // ============================================================
    task start_dma_transfer(
        input logic mode_i,
        input logic [2:0] burst_len_i,
        input logic [ADDR_W-1:0] src_addr_i,
        input logic [ADDR_W-1:0] dst_addr_i,
        input logic [DATA_W-1:0] length_i
    );
    begin
        @(posedge HCLK);
        dma_mode         <= mode_i;
        burst_length_cfg <= burst_len_i;
        src_addr_cfg     <= src_addr_i;
        dst_addr_cfg     <= dst_addr_i;
        length_cfg       <= length_i;
        dma_irq_en       <= 1'b1;
        dma_abort        <= 1'b0;

        dma_start        <= 1'b1;
        @(posedge HCLK);
        dma_start        <= 1'b0;
    end
    endtask

    task wait_for_completion;
    begin
        wait (dma_done == 1'b1 || dma_error == 1'b1);
        @(posedge HCLK);
    end
    endtask

     // ============================================================
    // Check destination SRAM contents
    // ============================================================
    task check_destination_sram(input int num_words);
        int i;
    begin
        for (i = 0; i < num_words; i++) begin
            if (dut.u_sram1.sram[i] !== (32'hA5000000 + i)) begin
                $display("ERROR: SRAM1[%0d] = %h, expected %h",
                         i, dut.u_sram1.sram[i], (32'hA5000000 + i));
            end
            else begin
                $display("PASS: SRAM1[%0d] = %h", i, dut.u_sram1.sram[i]);
            end
        end
    end
    endtask

     task expect_error(input logic [3:0] expected_err);
    begin
        if (!dma_error) begin
            $display("ERROR: Expected dma_error=1, got 0");
        end
        else if (dma_error_code !== expected_err) begin
            $display("ERROR: Expected error code %0d, got %0d",
                     expected_err, dma_error_code);
        end
        else begin
            $display("PASS: Expected error code %0d observed", expected_err);
        end
    end
    endtask

    // ============================================================
    // Main stimulus
    // ============================================================
    initial begin
        $display("======================================");
        $display("Starting DMA memory-to-memory testbench");
        $display("======================================");

        apply_reset();

        // --------------------------------------------------------
        // TEST 1: Single transfer basic copy
        // --------------------------------------------------------
        $display("\nTEST 1: Single transfer basic copy");
        clear_srams(16);
        init_source_sram(8, 32'hA5000000);

        start_dma_transfer(
            1'b0,        // single mode
            3'b000,      // ignored
            SRAM0_BASE,
            SRAM1_BASE,
            8            // 8 words
        );

        wait_for_completion();

        if (dma_error) begin
            $display("TEST 1 FAILED: unexpected dma_error, code=%0d", dma_error_code);
        end
        else begin
            $display("DMA DONE!");
            check_destination_sram(8, 32'hA5000000);
        end

        // --------------------------------------------------------
        // TEST 2: Burst mode transfer (INCR4)
        // --------------------------------------------------------
        apply_reset();
        $display("\nTEST 2: Burst mode transfer (INCR4)");
        clear_srams(16);
        init_source_sram(8, 32'hB6000000);

        start_dma_transfer(
            1'b1,        // burst mode
            3'b000,      // INCR4
            SRAM0_BASE,
            SRAM1_BASE,
            8
        );

        wait_for_completion();

        if (dma_error) begin
            $display("TEST 2 FAILED: unexpected dma_error, code=%0d", dma_error_code);
        end
        else begin
            $display("DMA DONE!");
            check_destination_sram(8, 32'hB6000000);
        end

        // --------------------------------------------------------
        // TEST 3: Zero-length transfer
        // --------------------------------------------------------
        apply_reset();
        $display("\nTEST 3: Zero-length transfer");

        start_dma_transfer(
            1'b0,
            3'b000,
            SRAM0_BASE,
            SRAM1_BASE,
            0
        );

        wait_for_completion();
        expect_error(DMA_ERR_ZERO_LEN);

        // --------------------------------------------------------
        // TEST 4: Misaligned source address
        // --------------------------------------------------------
        apply_reset();
        $display("\nTEST 4: Misaligned source address");

        start_dma_transfer(
            1'b0,
            3'b000,
            SRAM0_BASE + 1,
            SRAM1_BASE,
            4
        );

        wait_for_completion();
        expect_error(DMA_ERR_SRC_ALIGN);

        // --------------------------------------------------------
        // TEST 5: Misaligned destination address
        // --------------------------------------------------------
        apply_reset();
        $display("\nTEST 5: Misaligned destination address");

        start_dma_transfer(
            1'b0,
            3'b000,
            SRAM0_BASE,
            SRAM1_BASE + 2,
            4
        );

        wait_for_completion();
        expect_error(DMA_ERR_DST_ALIGN);

        // --------------------------------------------------------
        // TEST 6: Out-of-range source address
        // --------------------------------------------------------
        apply_reset();
        $display("\nTEST 6: Out-of-range source address");

        start_dma_transfer(
            1'b0,
            3'b000,
            32'h3000_0000,
            SRAM1_BASE,
            4
        );

        wait_for_completion();
        expect_error(DMA_ERR_OUT_OF_RANGE);

        // --------------------------------------------------------
        // TEST 7: Out-of-range destination address
        // --------------------------------------------------------
        apply_reset();
        $display("\nTEST 7: Out-of-range destination address");

        start_dma_transfer(
            1'b0,
            3'b000,
            SRAM0_BASE,
            32'h4000_0000,
            4
        );

        wait_for_completion();
        expect_error(DMA_ERR_OUT_OF_RANGE);

        // --------------------------------------------------------
        // TEST 8: Abort during transfer
        // --------------------------------------------------------
        apply_reset();
        $display("\nTEST 8: Abort during transfer");
        clear_srams(16);
        init_source_sram(8, 32'hC7000000);

        start_dma_transfer(
            1'b0,
            3'b000,
            SRAM0_BASE,
            SRAM1_BASE,
            8
        );

        // Assert abort after a few cycles
        repeat (3) @(posedge HCLK);
        dma_abort <= 1'b1;
        @(posedge HCLK);
        dma_abort <= 1'b0;

        wait_for_completion();
        expect_error(DMA_ERR_ABORT);

        $display("\n======================================");
        $display("All planned tests completed");
        $display("======================================");

        #20;
        $finish;
    end


    
    endmodule


/* Add tests for:- 
    1. burst mode test
    2. zero-length error test
    3. misaligned address test
    4. out-of-range address test
    5. abort test
*/