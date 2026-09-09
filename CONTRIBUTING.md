# Contributing

Corrections are genuinely welcome, particularly from anyone who has run this
against a real domain.

## The most valuable contributions

1. **A command that doesn't do what its comment says.** This is the highest-value
   report there is. Include your Windows Server version and what actually
   happened.
2. **A command that fails on a build where it should work.** Include the full
   error and your functional level.
3. **A missing `# FIXED:` case** — a mistake still in the script that nobody has
   caught.

## Ground rules for the script

- **Every command gets a plain-English note above it.** No exceptions. A command
  with no explanation is not useful here.
- **Create steps must be idempotent** — wrapped in `if (-not (Get-... )) { }` so
  a second run is a no-op.
- **Nothing hardcodes the domain.** Use `$DomainName` and `$DomainDN`. Two of the
  24 corrections exist because someone typed a domain name by hand.
- **Regions are tagged `[CORE]` or `[OPTIONAL]`.** New material is almost always
  optional; core is the minimum build.
- **Keep `VERIFY` last.** New regions go before it.

## If you change the script, update all three

`AD-Lab-Runbook.ps1`, `ad-lab-runbook.html` and `VALIDATION-NOTES.md` are meant
to describe the same thing. A PR that changes one and not the others will be
asked to fix that.

## Style

- 4-space continuation indent, backtick at end of line with nothing after it.
- Comments explain *why*, not just *what*. `# turn off AutoRun` is less useful
  than explaining that it is a classic malware entry point.
- British or American spelling both fine; be consistent within a block.
