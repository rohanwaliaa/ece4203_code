// ECE4203 Lab 1 — Post-Synthesis Gate-Level Testbench with SDF Annotation
//
// This testbench simulates the *mapped netlist* (not the RTL) and
// annotates it with gate delays from the SDF file produced by OpenSTA.
// The result shows real carry-chain propagation in the GTKWave waveform.
//
// Run:
//   make sim_gl WIDTH=<N>
// which expands to:
//   iverilog -g2012 -D WIDTH=<N> -D SDF_FILE=\"results/netlist_<N>.sdf\" \
//       -o results/sim_gl_<N> \
//       sim/tb_gl.v results/netlist_<N>.v \
//       $SKY130_CELLS/sky130_fd_sc_hd.v \
//       $SKY130_CELLS/primitives.v
//   vvp -M . -msdf results/sim_gl_<N>
//
// Key difference from the RTL testbench:
//   - DUT is the gate-level netlist, not registered_adder.v
//   - $sdf_annotate() is called at time 0 to back-annotate delays
//   - Outputs show non-zero rise/fall times and carry glitches
//   - The VCD waveform reveals the actual carry propagation time

`timescale 1ns/1ps

`ifndef WIDTH
  `define WIDTH 8
`endif

`ifndef PERIOD
  `define PERIOD 4
`endif

// The gate-level netlist still instantiates module registered_adder,
// so we use the same module name.  The netlist file is compiled
// alongside this testbench; registered_adder.v is NOT compiled.

module tb_gl;

    parameter WIDTH      = `WIDTH;
    // Clock period for gate-level sim — use the same period you tested
    // in STA so you can directly compare slack to simulation timing.
    parameter CLK_PERIOD = `PERIOD; // 10 ns default; override with -D

    // ---- DUT signals ----
    reg              clk, rst_n;
    reg  [WIDTH-1:0] a, b;
    reg              cin;
    wire [WIDTH-1:0] sum;
    wire             cout;

    // ---- DUT: gate-level netlist ----
    registered_adder dut (
        .clk(clk), .rst_n(rst_n),
        .a(a), .b(b), .cin(cin),
        .sum(sum), .cout(cout)
    );

    // ---- SDF back-annotation ----
    // $sdf_annotate must be called at simulation time 0, before any
    // clock edges, so the delays are in place from the first transition.
    //
    // The SDF_FILE macro is defined by the Makefile -D flag.
    // The second argument scopes the annotation to the DUT instance.
    //
    // iverilog note: compile with -g2012 and link with the sky130
    // cell models so that $sdf_annotate can find the cell UDP timing.
    initial begin
`ifdef SDF_FILE
        $sdf_annotate(`SDF_FILE, dut);
        $display("SDF annotated: %s", `SDF_FILE);
`else
        $display("WARNING: SDF_FILE not defined — running without delay annotation");
`endif
    end

    // ---- VCD dump ----
    // Open the waveform in GTKWave and zoom into a single clock cycle
    // to see the carry ripple propagating through the adder cells.
    initial begin
`ifdef VCD_FILE
        $dumpfile(`VCD_FILE);
`else
        $dumpfile("results/gl.vcd");
`endif
        $dumpvars(0, tb_gl);
    end

    // ---- Clock ----
    initial clk = 0;
    always #(CLK_PERIOD/2.0) clk = ~clk;

    // ---- Test tracking ----
    integer errors = 0;
    integer tests  = 0;

    // Same 2-cycle latency as RTL: input reg (cycle 1) + output reg (cycle 2).
    // With SDF annotation the outputs will have non-zero propagation delay
    // after the clock edge — sample at CLK_PERIOD*0.9 after the edge
    // (i.e., just before the next edge) to avoid metastability window.
    task apply_and_check;
        input [WIDTH-1:0] in_a, in_b;
        input             in_cin;
        input [WIDTH-1:0] exp_sum;
        input             exp_cout;
        begin
            @(negedge clk);
            a   = in_a;
            b   = in_b;
            cin = in_cin;
            // 2-cycle latency through the pipeline
            @(posedge clk);
            @(posedge clk);
            // Sample near end of cycle — after all gate delays have settled
            #(CLK_PERIOD * 0.8);
            tests = tests + 1;
            if (sum !== exp_sum || cout !== exp_cout) begin
                $display("FAIL  a=%3d b=%3d cin=%0d | sum=%3d cout=%0d (exp %3d/%0d)",
                    in_a, in_b, in_cin, sum, cout, exp_sum, exp_cout);
                errors = errors + 1;
            end else
                $display("PASS  a=%3d b=%3d cin=%0d => sum=%3d cout=%0d",
                    in_a, in_b, in_cin, sum, cout);
        end
    endtask

    // ---- Stimulus ----
    initial begin
        rst_n = 0; a = 0; b = 0; cin = 0;
        repeat(3) @(posedge clk);
        #(CLK_PERIOD * 0.8);
        if (sum !== 0 || cout !== 0) begin
            $display("FAIL  reset: sum=%0d cout=%0d", sum, cout);
            errors = errors + 1;
        end else
            $display("PASS  reset cleared outputs");
        rst_n = 1;

        apply_and_check(8'd10,  8'd20,  1'b0, 8'd30,  1'b0);
        apply_and_check(8'd200, 8'd100, 1'b0, 8'd44,  1'b1);
        apply_and_check(8'd255, 8'd255, 1'b1, 8'd255, 1'b1);
        apply_and_check(8'd127, 8'd127, 1'b1, 8'd255, 1'b0);
        apply_and_check(8'd42,  8'd58,  1'b0, 8'd100, 1'b0);

        repeat(4) @(posedge clk);
        $display("\n%0d/%0d tests passed (gate-level + SDF).", tests - errors, tests);
        $finish_and_return(errors);
    end

endmodule
