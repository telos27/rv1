# 👋 START HERE - RV1 RISC-V Processor

**New session? Read this first!**

---

## 🎉 Project Status

✅ **100% RISC-V Compliance Achieved!**
- 81/81 official tests passing
- All extensions implemented: I, M, A, F, D, C
- Production-ready 5-stage pipelined core

---

## 🔍 Test Infrastructure - Use These Tools!

### Quick Commands

```bash
# See all available commands
make help

# Browse all 208 tests (127 custom + 81 official)
cat docs/TEST_CATALOG.md

# Check test status
make check-hex

# Run tests
make test-quick                   # ⚡ Quick regression (14 tests in ~7s)
make test-custom-all              # All custom tests
env XLEN=32 make test-all-official  # All official tests

# Regenerate test catalog
make catalog
```

### Key Resources (Read These!)

📋 **Test Catalog** - `docs/reference/TEST_CATALOG.md`
- Auto-generated index of ALL tests
- Categorized by extension (I/M/A/F/D/C/etc.)
- Searchable descriptions
- **USE THIS to find tests instead of searching files!**

🛠️ **Script Guide** - `tools/README.md`
- Reference for all 22 scripts
- Shows main vs. legacy scripts
- Usage examples

📖 **Quick Regression** - `docs/guides/QUICK_REGRESSION_SUITE.md`
- 7-second test suite documentation
- Development workflow
- Time-saving automation

📖 **Documentation Index** - `docs/README.md`
- Complete documentation map
- Find any document quickly

---

## ⚡ Quick Regression Suite (USE THIS!)

**ALWAYS run this before and after making changes:**

```bash
make test-quick
# 14 tests in ~7s - catches 90% of bugs!
```

**Development Workflow:**
1. `make test-quick` → Establish baseline (should be all ✓)
2. Make your changes to RTL
3. `make test-quick` → Verify no regressions
4. If ✓: Continue development
5. If ✗: Debug immediately (don't continue!)
6. Before commit: `env XLEN=32 ./tools/run_official_tests.sh all`

**Why use quick tests:**
- ⚡ 11x faster than full suite (7s vs 80s)
- ⚡ Tests all extensions (I/M/A/F/D/C)
- ⚡ Catches most common bugs
- ⚡ Instant feedback

---

## 🚀 Common Tasks

### Running Tests

**Single test:**
```bash
env XLEN=32 ./tools/test_pipelined.sh test_fp_basic
```

**All official tests:**
```bash
env XLEN=32 ./tools/run_official_tests.sh all
```

**Specific extension:**
```bash
make test-m    # M extension
make test-f    # F extension
make test-d    # D extension
```

### Managing Hex Files

**Check for missing files:**
```bash
make check-hex
```

**Rebuild all hex files:**
```bash
make rebuild-hex
```

**Clean generated files:**
```bash
make clean-hex
```

### Finding Tests

**Don't search manually!** Use the catalog:
```bash
cat docs/reference/TEST_CATALOG.md
# or search within it:
grep "floating" docs/reference/TEST_CATALOG.md
```

---

## 📚 Documentation Structure

```
docs/
├── README.md                           # ⭐ Documentation index - START HERE
├── guides/                             # How-to guides
│   ├── QUICK_REGRESSION_SUITE.md      # ⚡ 7-second test suite
│   ├── OFFICIAL_COMPLIANCE_TESTING.md # Full compliance testing
│   ├── TEST_STANDARD.md               # How to write tests
│   └── PARAMETERIZATION_GUIDE.md      # RV32/RV64 configuration
├── reference/                          # Reference docs
│   ├── TEST_CATALOG.md                # ⭐ All 208 tests indexed
│   ├── PHASE3_DATAPATH_DIAGRAM.md     # Datapath diagrams
│   └── PHASE3_PIPELINE_ARCHITECTURE.md  # Pipeline specs
├── design/                             # Architecture docs
│   ├── M_EXTENSION_DESIGN.md          # Multiply/Divide
│   ├── A_EXTENSION_DESIGN.md          # Atomic operations
│   ├── FD_EXTENSION_DESIGN.md         # Floating-point
│   ├── C_EXTENSION_DESIGN.md          # Compressed instructions
│   └── [more...]
├── bugs/                               # Bug documentation
│   ├── CRITICAL_BUGS.md               # Top 10 critical bugs
│   └── BUG_FIXES_SUMMARY.md           # All 54+ bugs fixed
├── sessions/                           # Recent work
│   └── SESSION*.md                     # Latest 3 sessions
└── archive/                            # Historical docs (145+ files)

tools/
└── README.md                           # ⭐ Script reference guide
```

---

## 🎯 What to Do Next

Choose your path:

### 1. **Add New Features**
- B Extension (Bit Manipulation)
- V Extension (Vector Operations)
- K Extension (Cryptography)
- Performance enhancements

### 2. **Improve Testing**
- CI check script (automated pre-commit)
- Quick regression suite (10 tests in 10s)
- Test coverage matrix
- Parallel test execution

### 3. **Hardware Deployment**
- FPGA synthesis
- Peripheral interfaces (UART, GPIO, SPI)
- Boot ROM and bootloader
- Run Linux or xv6-riscv

See `docs/test-infrastructure/TEST_INFRASTRUCTURE_CLEANUP_REPORT.md` for detailed improvement suggestions.

---

## ⚡ Pro Tips

1. **Always run `make help` first** - See what's available
2. **Use the test catalog** - Don't search files manually
3. **Use Makefile targets** - Faster than running scripts directly
4. **Regenerate catalog** - Run `make catalog` after adding tests
5. **Check hex files** - Run `make check-hex` before testing

---

## 🤖 For AI Assistants

**Before doing ANYTHING with tests:**

1. Run `make help` - See available commands
2. Read `docs/README.md` - Documentation index
3. Browse `docs/reference/TEST_CATALOG.md` - See all tests
4. Check `tools/README.md` - Understand scripts

**Don't:**
- ❌ Search for test files manually
- ❌ Try to figure out which script to use
- ❌ Guess command syntax

**Do:**
- ✅ Use the catalog to find tests
- ✅ Use Makefile targets
- ✅ Check documentation first

---

## 📞 Help & Feedback

- Documentation index: See `docs/README.md`
- Run tests: See `tools/README.md`
- Architecture: See `ARCHITECTURE.md`
- Development history: See `PHASES.md`
- Project context: See `CLAUDE.md`
- Bug history: See `docs/bugs/CRITICAL_BUGS.md`

---

**Last Updated**: 2025-10-23
**Status**: Production Ready - 100% Compliance ✅
**Total Tests**: 208 (127 custom + 81 official)
