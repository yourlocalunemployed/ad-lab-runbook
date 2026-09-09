# 🗂️ Active Directory Lab Runbook

A PowerShell runbook that builds a **Windows Server Active Directory lab from
scratch** — OUs, users, groups, computers, Group Policy, a file share,
delegation, a gMSA, auditing, backup and reporting — with a plain-English note
above every single command explaining what it actually does.

**All of the commands in this script were obtained through a class lecture.** The
commands themselves, and the order they run in, come from a taught Windows Server
course. What was added afterwards is the explanation above each command, the
structure, and the corrections.

It exists because most AD scripts you find are either a wall of commands with no
explanation, or an explanation with no runnable script. This is both, in the
order the commands have to run.

```
  1-8 CORE  ──►  9-21 OPTIONAL  ──►  22 VERIFY
  the build      the real world      prove it worked
```

---

## Two ways to use it

**Regions 1–8 plus 22** are the core: a complete, working Active Directory
structure. Run those, jump to 22 to verify, and you have a functioning domain.

**Regions 9–21** are everything past that — Group Policy, NTFS permissions,
account lifecycle, delegation, group managed service accounts, LDAP filtering,
auditing, privileged-access review, DC health, the Recycle Bin, backup, CSV
reporting, and a read-only account for assessment tooling.

Every region is tagged `[CORE]` or `[OPTIONAL]` in the file itself.

## Quick start

Requires a **Windows Server domain controller** (or a member server with RSAT),
an **elevated** PowerShell session, and **Domain Admin** rights.

```powershell
git clone https://github.com/yourlocalunemployed/ad-lab-runbook.git
cd ad-lab-runbook
```

> ### ⚠ Do not press F5
>
> Run this **one region at a time** — highlight a block and press F8 in the ISE,
> or paste it into the console. Several commands prompt for input, install
> Windows features, change domain-wide audit policy, or (region 18) make a
> permanent, irreversible change to the forest.

Regions 1–3 must run before anything else: they set the variables everything
below depends on. Variables die with the window, so if you close PowerShell,
re-run them.

## What's in the box

| File | What it is |
|---|---|
| `AD-Lab-Runbook.ps1` | The runbook. 22 regions, ~700 lines of commands, every one annotated. |
| `ad-lab-runbook.html` | The same content as a browsable page — sticky navigation, copy buttons, an AGDLP diagram and the OU tree. Open it in any browser. |
| `VALIDATION-NOTES.md` | Every mistake found in the original class notes, what it did, and how it was fixed. |

## It's safe to re-run

Every create step is wrapped in *if it doesn't exist, make it*:

```powershell
if (-not (Get-ADOrganizationalUnit ...)) { New-ADOrganizationalUnit ... }
```

Run a region twice and the second run creates nothing and errors on nothing.
That property is called idempotence, and it's the habit that separates a script
from a one-off.

## The 24 corrections

The source material was classroom notes, and notes accumulate mistakes. All 24
are fixed here and marked with a `# FIXED:` comment where they occur — so you
can see what was wrong, not just get a working script. `VALIDATION-NOTES.md` has
the full list.

The instructive ones:

- **Two failed silently.** Misplaced brackets meant `New-GPLink` never ran, so a
  GPO was created but never linked and did nothing at all. And `$UsersOU` was
  redefined partway through to a single department OU, silently repointing every
  later command at the wrong place. Neither produced an error.
- **Three wouldn't parse.** Curly `“ ”` quotes from a word processor, pasted into
  LDAP filters. PowerShell only accepts straight `"`. This is the single most
  common paste problem there is.
- **Four errored on contact.** Groups used but never created, `Export-Csv`
  writing to a folder that didn't exist, `gpresult /h` with no output path.

## Honest limitations

- **This has not been run against a live domain by the author of this
  repository.** It was validated *statically* — balanced quotes and brackets, no
  curly quotes, no broken line continuations, all 22 regions opened and closed,
  no assignment missing its `$`. The logic bugs above were found by reading.
- **Test it in a lab before you point it at anything you care about.** It creates
  users, groups, computers and GPOs, changes audit policy, and region 18 makes a
  permanent change to the forest.
- Region 19 assumes an `E:` volume for the system state backup. Change it.

See [AI-DISCLOSURE.md](AI-DISCLOSURE.md) for how this was produced.

## Licence

MIT — see [LICENSE](LICENSE).
