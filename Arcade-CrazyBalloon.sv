//============================================================================
//  Arcade: CrazyBalloon
//
//  Mike Coates 
//
//  version 001 initial release - 15/06/2020
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	input         CLK_AUDIO, // 24.576 MHz	
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,    // 1 - signed audio samples, 0 - unsigned

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign USER_OUT  = 1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign AUDIO_S   = 1;

assign HDMI_ARX = status[1] ? 8'd16 : (status[2]) ? 8'd4 : 8'd3;
assign HDMI_ARY = status[1] ? 8'd9  : (status[2]) ? 8'd3 : 8'd4;

`include "build_id.v" 
localparam CONF_STR = {
	"A.CRBALLOON;;",
   "OOR,CRT H adjust,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
   "OSV,CRT V adjust,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H0O1,Aspect Ratio,Original,Wide;",
	"H1H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Fire,Start 1P,Start 2P,Coin;",
	"jn,A,Start,Select,R,L;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_vid;
reg  [1:0] clk_div = 2'd0;
wire cpu_clk = clk_div[1];		// 2.49675 Mhz
wire pix_clk = clk_div[0];		// 4.9935  Mhz
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_vid),			// 39.948 Mhz
	.outclk_1(clk_sys), 			// 9.987 Mhz
	.locked(pll_locked)
);

// Divider for other clocks (7474 and 74161 on PCB)
always @(posedge clk_sys) begin
	clk_div <= clk_div + 1;
end

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;

wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.status_menumask({1'd0,direct_video}),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joy1),
	.joystick_1(joy2),
	.ps2_key(ps2_key)
);


// Dip switches from MRA file
reg [7:0] sw[8];
always @(posedge clk_sys) if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;


// Keyboard
wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
wire [15:0] joy1, joy2;
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right
			'h029: btn_fire        <= pressed; // space
			'h014: btn_fire        <= pressed; // ctrl

			'h005: btn_start_1     <= pressed; // F1
			'h006: btn_start_2     <= pressed; // F2
			'h004: btn_coin        <= pressed; // F3
			'h00C: btn_cheat       <= pressed; // F4

			// JPAC/IPAC/MAME Style Codes
			'h016: btn_start_1     <= pressed; // 1
			'h01E: btn_start_2     <= pressed; // 2
			'h02E: btn_coin_1      <= pressed; // 5
			'h036: btn_coin_2      <= pressed; // 6
			'h02D: btn_up_2        <= pressed; // R
			'h02B: btn_down_2      <= pressed; // F
			'h023: btn_left_2      <= pressed; // D
			'h034: btn_right_2     <= pressed; // G
			'h01C: btn_fire_2      <= pressed; // A
		endcase
	end
end

reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_coin  = 0;
reg btn_fire  = 0;
reg btn_cheat = 0;

reg btn_start_1=0;
reg btn_start_2=0;
reg btn_coin_1=0;
reg btn_coin_2=0;
reg btn_up_2=0;
reg btn_down_2=0;
reg btn_left_2=0;
reg btn_right_2=0;
reg btn_fire_2=0;

// Combined buttons
wire B1_S = btn_start_1 | joy1[4];
wire B2_S = btn_start_2 | joy1[5];
wire B1_C = btn_coin | btn_coin_1 | joy1[6];

wire B1_U = btn_up | joy1[3];
wire B1_D = btn_down | joy1[2];
wire B1_L = btn_left | joy1[1];
wire B1_R = btn_right | joy1[0];

wire B2_U = btn_up_2 | joy2[3];
wire B2_D = btn_down_2 | joy2[2];
wire B2_L = btn_left_2 | joy2[1];
wire B2_R = btn_right_2 | joy2[0];

wire no_rotate = status[2] | direct_video;

wire hblank, vblank;
wire hs, vs;
wire [1:0] r,g,b;

wire [ 3:0] hoffset, voffset;
assign { voffset, hoffset } = status[31:24];

arcade_video #(260,224,6) arcade_video
(
	.*,

	.clk_video(clk_vid),
	.ce_pix(pix_clk),

	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.rotate_ccw(1),
	.fx(status[5:3])
);

wire [15:0] audio;
assign AUDIO_L = audio;
assign AUDIO_R = audio;

CRAZYBALLOON crazy 
(
	.O_VIDEO_R(r),
	.O_VIDEO_G(g),
	.O_VIDEO_B(b),
	.O_HSYNC(hs),
	.O_VSYNC(vs),
	.O_HBLANK(hblank),
	.O_VBLANK(vblank),
	.I_H_OFFSET(hoffset),
	.I_V_OFFSET(voffset),

	.dn_addr(ioctl_addr[15:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr && !ioctl_index),
	.dn_ld(ioctl_download),

	.O_AUDIO(audio),

	.dipsw1(sw[0]),
	.in0({~B2_R,~B2_L,~B2_D,~B2_U,~B1_R,~B1_L,~B1_D,~B1_U}),
	.in1({1'd0,B1_C,~B2_S,~B1_S,1'd1,1'd1,1'd1,1'd1}),
	
	.RESET(RESET | ioctl_download | status[0] | buttons[1]),
	.PIX_CLK(pix_clk),
	.CPU_CLK(cpu_clk),
	.CLK(clk_sys)
);

endmodule

