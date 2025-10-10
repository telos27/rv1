# Documentation Directory

This directory contains all design documentation for the RV1 processor.

## Subdirectories

### datapaths/
Contains datapath diagrams for each implementation phase:
- `phase1_single_cycle.svg` - Single-cycle datapath
- `phase2_multi_cycle.svg` - Multi-cycle datapath with FSM
- `phase3_pipeline.svg` - 5-stage pipeline diagram

### control/
Contains control logic documentation:
- `control_signals.md` - Complete control signal table
- `instruction_decode.md` - Instruction decoding logic
- `fsm_states.md` - FSM state diagrams (Phase 2)
- `hazard_logic.md` - Hazard detection and forwarding (Phase 3)

### specs/
Additional specification documents:
- `memory_map.md` - Memory address mapping
- `register_map.md` - Register file details
- `extensions.md` - Extension-specific documentation
- `timing_analysis.md` - Critical path analysis

## File Formats

- Use Markdown (.md) for text documentation
- Use SVG for diagrams (vector graphics)
- Use Verilog-style comments for code snippets
- Keep diagrams simple and clear
