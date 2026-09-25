# Validation notes — AD Lab script

Checked every command in the class notes. 24 issues found. All are fixed in
`AD-Lab-Runbook.ps1`, and flagged in place in the author's working notes, which
keep the commands exactly as they were written in class.

## Stops the script dead (parse or hard error)

| # | Where | Problem | Fix |
|---|---|---|---|
| 1 | User GPO | `UserGPO = "LAB - User Session Security"` — missing the `$`. PowerShell reads it as a command named `UserGPO`. | `$UserGPO = ...` |
| 2 | LDAP filter queries (3 lines) | Curly quotes `“ ”` from a Word/Teams paste. PowerShell only accepts straight `"`. | straight quotes |
| 3 | Audit test | `-Members "audit. Test"` — a space and wrong case. No such account. | `"audit.test"` |
| 3b | Recycle Bin | `Get-ADUser "recycle. Test"` — same mistake again. | `"recycle.test"` |
| 4 | Stray line | `Unlock an account` sitting on its own line as if it were a command. | removed (it's a heading) |

## Fails silently — the dangerous kind

| # | Where | Problem | Fix |
|---|---|---|---|
| 5 | Workstation GPO link | Misplaced brackets in `if (-not (...))`, so `New-GPLink` never runs. No error, no link, GPO does nothing. | whole pipeline wrapped in `-not ( )` |
| 6 | Forest info | `SchemaMastGet-NetAdapterer` — paste accident. Column returns empty. | `SchemaMaster` |

## Errors out when you reach it

| # | Where | Problem | Fix |
|---|---|---|---|
| 7 | File share | `DL-FinanceShare-Modify` / `-Read` get members added but are never created. | `New-ADGroup` for both, DomainLocal, in `$ResourceGroupsOU` |
| 8 | Privileged report | `Export-Csv` writes to `C:\LabReports\` which may not exist. | folder created first |
| 9 | `gpresult /h` | Needs an output path; errors without one. | `gpresult /h C:\LabReports\gpresult.html` |
| 10 | `whomai /groups` | Typo. | `whoami /groups` |

## Consistency — works, but wrong or fragile

| # | Where | Problem | Fix |
|---|---|---|---|
| 11 | LDAP section | `$UsersOU` redefined with a hardcoded `DC=contoso,DC=com`, overwriting the Part 2 value. | `"OU=LAB-Users,$DomainDN"` |
| 12 | Audit test user | `$InitialPassword` reused, silently clobbering the secure string from Part 5. | renamed `$AuditTestPassword` |
| 12b | Recycle Bin test user | Reused `$InitialPassword` again, by then holding the plaintext lab password. | renamed `$RecycleTestPassword` |
| 13 | `nltest /dsgetdc:lab.local` | Hardcoded `lab.local`, while the rest of the script uses `contoso.com`. | `$DomainName` |
| 14 | Final DNS check | Two `Resolve-DnsName` lines hardcode `contoso.com`. | `$DomainName` |
| 15 | User GPO link | No if-not-exists guard, unlike every other block. Re-running throws "already linked". | guarded to match |
| 16 | Group membership | Four `Add-ADGroupMember` blocks repeated verbatim. | de-duplicated |
| 17 | `Add-KdsRootKey` | Two versions given; running both is wrong. | the `-EffectiveTime` lab version left active, the other commented |

## Left alone deliberately

- `-Filter { PasswordNeverExpires -eq $true }` — script-block filters are valid;
  string filters are preferred style, but this works.
- The hardcoded lab password in the audit section is kept (it's deliberate, so the
  audit test needs no prompt) but marked clearly as lab-only.


## Found in the second batch (regions 19-21)

| # | Where | Problem | Fix |
|---|---|---|---|
| 20 | Audit account | `$UsersOU` redefined as `"OU=Information Technology,OU=LAB-Users,$DomainDN"`, silently repointing it from LAB-Users to a single department. Every later command using `$UsersOU` would target the wrong OU. **The worst kind of bug in the whole set — nothing errors, the wrong thing just quietly happens.** | given its own variable, `$AuditAccountOU` |
| 21 | Audit account | `-UserPrincipalName "adrecon.audit@lab.local"` hardcoded, while the rest of the script uses `$DomainName` (contoso.com). Two different domains in one script. | `"adrecon.audit@$DomainName"` |
| 22 | System state backup | `wbadmin start systemstatebackup` appears twice in a row. Running it twice wastes an hour and a lot of disk. | de-duplicated |
| 23 | DC health | `nltest /dsgetdc:contoso.com` and `Resolve-DnsName "..._msdcs.contoso.com"` hardcoded again after the same fix had already been applied earlier. | `$DomainName` |
| 24 | System state backup | `-backuptarget:E:` assumes an E: volume exists. On a machine without one it fails outright. | `Get-Volume` added before it, with a note to change the letter |

Also removed: 50 `[Thursday HH:MM]` Teams chat markers and the instructor's name,
which were pasted in with the commands.

## One thing that isn't a bug, but read it before you run it

`Enable-ADOptionalFeature` for the **AD Recycle Bin is permanent**. There is no
supported way to turn it back off once enabled. It is still the right call —
just know it is a one-way door before you run region 18.

## Note on how this was checked

Three layers, in increasing order of strength. Be clear about which covers what.

**1. Static reading** — the original pass, across all 694 code lines (the file is
1503 lines; the rest is comment and blank). No curly quotes, every quote
terminated, braces/parens/brackets balanced, no broken line-continuations, all 22
regions opened and closed, no assignment missing its `$`. The logic errors in
issues 5 and 7 were found this way — by reading, not by running.

**2. Parser** — the file has since been through PowerShell's own parser, which
the first pass could not do. **0 parse errors across 4,438 tokens.** Reproducible
on any machine with PowerShell 7:

```powershell
$t=$null; $e=$null
[System.Management.Automation.Language.Parser]::ParseFile(
    './AD-Lab-Runbook.ps1', [ref]$t, [ref]$e) | Out-Null
"$($e.Count) parse errors, $($t.Count) tokens"
```

An AST pass over the same file also confirms no variable is assigned twice
(the bug class behind issues 11, 12 and 20) and none is read before assignment.

**3. A live domain — partially.** Regions 1–8 and 22 were run end to end against
a live **Windows Server 2022** domain by a third party and completed
successfully. **Regions 9–21 have still never been run.** A parser proves the
script is structurally sound; only that live run proves a command does what its
comment claims, and it only proves it for the regions it touched.

### Known limitation: the script is not fully re-runnable

The live run was a first pass against a clean domain. Guard coverage is uneven:

| Command | Guarded with `if (-not (...))` | Unguarded |
|---|--:|--:|
| `New-ADOrganizationalUnit` | 6 | 0 |
| `New-ADGroup` | 4 | 0 |
| `New-GPO` / `New-GPLink` | 4 | 0 |
| `New-ADComputer` | 1 | 0 |
| `New-ADUser` | 1 | 4 |
| `Add-ADGroupMember` | 0 | 12 |
| `Add-KdsRootKey` | 0 | 1 |
| `New-ADServiceAccount` | 0 | 1 |

Re-running a region containing one of the 18 unguarded calls throws rather than
skipping. Most are harmless noise — "already a member", "already exists" — but
`Add-KdsRootKey` in region 13 is not: a second run adds a **second forest root
key**. Check `Get-KdsRootKey` before re-running that region.
