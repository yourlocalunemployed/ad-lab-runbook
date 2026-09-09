# AI Disclosure

**This runbook was assembled by an AI assistant (Claude, by Anthropic) from a set
of classroom lab notes, directed and reviewed by a human author.**

This file exists because you deserve to know that before you run it against a
domain controller.

---

## What that means in practice

### The good part

- The **commands are real**. They came from a taught Windows Server course, not
  from a model inventing plausible-looking PowerShell. The order they run in is
  the order they were taught.
- The **structure is verified**. All 22 regions open and close, quotes and
  brackets balance, no curly quotes survive in code, and no line continuation is
  broken. That check is reproducible — it is described in `VALIDATION-NOTES.md`.
- The **24 corrections are documented individually**, each marked `# FIXED:` at
  the line it applies to, with the original mistake described. Nothing was
  quietly changed.

### The part to be careful about

- **This has not been executed against a live Active Directory domain.** Not by
  the AI, and not by the author of this repository before publishing. The
  validation was static analysis plus reading.
- **AI-written explanations can be wrong.** They can be subtly wrong in ways that
  read fluently and confidently. A comment may be outdated, oversimplified, or
  true of one Windows Server version and not another.
- Static validation proves the script is **structurally sound**. It does not
  prove any command does what its comment claims on your domain.
- Behaviour varies by Windows Server version, forest and domain functional level,
  installed RSAT version, and tenant policy.

### What this script does to a system

It is not read-only. It creates organisational units, users, groups and computer
accounts; installs Windows features; creates and links Group Policy Objects;
changes NTFS permissions; **changes domain-wide audit policy**; creates a group
managed service account; and — in region 18 — **permanently enables the Active
Directory Recycle Bin, which cannot be undone**.

Read a region before you run it. That is why every command has a note above it.

## Our ask

Run it in a lab. If a comment is wrong, or a command behaves differently on your
build, open an issue — corrections from people who have actually run this on real
infrastructure are worth more than anything static analysis can tell you.
