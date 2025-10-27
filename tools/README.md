# Tools Directory - Script Reference

Quick reference for all RV1 test and build scripts.

## Main Scripts (Use These)

**Assembly & Build**:
- `asm_to_hex.sh` - Convert .s → .hex (complete pipeline)
- `assemble.sh` - Legacy assembly script
- `build_riscv_tests.sh` - Build official tests (one-time setup)

**Test Runners**:
- `test_pipelined.sh` - Run custom tests ✨ **AUTO-REBUILDS HEX FILES**
- `run_official_tests.sh` - Run compliance tests
- `run_quick_regression.sh` - Quick regression suite (14 tests)

**Utilities**:
- `run_test_by_name.sh` - Run test by name
- `run_tests_by_category.sh` - Run by extension (m/a/f/d)
- `check_env.sh` - Verify toolchain

## ✨ Auto-Rebuild Feature (New!)

**Individual tests automatically rebuild hex files if:**
- Hex file is missing
- Source (.s) file is newer than hex

**No manual intervention needed!** Tests "just work" after:
- Git operations (checkout, pull, etc.)
- Modifying source files
- Switching branches

**Example** (hex file missing, auto-rebuilds):
```bash
$ rm tests/asm/fibonacci.hex
$ env XLEN=32 ./tools/test_pipelined.sh fibonacci
# → Automatically rebuilds fibonacci.hex from fibonacci.s
# → Runs test
```

## Batch Builds

**Smart rebuild** (only rebuild if source changed):
```bash
make rebuild-hex
```

**Force rebuild** (rebuild everything):
```bash
make rebuild-hex-force
```

## Quick Examples

```bash
# Run custom test (auto-rebuilds if needed)
env XLEN=32 ./tools/test_pipelined.sh fibonacci

# Run all official tests
env XLEN=32 ./tools/run_official_tests.sh all

# Quick regression (14 tests, ~3s)
make test-quick

# Smart rebuild all hex files
make rebuild-hex
```

See full documentation at: `docs/TESTING_GUIDE.md`
