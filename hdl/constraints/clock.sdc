// On-board 27MHz crystal oscillator (Tang Nano 9K, pin 52)
// Period: 1 / 27_000_000 ≈ 37.037 ns, 50% duty
create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk}]
