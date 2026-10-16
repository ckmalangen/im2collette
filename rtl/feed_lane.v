`timescale 1ns / 1ps

module feed_lane #(
    parameter integer CHANNEL_INDEX = 0,
    parameter integer BIT_WIDTH     = 8,
    parameter integer BUS_WORDS     = 8,
    parameter integer ADDR_WIDTH    = 8
) (
    input  wire                             clk,
    input  wire                             clear,
    input  wire                             feed_active,
    input  wire                             stream_enable,

    // Bundle: {feed_en, valid, byte_offset, sram_raddr}
    input  wire [ADDR_WIDTH+5:0]            feed_in,
    input  wire [ADDR_WIDTH+5:0]            clear_feed,
    output wire [ADDR_WIDTH+5:0]            feed_out,

    output wire [ADDR_WIDTH-1:0]            sram_raddr,
    input  wire [(BUS_WORDS*BIT_WIDTH)-1:0] sram_rdata_bus,
    output wire [BIT_WIDTH-1:0]             activation_out
);

    // 1. Skew chain: row 0 has zero delay; row c adds c registers
    generate
        if (CHANNEL_INDEX == 0) begin : g_first
            assign feed_out = feed_in;
        end else begin : g_skew
            reg [ADDR_WIDTH+5:0] stage;
            always @(posedge clk) begin
                stage <= clear ? clear_feed : feed_in;
            end
            assign feed_out = stage;
        end
    endgenerate

    // 2. Drive synchronous SRAM read address
    assign sram_raddr = feed_out[ADDR_WIDTH-1:0];

    // 3. Register signals to align with synchronous SRAM read data
    reg [3:0] byte_offset_q;
    reg       rd_valid_q;

    always @(posedge clk) begin
        rd_valid_q    <= feed_out[ADDR_WIDTH+4];
        byte_offset_q <= feed_out[ADDR_WIDTH+3 : ADDR_WIDTH];
    end

    // 4. Unpack wide bus
    wire [BIT_WIDTH-1:0] bus_words [BUS_WORDS-1:0];
    genvar w;
    generate
        for (w = 0; w < BUS_WORDS; w = w + 1) begin : g_unpack
            assign bus_words[w] = sram_rdata_bus[w*BIT_WIDTH +: BIT_WIDTH];
        end
    endgenerate

    wire [BIT_WIDTH-1:0] selected_word = bus_words[byte_offset_q % BUS_WORDS];

    // 5. Gating: feed_out[ADDR_WIDTH+5] is feed_en
    assign activation_out = (feed_active && stream_enable && feed_out[ADDR_WIDTH+5] && rd_valid_q)
                            ? selected_word : {BIT_WIDTH{1'b0}};

endmodule