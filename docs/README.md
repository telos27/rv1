# RV1 Documentation Index

**Project**: RV1 RISC-V Processor (RV32IMAFDC)
**Status**: 100% Compliance (81/81 official tests) ✅
**Last Updated**: 2025-10-23

---

## Quick Start

**New to RV1?** Start here:
1. Read `../START_HERE.md` (root directory)
2. Browse `reference/TEST_CATALOG.md` (all 208 tests)
3. Run `make test-quick` (7-second regression)
4. Explore `guides/` for how-to documentation

---

## Documentation Structure

```
docs/
├── guides/              # User guides (how to use RV1)
├── design/              # Design documentation (how it works)
├── reference/           # Reference docs (detailed specs)
├── sessions/            # Recent session summaries
├── test-infrastructure/ # Testing system docs
├── bugs/                # Bug fixes and lessons learned
├── archive/             # Historical documents (145+ files)
├── control/             # Control signal specifications
└── specs/               # Instruction checklists
```

---

## 📖 Guides (How to Use)

**Purpose**: Practical guides for using and testing RV1

| Document | Description |
|----------|-------------|
| `guides/QUICK_REGRESSION_SUITE.md` | **⚡ START HERE** - 7-second test suite for development |
| `guides/OFFICIAL_COMPLIANCE_TESTING.md` | How to run full 81-test compliance suite |
| `guides/TEST_STANDARD.md` | How to write test programs |
| `guides/PARAMETERIZATION_GUIDE.md` | Configure RV32 vs RV64 mode |

**Use when**: Running tests, writing new tests, configuring the system

---

## 🏗️ Design (How It Works)

**Purpose**: Understand RV1's architecture and design decisions

| Document | Description |
|----------|-------------|
| `design/FORWARDING_ARCHITECTURE.md` | Pipeline forwarding and hazard handling |
| `design/M_EXTENSION_DESIGN.md` | Multiply/Divide extension design |
| `design/A_EXTENSION_DESIGN.md` | Atomic operations design |
| `design/FD_EXTENSION_DESIGN.md` | Floating-point (F/D) extensions (comprehensive) |
| `design/C_EXTENSION_DESIGN.md` | Compressed instructions design |
| `design/MMU_DESIGN.md` | Memory Management Unit (Sv32/Sv39) |
| `design/HEX_FILE_FORMAT.md` | Test vector hex file format |

**Use when**: Understanding internals, adding features, debugging complex issues

**See also**: `../ARCHITECTURE.md` (root) for overall system architecture

---

## 📚 Reference (Detailed Specifications)

**Purpose**: Detailed reference documentation and auto-generated catalogs

| Document | Description |
|----------|-------------|
| `reference/TEST_CATALOG.md` | **⭐ USE THIS** - Auto-generated catalog of all 208 tests |
| `reference/PHASE3_DATAPATH_DIAGRAM.md` | Detailed datapath diagrams |
| `reference/PHASE3_PIPELINE_ARCHITECTURE.md` | Pipeline stage specifications |

**Use when**: Finding specific tests, understanding data flow

---

## 📝 Sessions (Recent Work)

**Purpose**: Recent session summaries (only most important kept here)

| Document | Description |
|----------|-------------|
| `sessions/SESSION25_SUMMARY.md` | Test infrastructure enhancement (current session) |
| `sessions/SESSION24_C_EXTENSION_CONFIG_CLARIFICATION.md` | C extension configuration docs |
| `sessions/SESSION23_100_PERCENT_RV32D.md` | **🎉 100% Compliance achieved!** |

**Older sessions**: See `archive/SESSION_*.md` for complete history

---

## 🧪 Test Infrastructure

**Purpose**: Documentation for the testing system itself

| Document | Description |
|----------|-------------|
| `test-infrastructure/TEST_INFRASTRUCTURE_CLEANUP_REPORT.md` | Infrastructure analysis and improvements |
| `test-infrastructure/TEST_INFRASTRUCTURE_IMPROVEMENTS_COMPLETED.md` | Completed improvements summary |
| `test-infrastructure/TEST_INFRASTRUCTURE_IMPROVEMENTS.md` | Original improvement proposals |

**See also**: `../tools/README.md` for script reference guide

---

## 🐛 Bugs (Fixes and Lessons Learned)

**Purpose**: Understand bugs fixed and avoid repeating them

| Document | Description |
|----------|-------------|
| `bugs/CRITICAL_BUGS.md` | **⭐ READ THIS** - Top 10 critical bugs and quick reference |
| `bugs/BUG_FIXES_SUMMARY.md` | Complete summary of all 54+ bugs fixed |

**Detailed bug docs**: See `archive/BUG*.md` and `archive/FPU_BUG*.md` (30 files)

**Current issues**: See `../KNOWN_ISSUES.md` (root directory)

---

## 📦 Archive (Historical Documents)

**Purpose**: Preserve development history (145+ documents)

The `archive/` directory contains:
- **70+ session summaries**: Day-by-day development progress
- **30+ individual bug fixes**: Detailed debugging sessions
- **25+ phase completions**: Milestone completion reports
- **20+ status documents**: Extension implementation progress

**Organization**:
- `archive/BUG*.md` - Individual bug fix details
- `archive/FPU_BUG*.md` - FPU-specific bug fixes
- `archive/SESSION*.md` - Historical session summaries
- `archive/PHASE*.md` - Phase completion reports
- `archive/*_STATUS.md` - Extension implementation status
- `archive/*_COMPLETE.md` - Milestone completions

**Use when**: Understanding why decisions were made, researching historical bugs

---

## 🎛️ Control & Specs

**Purpose**: Low-level specifications

| Directory | Contents |
|-----------|----------|
| `control/` | Control signal specifications |
| `specs/` | Instruction checklists |

---

## Documentation by Task

### "I want to run tests"
→ Start: `guides/QUICK_REGRESSION_SUITE.md`
→ Then: `guides/OFFICIAL_COMPLIANCE_TESTING.md`

### "I want to find a specific test"
→ Use: `reference/TEST_CATALOG.md`
→ Or run: `grep "keyword" reference/TEST_CATALOG.md`

### "I want to add a new feature"
→ Read: `design/` relevant to your extension
→ Example: Adding B extension? Study `design/M_EXTENSION_DESIGN.md` pattern

### "I want to understand a bug"
→ Start: `bugs/CRITICAL_BUGS.md`
→ Then: `bugs/BUG_FIXES_SUMMARY.md`
→ Details: `archive/BUG*.md`

### "I want to understand the architecture"
→ Start: `../ARCHITECTURE.md` (root)
→ Then: `design/FORWARDING_ARCHITECTURE.md`
→ Details: `design/` specific extensions

### "I want development history"
→ Overview: `../PHASES.md` (root)
→ Recent: `sessions/SESSION*.md`
→ Complete: `archive/SESSION*.md`

### "I want to write a test"
→ Guide: `guides/TEST_STANDARD.md`
→ Examples: `reference/TEST_CATALOG.md`
→ Scripts: `../tools/README.md`

---

## External Documentation

**Root Directory Documentation**:
- `README.md` - Project overview and quick start
- `START_HERE.md` - **Read this first in new sessions**
- `CLAUDE.md` - AI assistant context and project info
- `ARCHITECTURE.md` - Overall system architecture
- `PHASES.md` - Complete development history
- `KNOWN_ISSUES.md` - Current status and issues
- `COMPLIANCE_QUICK_START.md` - Quick compliance test guide

**Tools Documentation**:
- `tools/README.md` - Complete script reference guide

---

## Statistics

### Current Documentation
- **Root docs**: 7 core documents
- **Guides**: 4 how-to documents
- **Design**: 7 architecture documents
- **Reference**: 3 specification documents
- **Sessions**: 3 recent summaries (150+ in archive)
- **Test Infrastructure**: 3 documents
- **Bugs**: 2 summary documents (30+ detailed in archive)
- **Archive**: 145+ historical documents
- **Total**: 186 markdown files

### Test Coverage
- **Total tests**: 208 (127 custom + 81 official)
- **Compliance**: 100% (81/81 tests passing)
- **Extensions**: RV32IMAFDC fully implemented
- **Instructions**: 184+ instructions implemented

---

## Maintenance

### Auto-Generated Documents
These docs are auto-generated and should NOT be manually edited:
- `reference/TEST_CATALOG.md` - Run `make catalog` to regenerate

### Regular Updates
These docs should be kept current:
- `sessions/` - Add new summaries after important milestones
- `bugs/` - Update if major bugs found/fixed
- `../KNOWN_ISSUES.md` - Update as issues resolved
- `../PHASES.md` - Update as phases completed

### Archival Policy
Move to `archive/` when:
- Session docs older than 3 sessions
- Status docs superseded by newer versions
- Planning docs completed/obsolete

---

## Contributing

### Adding Documentation
1. **New guide**: Add to `guides/` with descriptive name
2. **New design doc**: Add to `design/` following existing pattern
3. **Session summary**: Add to `sessions/` (archive after 3 sessions)
4. **Bug fix**: Update `bugs/BUG_FIXES_SUMMARY.md`, detailed doc to `archive/`

### Documentation Standards
- Use markdown format
- Include "Purpose" and "Status" at top
- Add to this README index
- Cross-reference related docs
- Update "Last Updated" date

---

## Quick Reference

**Most Important Docs**:
1. `../START_HERE.md` - Begin here
2. `guides/QUICK_REGRESSION_SUITE.md` - Essential testing workflow
3. `reference/TEST_CATALOG.md` - Find any test
4. `bugs/CRITICAL_BUGS.md` - Learn from mistakes
5. `../ARCHITECTURE.md` - Understand the system

**Most Used Commands**:
```bash
make test-quick              # Quick regression (7s)
make catalog                 # Update test catalog
cat docs/reference/TEST_CATALOG.md  # Browse all tests
grep "keyword" docs/reference/TEST_CATALOG.md  # Find test
```

---

**Last Updated**: 2025-10-23
**Documentation Version**: 2.0 (Reorganized)
**Status**: Production Ready ✅
