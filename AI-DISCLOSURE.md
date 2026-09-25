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
- The **structure is verified by a parser**, not just by reading. The file was
  run through PowerShell's own `[Parser]::ParseFile()`: **0 parse errors across
  4,438 tokens**. All 22 regions open and close, quotes and brackets balance, no
  curly quote survives anywhere in executable code, and no line continuation is
  broken. That check is reproducible — `VALIDATION-NOTES.md` gives the command.
- The **24 corrections are documented**, 20 of them marked `# FIXED:` inline at
  the line they apply to, with the original mistake described. Four are not
  marked inline — the removed stray heading, the de-duplicated system-state
  backup, the commented-out alternative `Add-KdsRootKey`, and the added
  `Get-Volume` check — because each removed or replaced the line that would have
  carried the marker. All four are in `VALIDATION-NOTES.md`. Nothing was quietly
  changed.

### The part to be careful about

- **The core build has now been run against a live domain; the rest has not.**
  Regions 1–8 plus 22 — the OUs, users, groups, computers and the verification
  pass — were run successfully end to end against a live **Windows Server 2022**
  domain by a third party, not by the author and not by the AI. **Regions 9–21
  have still never been executed anywhere**: Group Policy, NTFS permissions,
  account lifecycle, delegation, the gMSA, LDAP filtering, auditing, DC health,
  the Recycle Bin, backup and reporting remain static analysis only.
- **That run was a first pass on a clean domain, and parts of this script are not
  re-runnable.** OUs, groups and GPOs are guarded with `if (-not (...))` and skip
  if they already exist. 18 other commands are not: `Add-ADGroupMember` errors
  when the member is already there, `New-ADUser` when the account exists, and
  `Add-KdsRootKey` in region 13 would add a *second* forest root key. Run each
  region once, or check before re-running.
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
