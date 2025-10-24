# Tools Directory - Script Reference

Quick reference for all RV1 test and build scripts.

## Main Scripts (Use These)

**Assembly & Build**:
- `assemble.sh` - Convert .s → .hex
- `build_riscv_tests.sh` - Build official tests (one-time setup)

**Test Runners**:
- `test_pipelined.sh` - Run custom tests
- `run_official_tests.sh` - Run compliance tests

**Utilities**:
- `run_test_by_name.sh` - Run test by name
- `run_tests_by_category.sh` - Run by extension (m/a/f/d)
- `check_env.sh` - Verify toolchain

## Quick Examples

```bash
# Run custom test
env XLEN=32 ./tools/test_pipelined.sh fibonacci

# Run all official tests
env XLEN=32 ./tools/run_official_tests.sh all

# Run M extension tests
./tools/run_tests_by_category.sh m
```

See full documentation at: `docs/TESTING_GUIDE.md`
