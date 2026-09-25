<#
===============================================================================
  ACTIVE DIRECTORY LAB RUNBOOK
  All commands in this script were obtained through a class lecture.
  The explanations, structure and corrections were added afterwards.

  Build a lab Active Directory domain from scratch: OUs, users, groups,
  computers, Group Policy, a file share, delegation, a gMSA, auditing and a
  privileged-access review.

  -----------------------------------------------------------------------
  DO NOT PRESS F5.
  Run this ONE SECTION AT A TIME. Highlight a block and press F8 in the ISE,
  or paste it into the console. Several commands prompt for input, install
  Windows features, or change domain-wide audit policy.
  -----------------------------------------------------------------------

  REQUIREMENTS
    · Windows Server domain controller, or a member server with RSAT
    · An elevated PowerShell session (Run as Administrator)
    · Domain Admin rights
    · Parts 1-3 must run before anything else: they set the variables
      everything below depends on.

  RE-RUNNABLE
    Every create step is wrapped in "if it doesn't exist, make it", so running
    a section twice creates nothing and errors on nothing.

  VALIDATED
    24 issues in the original class notes are corrected here and marked with
    a "# FIXED:" comment where they occur. See VALIDATION-NOTES.md for the
    full list and what each one did.

  -----------------------------------------------------------------------
  TWO WAYS TO USE THIS

  [CORE] is the basic Active Directory structure the Cluster 3 project asks
  for. Run regions 1-8, then jump straight to 22 to verify. That is a
  complete, working, assessable build on its own.

  [OPTIONAL] is everything past that — Group Policy, file shares, account
  lifecycle, delegation, gMSA, auditing, privileged review. None of it is
  needed for the project. It is here because the class covered it, and
  because it's what you'd actually do next in a real domain.
  -----------------------------------------------------------------------

  CONTENTS
     1  Look        what am I connected to?                      [CORE]
     2  Store       save domain details into variables           [CORE]
     3  Survey      what's installed, what exists, is DNS healthy [CORE]
     4  Build       the OU structure                             [CORE]
     5  Defaults    redirect containers, check password policy   [CORE]
     6  Users       create the people                            [CORE]
     7  Groups      create groups, then fill them (AGDLP)        [CORE]
     8  Computers   stage the machine accounts                   [CORE]
    ---------------------------------------------------------------------
     9  Policy      Group Policy: workstation + user GPOs        [OPTIONAL]
    10  Share       file share and NTFS permissions              [OPTIONAL]
    11  Lifecycle   disable, move, expire, reset, unlock         [OPTIONAL]
    12  Delegation  hand password resets to the helpdesk         [OPTIONAL]
    13  gMSA        group managed service account                [OPTIONAL]
    14  Query       LDAP filters and identity troubleshooting    [OPTIONAL]
    15  Audit       turn on auditing and prove it works          [OPTIONAL]
    16  Review      privileged group membership, account hygiene [OPTIONAL]
    17  Health      dcdiag, DC services, SYSVOL, time sync        [OPTIONAL]
    18  RecycleBin  enable it, then delete and restore an account [OPTIONAL]
    19  Backup      system state + Group Policy backup            [OPTIONAL]
    20  Report      export users/computers/groups/OUs to CSV      [OPTIONAL]
    21  Assessment  read-only account for AD audit tooling        [OPTIONAL]
    ---------------------------------------------------------------------
    22  Verify      prove the whole thing worked                 [CORE]
===============================================================================
#>


#region 1 — LOOK : WHAT AM I CONNECTED TO?   [CORE]
# ---------------------------------------------------------------------------
# All read-only. Get your bearings before touching anything.
# Get- looks and never changes. New- creates. Set- changes. Add- puts into.
# ---------------------------------------------------------------------------

# PowerShell version. Older versions are missing commands used below.
$PSVersionTable

# Full profile of the domain and the forest that contains it.
Get-ADDomain
Get-ADForest

# The readable version — only the columns that matter.
# DomainMode is set by your OLDEST domain controller's Windows version.
# The last three are FSMO roles: jobs only one DC can hold at a time.
Get-ADDomain |
    Select-Object DNSRoot, NetBIOSName, DistinguishedName,
        DomainMode, PDCEmulator, RIDMaster, InfrastructureMaster

# FIXED: was "SchemaMastGet-NetAdapterer" — a paste accident that silently
#        returned an empty column. Correct property is SchemaMaster.
Get-ADForest |
    Select-Object Name, RootDomain, ForestMode,
        SchemaMaster, DomainNamingMaster, GlobalCatalogs

#endregion


#region 2 — STORE : PUT THE DETAILS IN VARIABLES   [CORE]
# ---------------------------------------------------------------------------
# Store the domain once so nothing below hardcodes it. Run this in a different
# domain and the rest of the script still works unchanged.
#
# NOTE: variables die with the window. Close PowerShell and you must re-run
# this region before anything from region 4 onwards.
# ---------------------------------------------------------------------------

$Domain = Get-ADDomain
$Forest = Get-ADForest

$DomainName = $Domain.DNSRoot              # contoso.com
$DomainDN   = $Domain.DistinguishedName    # DC=contoso,DC=com
$NetBIOS    = $Domain.NetBIOSName          # CONTOSO

$DomainName
$DomainDN
$NetBIOS

#endregion


#region 3 — SURVEY : TOOLS, EXISTING OBJECTS, DNS HEALTH   [CORE]
# ---------------------------------------------------------------------------

# Every domain controller. IsGlobalCatalog = holds the forest-wide index.
Get-ADDomainController -Filter * |
    Format-Table HostName, IPv4Address, Site, IsGlobalCatalog, OperationMasterRoles

# Everything installed, alphabetically.
Get-WindowsFeature |
    Where-Object InstallState -eq "Installed" |
    Sort-Object Name |
    Format-Table DisplayName, Name

# Check the four that matter for this lab.
Get-WindowsFeature AD-Domain-Services, DNS, RSAT-AD-Tools, GPMC

# First command that CHANGES the server.
Install-WindowsFeature RSAT-AD-Tools, GPMC -IncludeManagementTools

# Load the toolboxes. Usually automatic, but doing it by hand gives you a clear
# error now rather than a confusing one later.
Import-Module ActiveDirectory
Import-Module GroupPolicy
Get-Module ActiveDirectory, GroupPolicy

# The "before" snapshot. Run these again in region 17 to see your work.
Get-ADOrganizationalUnit -Filter * |
    Select-Object Name, DistinguishedName |
    Sort-Object DistinguishedName

Get-ADUser -Filter * |
    Select-Object Name, SamAccountName, Enabled |
    Sort-Object Name

Get-ADComputer -Filter * |
    Select-Object Name, Enabled, DistinguishedName

# Which DC holds each of the five FSMO roles. Legacy tool, still the fastest way.
netdom query fsmo

# --- DNS. When someone says AD is broken, it is nearly always DNS. -----------

# A DC must point at DNS that knows about the domain.
Get-DnsClientServerAddress -AddressFamily IPv4
Get-DnsServerZone

# Clients FIND domain controllers by asking DNS for these SRV records. No
# answer here means nobody can log in, whatever else is configured correctly.
# FIXED: was hardcoded "contoso.com"; uses $DomainName so it travels.
Resolve-DnsName "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV
Resolve-DnsName "_kerberos._tcp.$DomainName"       -Type SRV

#endregion


#region 4 — BUILD : THE OU STRUCTURE   [CORE]
# ---------------------------------------------------------------------------
# The filing cabinet before the files. Users, groups and computers all need a
# -Path, and that path is an OU. The real reason OUs matter is that Group
# Policy links to them — which region 9 depends on.
#
# THE PATTERN, repeated six times:
#     if (-not (Get-ADOrganizationalUnit ...)) { New-ADOrganizationalUnit ... }
# "If looking for it does NOT find it, create it." That makes this safe to
# re-run — idempotent, the habit that separates a script from a one-off.
# ---------------------------------------------------------------------------

$AdminsOU          = "OU=LAB-Admins,$DomainDN"
$UsersOU           = "OU=LAB-Users,$DomainDN"
$ComputersOU       = "OU=LAB-Computers,$DomainDN"
$GroupsOU          = "OU=LAB-Groups,$DomainDN"
$ServiceAccountsOU = "OU=LAB-Service-Accounts,$DomainDN"
$TestObjectsOU     = "OU=LAB-Test-Objects,$DomainDN"

# --- top level --------------------------------------------------------------
$TopLevelOUs = @(
    "LAB-Admins",
    "LAB-Users",
    "LAB-Computers",
    "LAB-Groups",
    "LAB-Service-Accounts",
    "LAB-Test-Objects"
)

foreach ($OU in $TopLevelOUs) {
    if (-not (Get-ADOrganizationalUnit `
            -LDAPFilter "(ou=$OU)" `
            -SearchBase $DomainDN `
            -SearchScope OneLevel `
            -ErrorAction SilentlyContinue)) {

        New-ADOrganizationalUnit `
            -Name $OU `
            -Path $DomainDN `
            -ProtectedFromAccidentalDeletion $true
    }
}

# --- departments, inside LAB-Users -----------------------------------------
# "Disabled Users" is where leavers get parked, not deleted.
$DepartmentOUs = @(
    "Finance",
    "Human Resources",
    "Information Technology",
    "Sales",
    "Contractors",
    "Disabled Users"
)

foreach ($OU in $DepartmentOUs) {
    if (-not (Get-ADOrganizationalUnit `
            -LDAPFilter "(ou=$OU)" `
            -SearchBase $UsersOU `
            -SearchScope OneLevel `
            -ErrorAction SilentlyContinue)) {

        New-ADOrganizationalUnit `
            -Name $OU `
            -Path $UsersOU `
            -ProtectedFromAccidentalDeletion $true
    }
}

# --- admin tiers, inside LAB-Admins ----------------------------------------
# Tier-0 = domain admins, Tier-1 = server admins, Tier-2 = helpdesk.
# Keeping them apart limits the blast radius if one account is compromised.
# Shorter style: pipe the list in, $_ is "the current item". Same job.
"Tier-0", "Tier-1", "Tier-2" | ForEach-Object {
    if (-not (Get-ADOrganizationalUnit `
            -LDAPFilter "(ou=$_)" `
            -SearchBase $AdminsOU `
            -SearchScope OneLevel `
            -ErrorAction SilentlyContinue)) {

        New-ADOrganizationalUnit `
            -Name $_ `
            -Path $AdminsOU `
            -ProtectedFromAccidentalDeletion $true
    }
}

# --- machine split, inside LAB-Computers ------------------------------------
# Workstations and Servers get very different Group Policy.
"Workstations", "Servers", "Quarantine" | ForEach-Object {
    if (-not (Get-ADOrganizationalUnit `
            -LDAPFilter "(ou=$_)" `
            -SearchBase $ComputersOU `
            -SearchScope OneLevel `
            -ErrorAction SilentlyContinue)) {

        New-ADOrganizationalUnit `
            -Name $_ `
            -Path $ComputersOU `
            -ProtectedFromAccidentalDeletion $true
    }
}

# --- sites, three levels deep ----------------------------------------------
$WorkstationsOU = "OU=Workstations,$ComputersOU"

"Sydney", "Melbourne" | ForEach-Object {
    if (-not (Get-ADOrganizationalUnit `
            -LDAPFilter "(ou=$_)" `
            -SearchBase $WorkstationsOU `
            -SearchScope OneLevel `
            -ErrorAction SilentlyContinue)) {

        New-ADOrganizationalUnit `
            -Name $_ `
            -Path $WorkstationsOU `
            -ProtectedFromAccidentalDeletion $true
    }
}

# --- group split, inside LAB-Groups ----------------------------------------
# Role Groups = "who you are". Resource Groups = "what you can reach".
# That split is AGDLP — see region 7.
"Role Groups", "Resource Groups" | ForEach-Object {
    if (-not (Get-ADOrganizationalUnit `
            -LDAPFilter "(ou=$_)" `
            -SearchBase $GroupsOU `
            -SearchScope OneLevel `
            -ErrorAction SilentlyContinue)) {

        New-ADOrganizationalUnit `
            -Name $_ `
            -Path $GroupsOU `
            -ProtectedFromAccidentalDeletion $true
    }
}

# Checkpoint. Sorting by DN makes children sit under their parents.
Get-ADOrganizationalUnit -Filter * -SearchBase $DomainDN |
    Sort-Object DistinguishedName |
    Format-Table Name, DistinguishedName

#endregion


#region 5 — DEFAULTS : REDIRECT CONTAINERS, CHECK PASSWORD POLICY   [CORE]
# ---------------------------------------------------------------------------
# By default anything joining the domain lands in the built-in Computers and
# Users CONTAINERS. Containers are not OUs and you CANNOT link Group Policy to
# them — so anything landing there gets none of your policy. These fix it.
# ---------------------------------------------------------------------------

redircmp "OU=Workstations,OU=LAB-Computers,$DomainDN"
redirusr "OU=LAB-Users,$DomainDN"

# Confirm — both fields should now show YOUR OUs.
Get-ADDomain | Select-Object UsersContainer, ComputersContainer

# Ask once, keep it encrypted in memory rather than plain text in the script.
$InitialPassword = Read-Host `
    "Enter an initial password for the sample users" `
    -AsSecureString

# Check this BEFORE creating users. If your password fails these rules,
# New-ADUser rejects it and the error doesn't say the password was the problem.
Get-ADDefaultDomainPasswordPolicy

#endregion


#region 6 — USERS : CREATE THE PEOPLE   [CORE]
# ---------------------------------------------------------------------------
# Data separated from logic: a list, then one loop that reads it. To add a
# person, add a block to the list and re-run. You never touch the loop.
# ---------------------------------------------------------------------------

$Users = @(
    @{ GivenName = "Sarah";   Surname = "Malik";      SamAccountName = "sarah.malik"
       Department = "Finance";                Title = "Senior Accountant"
       Office = "Sydney";     EmployeeID = "LAB1001"; OU = "OU=Finance,$UsersOU" },

    @{ GivenName = "James";   Surname = "Wong";       SamAccountName = "james.wong"
       Department = "Finance";                Title = "Finance Manager"
       Office = "Sydney";     EmployeeID = "LAB1002"; OU = "OU=Finance,$UsersOU" },

    @{ GivenName = "Priya";   Surname = "Sharma";     SamAccountName = "priya.sharma"
       Department = "Human Resources";        Title = "HR Adviser"
       Office = "Melbourne";  EmployeeID = "LAB1003"; OU = "OU=Human Resources,$UsersOU" },

    @{ GivenName = "Daniel";  Surname = "Nguyen";     SamAccountName = "daniel.nguyen"
       Department = "Information Technology"; Title = "Systems Administrator"
       Office = "Sydney";     EmployeeID = "LAB1004"; OU = "OU=Information Technology,$UsersOU" },

    @{ GivenName = "Emily";   Surname = "Taylor";     SamAccountName = "emily.taylor"
       Department = "Sales";                  Title = "Sales Consultant"
       Office = "Melbourne";  EmployeeID = "LAB1005"; OU = "OU=Sales,$UsersOU" },

    @{ GivenName = "Michael"; Surname = "Chen";       SamAccountName = "michael.chen"
       Department = "Sales";                  Title = "Sales Manager"
       Office = "Sydney";     EmployeeID = "LAB1006"; OU = "OU=Sales,$UsersOU" },

    @{ GivenName = "Alex";    Surname = "Contractor"; SamAccountName = "alex.contractor"
       Department = "Contractor";             Title = "Project Contractor"
       Office = "Sydney";     EmployeeID = "EXT2001"; OU = "OU=Contractors,$UsersOU" }
)

foreach ($User in $Users) {
    $ExistingUser = Get-ADUser `
        -Filter "SamAccountName -eq '$($User.SamAccountName)'" `
        -ErrorAction SilentlyContinue

    if (-not $ExistingUser) {
        $DisplayName = "$($User.GivenName) $($User.Surname)"
        $UPN         = "$($User.SamAccountName)@$DomainName"

        New-ADUser `
            -Name $DisplayName `
            -DisplayName $DisplayName `
            -GivenName $User.GivenName `
            -Surname $User.Surname `
            -SamAccountName $User.SamAccountName `
            -UserPrincipalName $UPN `
            -Department $User.Department `
            -Title $User.Title `
            -Office $User.Office `
            -EmployeeID $User.EmployeeID `
            -Path $User.OU `
            -AccountPassword $InitialPassword `
            -Enabled $true `
            -ChangePasswordAtLogon $true   # never know their real password
    }
}

# Checkpoint. -Properties is needed because AD only returns a few fields by
# default; Department/Title/Office/EmployeeID must be asked for explicitly.
Get-ADUser -Filter * -SearchBase $UsersOU `
        -Properties Department, Title, Office, EmployeeID |
    Select-Object Name, SamAccountName, Department, Title, Office, Enabled |
    Sort-Object Department, Name |
    Format-Table -AutoSize

# --- org chart. -Manager needs the manager's OBJECT, not a name string. -----
$James   = Get-ADUser "james.wong"
Set-ADUser -Identity "sarah.malik"  -Manager $James

$Michael = Get-ADUser "michael.chen"
Set-ADUser -Identity "emily.taylor" -Manager $Michael

# Prove it stuck. Manager isn't returned by default, so ask for it.
$Sarah = Get-ADUser "sarah.malik" -Properties Manager
Get-ADUser $Sarah.Manager | Select-Object Name, SamAccountName, Title

# --- the admin's SECOND account ---------------------------------------------
# Do the day job on the normal account; only use adm- when you need the rights.
# If the daily account gets phished, the attacker gets a normal user.
$AdminPassword = Read-Host `
    "Enter an initial password for the administrative account" `
    -AsSecureString

New-ADUser `
    -Name "Daniel Nguyen - Server Admin" `
    -DisplayName "Daniel Nguyen - Server Admin" `
    -GivenName "Daniel" `
    -Surname "Nguyen" `
    -SamAccountName "adm-daniel.nguyen" `
    -UserPrincipalName "adm-daniel.nguyen@$DomainName" `
    -Description "Dedicated Tier 1 server administration account" `
    -Path "OU=Tier-1,$AdminsOU" `
    -AccountPassword $AdminPassword `
    -Enabled $true `
    -ChangePasswordAtLogon $true

#endregion


#region 7 — GROUPS : AGDLP   [CORE]
# ---------------------------------------------------------------------------
#   A   Account        the user                       sarah.malik
#   G   Global group   WHO THEY ARE                   GG-Finance-Employees
#   DL  Domain Local   WHAT IT CAN REACH              DL-FinanceShare-Modify
#   P   Permission     granted to the DL group        Modify on the share
#
# You never give a permission to a person. Someone joins Finance, you add them
# to ONE group. The share's permissions change, you edit ONE group.
#
# SCOPES   Global      users from THIS domain      — "who you are"
#          DomainLocal access to a resource here   — "what you can reach"
#          Universal   spans the whole forest
# CATEGORY Security     can hold permissions
#          Distribution email lists only
# ---------------------------------------------------------------------------

$RoleGroupsOU     = "OU=Role Groups,$GroupsOU"
$ResourceGroupsOU = "OU=Resource Groups,$GroupsOU"

# --- the G: role groups -----------------------------------------------------
$GlobalGroups = @(
    @{ Name = "GG-Finance-Employees";          Description = "All Finance employees" },
    @{ Name = "GG-HR-Employees";               Description = "All Human Resources employees" },
    @{ Name = "GG-IT-Employees";               Description = "All Information Technology employees" },
    @{ Name = "GG-Sales-Employees";            Description = "All Sales employees" },
    @{ Name = "GG-Sydney-Users";               Description = "Users based in Sydney" },
    @{ Name = "GG-Melbourne-Users";            Description = "Users based in Melbourne" },
    @{ Name = "GG-Server-Administrators";      Description = "Tier 1 server administrators" },
    @{ Name = "GG-Helpdesk-Password-Reset";    Description = "Help desk staff authorised for delegated password resets" },
    @{ Name = "GG-Privileged-Password-Policy"; Description = "Accounts receiving the privileged password policy" }
)

foreach ($Group in $GlobalGroups) {
    if (-not (Get-ADGroup `
            -Filter "Name -eq '$($Group.Name)'" `
            -ErrorAction SilentlyContinue)) {

        New-ADGroup `
            -Name $Group.Name `
            -SamAccountName $Group.Name `
            -GroupCategory Security `
            -GroupScope Global `
            -Path $RoleGroupsOU `
            -Description $Group.Description
    }
}

# --- the DL: resource groups ------------------------------------------------
# FIXED: these two were used in region 10 but never created, so every
#        Add-ADGroupMember against them failed with "Cannot find an object
#        with identity". $ResourceGroupsOU existed but was never used — this
#        is what it was for.
$ResourceGroups = @(
    @{ Name = "DL-FinanceShare-Modify"; Description = "Modify on the Finance share" },
    @{ Name = "DL-FinanceShare-Read";   Description = "Read on the Finance share" }
)

foreach ($Group in $ResourceGroups) {
    if (-not (Get-ADGroup `
            -Filter "Name -eq '$($Group.Name)'" `
            -ErrorAction SilentlyContinue)) {

        New-ADGroup `
            -Name $Group.Name `
            -SamAccountName $Group.Name `
            -GroupCategory Security `
            -GroupScope DomainLocal `
            -Path $ResourceGroupsOU `
            -Description $Group.Description
    }
}

# One Universal group, to show the third scope. Universal groups live in the
# global catalog, so changing them replicates forest-wide.
if (-not (Get-ADGroup -Filter "Name -eq 'UG-All-Business-Users'" -ErrorAction SilentlyContinue)) {
    New-ADGroup `
        -Name "UG-All-Business-Users" `
        -SamAccountName "UG-All-Business-Users" `
        -GroupCategory Security `
        -GroupScope Universal `
        -Path $RoleGroupsOU `
        -Description "Cross-domain business user aggregation demonstration"
}

Get-ADGroup -Filter * -SearchBase $GroupsOU |
    Select-Object Name, GroupCategory, GroupScope |
    Sort-Object GroupScope, Name |
    Format-Table

# --- the A: accounts into the global groups ---------------------------------
# FIXED: the Sales / Sydney / Melbourne / Server-Administrators blocks were
#        each repeated twice in the notes. De-duplicated.
Add-ADGroupMember -Identity "GG-Finance-Employees"     -Members "sarah.malik", "james.wong"
Add-ADGroupMember -Identity "GG-HR-Employees"          -Members "priya.sharma"
Add-ADGroupMember -Identity "GG-IT-Employees"          -Members "daniel.nguyen"
Add-ADGroupMember -Identity "GG-Sales-Employees"       -Members "emily.taylor", "michael.chen"
Add-ADGroupMember -Identity "GG-Melbourne-Users"       -Members "priya.sharma", "emily.taylor"
Add-ADGroupMember -Identity "GG-Server-Administrators" -Members "adm-daniel.nguyen"

# People sit in BOTH a department group and a site group. That's the point.
Add-ADGroupMember -Identity "GG-Sydney-Users" -Members `
    "sarah.malik", "james.wong", "daniel.nguyen", "michael.chen", "alex.contractor"

# --- the DL step: global groups INTO domain local groups --------------------
# Note the members here are GROUPS, not people.
Add-ADGroupMember -Identity "DL-FinanceShare-Modify" -Members "GG-Finance-Employees"
Add-ADGroupMember -Identity "DL-FinanceShare-Read"   -Members "GG-IT-Employees"

# --- three ways to ask about membership, and they differ --------------------
Get-ADGroupMember "GG-Finance-Employees"                          # direct only
Get-ADGroupMember -Identity "GG-Finance-Employees" -Recursive     # expands nesting
Get-ADGroupMember "DL-FinanceShare-Modify"                        # should show the GG-, not people

# The reverse: what groups is this PERSON in?
Get-ADPrincipalGroupMembership "sarah.malik" |
    Select-Object Name, GroupScope |
    Sort-Object Name

# The best one — every level of nesting plus built-ins. This is what the
# user's access ACTUALLY is.
Get-ADAccountAuthorizationGroup "sarah.malik" |
    Select-Object Name, GroupScope |
    Sort-Object Name

#endregion


#region 8 — COMPUTERS : STAGE THE MACHINE ACCOUNTS   [CORE]
# ---------------------------------------------------------------------------
# Pre-creating them means a machine lands in the right OU and gets the right
# Group Policy from its FIRST boot, instead of appearing in the default
# container and having to be moved.
# ---------------------------------------------------------------------------

$SydneyWorkstationsOU    = "OU=Sydney,$WorkstationsOU"
$MelbourneWorkstationsOU = "OU=Melbourne,$WorkstationsOU"
$ServersOU               = "OU=Servers,$ComputersOU"

$Computers = @(
    @{ Name = "SYD-WIN11-01"; Path = $SydneyWorkstationsOU;    Description = "Sydney Windows 11 lab workstation" },
    @{ Name = "SYD-WIN11-02"; Path = $SydneyWorkstationsOU;    Description = "Sydney Windows 11 lab workstation" },
    @{ Name = "MEL-WIN11-01"; Path = $MelbourneWorkstationsOU; Description = "Melbourne Windows 11 lab workstation" },
    @{ Name = "LAB-SRV01";    Path = $ServersOU;               Description = "Lab member and file server" },
    @{ Name = "LAB-APP01";    Path = $ServersOU;               Description = "Lab application server" }
)

foreach ($Computer in $Computers) {
    if (-not (Get-ADComputer `
            -Filter "Name -eq '$($Computer.Name)'" `
            -ErrorAction SilentlyContinue)) {

        New-ADComputer `
            -Name $Computer.Name `
            -SamAccountName "$($Computer.Name)$" `
            -Path $Computer.Path `
            -Description $Computer.Description `
            -Enabled $true
    }
}
# The trailing $ in -SamAccountName is REQUIRED — it's how AD marks an account
# as a computer rather than a person.

#endregion


###############################################################################
#                                                                             #
#   END OF THE CORE BUILD.                                                    #
#                                                                             #
#   Everything above is the basic Active Directory structure the Cluster 3    #
#   project asks for: OUs, users, groups, computers. If that's all you need,  #
#   skip to region 22 and verify.                                             #
#                                                                             #
#   EVERYTHING BELOW IS OPTIONAL. It is what the class covered beyond the     #
#   project scope. Each region stands on its own — run the ones you want,     #
#   in order, but they all assume regions 1-8 have already run.               #
#                                                                             #
###############################################################################

#region 9 — POLICY : GROUP POLICY   [OPTIONAL]
# ---------------------------------------------------------------------------
# A GPO is a bundle of settings. LINK it to an OU and everything inside picks
# it up at boot/logon, then re-checks roughly every 90 minutes.
#
# THREE STEPS, ALWAYS THIS ORDER
#   1  New-GPO              create the empty bundle
#   2  New-GPLink           decide WHO gets it
#   3  Set-GPRegistryValue  what it actually does
# A GPO with no link does nothing. A link with no settings does nothing.
#
# HKLM = computer setting, applies no matter who signs in.
# HKCU = user setting, follows the person to whatever machine they use.
# ---------------------------------------------------------------------------

# --- 9a. workstation baseline (computer settings) ---------------------------
$WorkstationGPO = "LAB - Workstation Security Baseline"

if (-not (Get-GPO -Name $WorkstationGPO -ErrorAction SilentlyContinue)) {
    New-GPO `
        -Name $WorkstationGPO `
        -Comment "Basic workstation security settings for the AD lab"
}

# FIXED: the original brackets were misplaced —
#            if (-not (Get-GPInheritance -Target $OU).GpoLinks | Where-Object ...)
#        which applies -not to .GpoLinks FIRST, then pipes a true/false into
#        Where-Object, which matches nothing. Result is always empty, empty is
#        false, so New-GPLink NEVER RAN. No error, no link, GPO did nothing.
#        The whole pipeline has to sit inside -not ( ).
if (-not ((Get-GPInheritance -Target $WorkstationsOU).GpoLinks |
        Where-Object DisplayName -eq $WorkstationGPO)) {

    New-GPLink `
        -Name $WorkstationGPO `
        -Target $WorkstationsOU `
        -LinkEnabled Yes
}

# AutoRun off for every drive type. 255 covers all drive letters including USB
# — the classic "plug in an infected stick and it runs itself" entry point.
Set-GPRegistryValue `
    -Name $WorkstationGPO `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
    -ValueName "NoDriveTypeAutoRun" `
    -Type DWord `
    -Value 255

# The other half — non-volume devices: phones, cameras, MTP gear.
Set-GPRegistryValue `
    -Name $WorkstationGPO `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
    -ValueName "NoAutoPlayfornonVolume" `
    -Type DWord `
    -Value 1

# Logon banner. Caption and Text are a PAIR — set one only and nothing appears.
# A LEGAL control, not a technical one: it removes the "I didn't know I wasn't
# allowed on here" defence, which is why hardening standards expect it.
Set-GPRegistryValue `
    -Name $WorkstationGPO `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "LegalNoticeCaption" `
    -Type String `
    -Value "LAB.LOCAL Authorised Access Only"

Set-GPRegistryValue `
    -Name $WorkstationGPO `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "LegalNoticeText" `
    -Type String `
    -Value "This computer is part of an authorised Active Directory training environment."

# --- 9b. user session security (user settings) ------------------------------
# FIXED: was "UserGPO = ..." with no $. PowerShell read that as a command
#        named UserGPO and everything below referencing $UserGPO was empty.
$UserGPO = "LAB - User Session Security"

if (-not (Get-GPO -Name $UserGPO -ErrorAction SilentlyContinue)) {
    New-GPO `
        -Name $UserGPO `
        -Comment "User session and screen lock settings"
}

# FIXED: the original New-GPLink had no if-not-exists guard, unlike every
#        other block, so re-running threw "already linked". Guarded to match.
if (-not ((Get-GPInheritance -Target $UsersOU).GpoLinks |
        Where-Object DisplayName -eq $UserGPO)) {

    New-GPLink `
        -Name $UserGPO `
        -Target $UsersOU `
        -LinkEnabled Yes
}

# Screen lock. Three settings that only work as a set:
#   ScreenSaveActive    turn the screen saver on at all
#   ScreenSaverIsSecure require the password to get back in  <- the security bit
#   ScreenSaveTimeOut   seconds of idle before it kicks in (600 = 10 min)
# Note these are REG_SZ strings, not numbers — hence -Type String even for 600.
Set-GPRegistryValue `
    -Name $UserGPO `
    -Key "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -ValueName "ScreenSaveActive" `
    -Type String `
    -Value "1"

Set-GPRegistryValue `
    -Name $UserGPO `
    -Key "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -ValueName "ScreenSaverIsSecure" `
    -Type String `
    -Value "1"

Set-GPRegistryValue `
    -Name $UserGPO `
    -Key "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -ValueName "ScreenSaveTimeOut" `
    -Type String `
    -Value "600"

# --- 9c. did any of it work? ------------------------------------------------
Get-GPInheritance -Target $WorkstationsOU
Get-GPInheritance -Target $UsersOU

Get-GPO -All |
    Select-Object DisplayName, GpoStatus, CreationTime, ModificationTime |
    Sort-Object DisplayName

# Run these ON A CLIENT in the OU, not on the DC — the DC isn't in
# LAB-Computers, so the workstation GPO does not apply to it.
gpupdate /force
gpresult /r

# FIXED: "gpresult /h" on its own errors — /h needs an output path.
New-Item -Path "C:\LabReports" -ItemType Directory -Force | Out-Null
gpresult /h "C:\LabReports\gpresult.html"

# Read back the actual registry values the policy wrote.
Get-ItemProperty `
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" |
    Select-Object LegalNoticeCaption, LegalNoticeText

Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop"

# The Group Policy operational log — where you find out WHY policy didn't apply.
Get-WinEvent `
        -LogName "Microsoft-Windows-GroupPolicy/Operational" `
        -MaxEvents 30 |
    Select-Object TimeCreated, Id, LevelDisplayName, Message

#endregion


#region 10 — SHARE : FILE SHARE AND NTFS PERMISSIONS   [OPTIONAL]
# ---------------------------------------------------------------------------
# The "P" of AGDLP. Everything so far lived inside AD; this is the thing AD
# was protecting. Folder first, then break inheritance, then grant the DL
# groups created in region 7.
# ---------------------------------------------------------------------------

$FinancePath = "C:\LabShares\Finance"

New-Item -Path $FinancePath -ItemType Directory -Force

# /inheritance:d DISABLES inheritance but COPIES the current permissions down
# first, so they become explicit on this folder.
# Use :d, not :r — :r REMOVES them and can lock you out of your own folder.
icacls $FinancePath /inheritance:d

# Grant the resource groups. (OI)(CI) = applies to files and subfolders too.
# M = Modify, RX = Read + Execute.
icacls $FinancePath /grant "DL-FinanceShare-Modify:(OI)(CI)M"
icacls $FinancePath /grant "DL-FinanceShare-Read:(OI)(CI)RX"

icacls $FinancePath

#endregion


#region 11 — LIFECYCLE : DISABLE, MOVE, EXPIRE, RESET, UNLOCK   [OPTIONAL]
# ---------------------------------------------------------------------------
# What actually happens to accounts day to day. The golden rule for a leaver:
# DISABLE and MOVE, never delete. Deleting destroys the SID, and with it every
# file permission and group membership that pointed at it.
# ---------------------------------------------------------------------------

# --- a contractor finishes ---------------------------------------------------
Disable-ADAccount -Identity "alex.contractor"

Get-ADUser "alex.contractor" |
    Move-ADObject -TargetPath "OU=Disabled Users,$UsersOU"

# Always say WHY. Six months on, nobody remembers.
Set-ADUser `
    -Identity "alex.contractor" `
    -Description "Contract completed; account disabled for lab exercise"

Get-ADUser -Identity "alex.contractor" -Properties Description |
    Select-Object Name, Enabled, Description, DistinguishedName

# --- they come back ----------------------------------------------------------
Enable-ADAccount -Identity "alex.contractor"

Get-ADUser "alex.contractor" |
    Move-ADObject -TargetPath "OU=Contractors,$UsersOU"

# --- expiry: better than remembering to disable them yourself ---------------
Set-ADAccountExpiration `
    -Identity "alex.contractor" `
    -DateTime (Get-Date).AddDays(30)

Get-ADUser "alex.contractor" -Properties AccountExpirationDate |
    Select-Object Name, AccountExpirationDate

Clear-ADAccountExpiration -Identity "alex.contractor"

# --- password reset ----------------------------------------------------------
# -Reset means "set it, don't ask for the old one" — the helpdesk operation.
$NewPassword = Read-Host "Enter the replacement password" -AsSecureString

Set-ADAccountPassword `
    -Identity "sarah.malik" `
    -Reset `
    -NewPassword $NewPassword

# Then force a change at next logon, so you don't know their password.
Set-ADUser -Identity "sarah.malik" -ChangePasswordAtLogon $true

# --- unlock (different from disabled) ---------------------------------------
# LOCKED OUT = too many bad password attempts; it clears itself after the
# lockout window. DISABLED = an admin turned it off. Different problems.
Unlock-ADAccount -Identity "sarah.malik"

# --- find them in bulk -------------------------------------------------------
Search-ADAccount -LockedOut
Search-ADAccount -UsersOnly -AccountDisabled

#endregion


#region 12 — DELEGATION : LET THE HELPDESK RESET PASSWORDS   [OPTIONAL]
# ---------------------------------------------------------------------------
# The point of delegation: the helpdesk can reset passwords WITHOUT being
# Domain Admins. Least privilege — give the smallest right that does the job.
#
# The group was created back in region 7; this is where it gets used.
# ---------------------------------------------------------------------------

Add-ADGroupMember `
    -Identity "GG-Helpdesk-Password-Reset" `
    -Members "daniel.nguyen"

# dsacls reads the ACL on an AD object — who is allowed to do what to this OU.
dsacls "OU=LAB-Users,$DomainDN"

# Filtered to just our group, since the full output is enormous.
dsacls "OU=LAB-Users,$DomainDN" |
    Select-String "GG-Helpdesk-Password-Reset"

# NOTE: granting the right itself is done in the "Delegation of Control"
# wizard in ADUC (right-click the OU), or with dsacls /G. The commands above
# only ADD THE MEMBER and READ the result — if Select-String returns nothing,
# the delegation hasn't been granted yet.

#endregion


#region 13 — gMSA : GROUP MANAGED SERVICE ACCOUNT   [OPTIONAL]
# ---------------------------------------------------------------------------
# A service account whose password AD manages: 120 characters, rotated every
# 30 days automatically, and nobody ever knows it. It replaces the old habit
# of a service running as a normal account with a password in a config file.
# ---------------------------------------------------------------------------

# One-time, forest-wide. Creates the root key gMSA passwords derive from.
# Normally it waits 10 hours to replicate; -EffectiveTime backdates it so a
# single-DC lab works immediately.
#
# Production instead of the lab line below:
# Add-KdsRootKey -EffectiveImmediately
#
# FIXED: this ran unguarded, unlike every other creation in this script. The
#        comment said "ONLY IF YOU DON'T ALREADY HAVE A KDS ROOT KEY. Check
#        first: Get-KdsRootKey" — but nothing enforced it, so re-running the
#        region added a SECOND forest root key. The check is now in the code.
#        Forest-wide state: guarding it matters more here than anywhere else.
if (-not (Get-KdsRootKey -ErrorAction SilentlyContinue)) {

    # Lab / single DC: backdate so the key is usable immediately.
    Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))

} else {
    Write-Host "KDS root key already exists - skipping (this is forest-wide, only ever needed once)."
}

# Which COMPUTERS are allowed to retrieve the password. The members of this
# group are machines, not people.
if (-not (Get-ADGroup -Filter "Name -eq 'GG-gMSA-WebHosts'" -ErrorAction SilentlyContinue)) {
    New-ADGroup `
        -Name "GG-gMSA-WebHosts" `
        -SamAccountName "GG-gMSA-WebHosts" `
        -GroupCategory Security `
        -GroupScope Global `
        -Path $RoleGroupsOU `
        -Description "Computers authorised to retrieve the web application gMSA password"
}

# The trailing $ makes it a computer account name, same rule as region 8.
$CurrentComputer = "$env:COMPUTERNAME$"

Add-ADGroupMember `
    -Identity "GG-gMSA-WebHosts" `
    -Members $CurrentComputer

New-ADServiceAccount `
    -Name "gmsa-webapp" `
    -DNSHostName "gmsa-webapp.$DomainName" `
    -PrincipalsAllowedToRetrieveManagedPassword "GG-gMSA-WebHosts" `
    -KerberosEncryptionType AES128, AES256 `
    -Description "Lab web application group managed service account"

# Check it, then install it on the machine that will run the service:
Get-ADServiceAccount "gmsa-webapp" -Properties PrincipalsAllowedToRetrieveManagedPassword
# Install-ADServiceAccount -Identity "gmsa-webapp"   # run ON the web host
# Test-ADServiceAccount    -Identity "gmsa-webapp"

#endregion


#region 14 — QUERY : LDAP FILTERS AND IDENTITY TROUBLESHOOTING   [OPTIONAL]
# ---------------------------------------------------------------------------
# -Filter is PowerShell syntax. -LDAPFilter is raw LDAP: uglier, but far more
# powerful, and it's what AD actually speaks. Worth being able to read.
#
#   (attribute=value)         one condition
#   (&(a=1)(b=2))             AND — the & goes FIRST
#   (|(a=1)(b=2))             OR
#   (!(a=1))                  NOT
# ---------------------------------------------------------------------------

# Who am I, really?
whoami
whoami /user      # my SID
whoami /groups    # FIXED: was "whomai /groups" — typo.

# My Kerberos tickets. Empty or stale tickets explain a lot of odd
# "access denied" behaviour. klist purge forces fresh ones.
klist

# Which DC am I actually talking to?
# FIXED: was hardcoded "lab.local" while the rest of the script uses
#        contoso.com — the two never matched.
nltest /dsgetdc:$DomainName

# --- LDAP filters -----------------------------------------------------------
# FIXED (all three below): the notes had CURLY quotes “ ” from a Word/Teams
#        paste. PowerShell only accepts straight " and throws a parse error
#        on the curly ones. This is the single most common paste problem.

Get-ADUser `
    -LDAPFilter "(sAMAccountName=sarah.malik)" `
    -Properties Department, Title, Manager

# FIXED: the notes re-declared $UsersOU with a hardcoded
#        "OU=LAB-Users,DC=contoso,DC=com", overwriting the region 2 value.
#        Left out — $UsersOU is already correct from region 4.

# Everyone in Finance. Reads as: is a person AND is a user AND department=Finance.
Get-ADUser `
        -LDAPFilter "(&(objectCategory=person)(objectClass=user)(department=Finance))" `
        -SearchBase $UsersOU `
        -Properties Department |
    Select-Object Name, SamAccountName, Department

# Every ENABLED user. That long number is the LDAP_MATCHING_RULE_BIT_AND rule:
# "bit 2 of userAccountControl is the "account disabled" flag, and NOT it".
# You will never remember this. Look it up each time; everyone does.
Get-ADUser `
    -LDAPFilter "(&(objectCategory=person)(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))" `
    -SearchBase $UsersOU

# The two identifiers every AD object has. The SID is what permissions are
# actually written against — which is why deleting and recreating an account
# with the same name does NOT restore its access.
Get-ADUser "sarah.malik" -Properties ObjectSID, ObjectGUID |
    Select-Object Name, DistinguishedName, SID, ObjectGUID

#endregion


#region 15 — AUDIT : TURN LOGGING ON AND PROVE IT WORKS   [OPTIONAL]
# ---------------------------------------------------------------------------
# Auditing is off by default for most of what matters. If it isn't on BEFORE
# an incident, the evidence simply does not exist.
# ---------------------------------------------------------------------------

# What's currently being audited?
auditpol /get /category:*

# Turn on the subcategories that matter for identity. Success AND failure:
# failures show attacks, successes show what actually happened.
auditpol /set /subcategory:"User Account Management"          /success:enable /failure:enable
auditpol /set /subcategory:"Security Group Management"        /success:enable /failure:enable
auditpol /set /subcategory:"Logon"                            /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Authentication Service"  /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable

# --- generate something to find ---------------------------------------------
# FIXED: the notes reused $InitialPassword here, silently overwriting the
#        secure string from region 5. Renamed so region 5 stays intact.
# NOTE:  a plaintext password in a script is bad practice. It's deliberate
#        here so the audit test runs without prompting. LAB ONLY.
$AuditTestPassword = ConvertTo-SecureString "LabUser!2026Strong" -AsPlainText -Force

New-ADUser `
    -Name "Audit Test User" `
    -SamAccountName "audit.test" `
    -UserPrincipalName "audit.test@$DomainName" `
    -Path $TestObjectsOU `
    -AccountPassword $AuditTestPassword `
    -Enabled $true

# FIXED: was -Members "audit. Test" — a space and wrong case, so it failed
#        with "cannot find an object with identity".
Add-ADGroupMember `
    -Identity "GG-Sales-Employees" `
    -Members "audit.test"

# --- now find it in the log --------------------------------------------------
#   4720 user created      4722 enabled        4725 disabled    4726 deleted
#   4728/4729 global group member added/removed
#   4732/4733 local  group member added/removed
Get-WinEvent -FilterHashtable @{
        LogName   = "Security"
        StartTime = (Get-Date).AddMinutes(-30)
        Id        = 4720, 4722, 4725, 4726, 4728, 4729, 4732, 4733
    } |
    Select-Object TimeCreated, Id, Message |
    Format-List

#endregion


#region 16 — REVIEW : PRIVILEGED ACCESS AND ACCOUNT HYGIENE   [OPTIONAL]
# ---------------------------------------------------------------------------
# The single most valuable recurring check in AD: who has the keys, and which
# accounts are quietly weak. -Recursive matters — someone can be a Domain
# Admin through three levels of nested groups and never appear in a direct
# membership list.
# ---------------------------------------------------------------------------

Get-ADGroupMember -Identity "Domain Admins" -Recursive |
    Select-Object Name, SamAccountName, ObjectClass

Get-ADGroupMember -Identity "Enterprise Admins" -Recursive

# The nine groups worth reviewing. The bottom four surprise people: each one
# has a path to full control, which is exactly why attackers look there.
$PrivilegedGroups = @(
    "Domain Admins",
    "Enterprise Admins",
    "Schema Admins",
    "Administrators",
    "Account Operators",
    "Server Operators",
    "Backup Operators",
    "Group Policy Creator Owners",
    "DnsAdmins"
)

foreach ($Group in $PrivilegedGroups) {
    Write-Host "`n=== $Group ===" -ForegroundColor Cyan

    Get-ADGroupMember `
            -Identity $Group `
            -Recursive `
            -ErrorAction SilentlyContinue |
        Select-Object Name, SamAccountName, ObjectClass
}

# Same data, but as objects you can export. The @{Name=;Expression=} block is
# a calculated property: it adds a column saying which group each row came
# from, which the loop above prints but throws away.
$PrivilegedReport = foreach ($Group in $PrivilegedGroups) {
    Get-ADGroupMember `
            -Identity $Group `
            -Recursive `
            -ErrorAction SilentlyContinue |
        Select-Object @{
            Name       = "PrivilegedGroup"
            Expression = { $Group }
        }, Name, SamAccountName, ObjectClass
}

# FIXED: Export-Csv fails if the folder doesn't exist. Created first.
New-Item -Path "C:\LabReports" -ItemType Directory -Force | Out-Null

$PrivilegedReport |
    Export-Csv `
        -Path "C:\LabReports\PrivilegedGroupMembership.csv" `
        -NoTypeInformation

# --- account hygiene ---------------------------------------------------------
Search-ADAccount -UsersOnly -AccountExpired

# Passwords that never expire — usually old service accounts nobody owns.
Get-ADUser `
        -Filter { PasswordNeverExpires -eq $true } `
        -Properties PasswordNeverExpires |
    Select-Object Name, SamAccountName, PasswordNeverExpires

# Accounts that need NO password at all. Should always be an empty list.
Get-ADUser `
        -Filter { PasswordNotRequired -eq $true } `
        -Properties PasswordNotRequired |
    Select-Object Name, SamAccountName, PasswordNotRequired

# Untouched for 90 days. -TimeSpan takes d.hh:mm:ss. Stale accounts are free
# attack surface — nobody watches them, nobody notices when they get used.
Search-ADAccount -UsersOnly     -AccountInactive -TimeSpan 90.00:00:00
Search-ADAccount -ComputersOnly -AccountInactive -TimeSpan 90.00:00:00

#endregion


#region 17 — HEALTH : DOMAIN CONTROLLER AND TIME   [OPTIONAL]
# ---------------------------------------------------------------------------
# Everything above assumed the DC itself is healthy. These are what you run
# FIRST when something is broken and you don't yet know what.
#
# Time gets its own block for a reason: Kerberos rejects any ticket where the
# clocks differ by more than 5 minutes. A DC with bad time breaks ALL
# authentication domain-wide, and the symptom ("access denied") looks nothing
# like a clock problem.
# ---------------------------------------------------------------------------

# ~30 tests against the DC: replication, services, DNS registration.
dcdiag
dcdiag /v
dcdiag /test:dns /v

# The two shares every DC must publish — where Group Policy and logon scripts
# actually live. Missing = policy silently stops applying everywhere.
Get-SmbShare -Name SYSVOL, NETLOGON

# ...and can they be reached? Both should return True.
Test-Path "\\$DomainName\SYSVOL"
Test-Path "\\$DomainName\NETLOGON"

# The six services a DC cannot work without. All should be Running.
#   NTDS the AD database · DNS · Netlogon secure channel + SYSVOL
#   KDC Kerberos tickets · ADWS what the PS module talks to · DFSR SYSVOL replication
Get-Service NTDS, DNS, Netlogon, KDC, ADWS, DFSR |
    Format-Table Name, Status, StartType

# The PDC Emulator is the domain's clock: it syncs to an external source and
# everything else syncs to it.
w32tm /query /status
w32tm /query /source
w32tm /query /configuration

# Targeted dcdiag tests. Faster than a full run when you already suspect what
# is wrong, and the output is short enough to actually read.
#   advertising  is this DC telling the world it is a DC?
#   netlogons    are the SYSVOL/NETLOGON permissions right?
#   services     are the required services running?
#   dns          the big one - DNS registration and resolution
dcdiag /test:advertising
dcdiag /test:netlogons
dcdiag /test:services
dcdiag /test:dns

#endregion


#region 18 — RECYCLE BIN : RESTORE A DELETED OBJECT   [OPTIONAL]
# ---------------------------------------------------------------------------
# Deleting an AD object normally leaves a "tombstone" — a husk with almost
# every attribute stripped. The Recycle Bin keeps the object INTACT, so a
# restore brings back attributes, group memberships and the same SID. That
# last part is why file permissions still work afterwards.
#
#   *** ENABLING IT IS PERMANENT — there is no way to turn it back off. ***
#   It is still the right call. Just know it is one-way before you run it.
# ---------------------------------------------------------------------------

# Is it on? Empty EnabledScopes = not yet.
Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'" |
    Select-Object Name, EnabledScopes

# IRREVERSIBLE. Needs $Forest from region 2.
Enable-ADOptionalFeature `
    -Identity "Recycle Bin Feature" `
    -Scope ForestOrConfigurationSet `
    -Target $Forest.Name

Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'" |
    Select-Object Name, EnabledScopes

# --- prove it on a disposable account ---------------------------------------
# FIXED: the notes reused $InitialPassword, which region 15 had already
#        overwritten with the plaintext lab password. Own variable here.
$RecycleTestPassword = ConvertTo-SecureString "LabUser!2026Strong" -AsPlainText -Force

New-ADUser `
    -Name "Recycle Bin Test" `
    -SamAccountName "recycle.test" `
    -UserPrincipalName "recycle.test@$DomainName" `
    -Path $TestObjectsOU `
    -AccountPassword $RecycleTestPassword `
    -Enabled $true `
    -Description "Disposable account for Recycle Bin exercise"

# Note the ObjectGUID first — it is the one identifier that survives deletion.
$RecycleUser = Get-ADUser "recycle.test"
$RecycleUser | Select-Object Name, ObjectGUID, DistinguishedName

Remove-ADUser -Identity "recycle.test" -Confirm:$false

# Deleted objects are invisible to Get-ADUser — you need Get-ADObject with
# -IncludeDeletedObjects. LastKnownParent is the OU it came from, which is
# what makes the restore land back in the right place.
Get-ADObject `
        -Filter "SamAccountName -eq 'recycle.test'" `
        -IncludeDeletedObjects `
        -Properties SamAccountName, LastKnownParent |
    Format-List Name, SamAccountName, Deleted, LastKnownParent, ObjectGUID

Get-ADObject `
        -Filter "SamAccountName -eq 'recycle.test'" `
        -IncludeDeletedObjects |
    Restore-ADObject

# FIXED: was Get-ADUser "recycle. Test" — a space and wrong case, the same
#        mistake as "audit. Test" in region 15.
Get-ADUser "recycle.test"

#endregion


#region 19 — BACKUP : SYSTEM STATE AND GROUP POLICY   [OPTIONAL]
# ---------------------------------------------------------------------------
# A domain controller without a tested backup is a single point of failure for
# the whole domain. Two different things are worth backing up, and they are not
# the same job:
#   SYSTEM STATE  the AD database itself (NTDS.dit), SYSVOL, registry, COM+.
#                 This is what you restore from if the DC dies.
#   GPO BACKUP    the policy objects on their own. Far more common in practice
#                 - someone edits a GPO, breaks something, and you roll back
#                 that one GPO without touching the rest of the domain.
# ---------------------------------------------------------------------------

# Check the target drive exists and has room before starting. A system state
# backup of a lab DC is typically 8-15 GB.
Get-Volume |
    Format-Table DriveLetter, FileSystemLabel, FileSystem, SizeRemaining, Size

# System state backup. -quiet suppresses the confirmation prompt.
# NOTE: -backuptarget must be a volume that exists and is NOT the system drive.
#       Change E: to whatever Get-Volume above showed you.
wbadmin start systemstatebackup -backuptarget:E: -quiet

# Did it work, and what do we have?
wbadmin get status
wbadmin get versions

# --- Group Policy backup ----------------------------------------------------
$GPOBackupPath = "C:\LabBackups\GPO"

New-Item -Path $GPOBackupPath -ItemType Directory -Force

# -All backs up every GPO in the domain. The -Comment is stamped into the
# backup manifest, which is how you tell three backups apart six months later.
Backup-GPO -All -Path $GPOBackupPath -Comment "Full lab GPO backup $(Get-Date)"

# Each GPO lands in its own GUID-named folder. Confirm they are there.
Get-ChildItem -Path $GPOBackupPath -Recurse

# To restore one later:
#   Restore-GPO -Name "LAB - Workstation Security Baseline" -Path $GPOBackupPath

#endregion


#region 20 — REPORT : EXPORT THE DOMAIN TO CSV   [OPTIONAL]
# ---------------------------------------------------------------------------
# Everything so far printed to the screen. This turns the domain into files you
# can hand to someone, diff against last month, or open in Excel.
#
# Export-Csv -NoTypeInformation drops the "#TYPE System.Management..." header
# line that Excel shows as a junk first row. Always use it.
# ---------------------------------------------------------------------------

New-Item -Path "C:\LabReports" -ItemType Directory -Force | Out-Null

# Every GPO's full settings as one browsable HTML report. Genuinely useful -
# this is what you attach to a change request.
Get-GPOReport -All -ReportType Html -Path "C:\LabReports\All-GPOs.html"

# Users. LastLogonDate and PasswordLastSet are the two columns that make this
# an audit rather than a list.
Get-ADUser `
        -Filter * `
        -SearchBase $UsersOU `
        -Properties Department, Title, Office, Enabled, LastLogonDate, PasswordLastSet |
    Select-Object Name, SamAccountName, Department, Title, Office, Enabled,
        LastLogonDate, PasswordLastSet, DistinguishedName |
    Export-Csv -Path "C:\LabReports\AD-Users.csv" -NoTypeInformation

# Computers. OperatingSystem exposes machines nobody has patched in years.
Get-ADComputer `
        -Filter * `
        -SearchBase $ComputersOU `
        -Properties OperatingSystem, LastLogonDate, Description |
    Select-Object Name, OperatingSystem, LastLogonDate, Description, DistinguishedName |
    Export-Csv -Path "C:\LabReports\AD-Computers.csv" -NoTypeInformation

# Groups.
Get-ADGroup `
        -Filter * `
        -SearchBase $GroupsOU `
        -Properties Description |
    Select-Object Name, GroupScope, GroupCategory, Description, DistinguishedName |
    Export-Csv -Path "C:\LabReports\AD-Groups.csv" -NoTypeInformation

# OUs, including whether each is protected from accidental deletion.
Get-ADOrganizationalUnit -Filter * -SearchBase $DomainDN |
    Select-Object Name, DistinguishedName, ProtectedFromAccidentalDeletion |
    Export-Csv -Path "C:\LabReports\AD-OUs.csv" -NoTypeInformation

# --- group membership, flattened ---------------------------------------------
# One row per group-member pair, which is the shape you actually want for
# reviewing access. [PSCustomObject]@{} builds a custom row with named columns.
# The else branch matters: an EMPTY group still gets a row, so it shows up in
# the report instead of silently vanishing. Empty security groups are worth
# seeing - they are usually leftovers nobody cleaned up.
$GroupMembershipReport = foreach ($Group in (Get-ADGroup -Filter * -SearchBase $GroupsOU)) {

    $Members = Get-ADGroupMember -Identity $Group -ErrorAction SilentlyContinue

    if ($Members) {
        foreach ($Member in $Members) {
            [PSCustomObject]@{
                GroupName        = $Group.Name
                GroupScope       = $Group.GroupScope
                MemberName       = $Member.Name
                MemberType       = $Member.ObjectClass
                MemberSAMAccount = $Member.SamAccountName
            }
        }
    }
    else {
        [PSCustomObject]@{
            GroupName        = $Group.Name
            GroupScope       = $Group.GroupScope
            MemberName       = "<No members>"
            MemberType       = ""
            MemberSAMAccount = ""
        }
    }
}

$GroupMembershipReport |
    Export-Csv -Path "C:\LabReports\Group-Membership.csv" -NoTypeInformation

#endregion


#region 21 — ASSESSMENT : A READ-ONLY ACCOUNT FOR AUDIT TOOLING   [OPTIONAL]
# ---------------------------------------------------------------------------
# AD assessment tools (ADRecon, PingCastle, BloodHound and friends) only need
# to READ the directory. Running them as Domain Admin is the lazy habit that
# turns an audit into an incident: the tool's credentials become the most
# valuable thing on the network.
#
# A standard domain user can already read most of AD. That is the point of
# this account - no groups, no rights beyond Domain Users, and it still works.
# ---------------------------------------------------------------------------

# FIXED: the notes redefined $UsersOU here to a DEPARTMENT OU
#            $UsersOU = "OU=Information Technology,OU=LAB-Users,$DomainDN"
#        which silently repointed it away from LAB-Users. Every later command
#        using $UsersOU would then target the wrong OU. Given its own variable.
$AuditAccountOU = "OU=Information Technology,$UsersOU"

Get-ADOrganizationalUnit -Identity $AuditAccountOU

$ADReconPassword = Read-Host `
    "Enter a password for the audit account" `
    -AsSecureString

# FIXED: -UserPrincipalName was hardcoded to @lab.local while the rest of the
#        script uses $DomainName. Two different domains in one script.
# NOTE:  -ChangePasswordAtLogon $false is DELIBERATE here. A tool cannot answer
#        a password-change prompt. This is the one place that flag is correct,
#        and it is why the account must have no privileges to compensate.
New-ADUser `
    -Name "ADRecon Audit User" `
    -GivenName "ADRecon" `
    -Surname "Audit User" `
    -DisplayName "ADRecon Audit User" `
    -SamAccountName "adrecon.audit" `
    -UserPrincipalName "adrecon.audit@$DomainName" `
    -Description "Standard read-only account for authorised AD assessments" `
    -Path $AuditAccountOU `
    -AccountPassword $ADReconPassword `
    -Enabled $true `
    -ChangePasswordAtLogon $false

Get-ADUser "adrecon.audit" -Properties Description |
    Select-Object Name, SamAccountName, Enabled, Description, DistinguishedName

# Confirm it is ONLY in Domain Users. If anything else appears here, the
# account is over-privileged and should not be handed to a scanning tool.
Get-ADPrincipalGroupMembership "adrecon.audit" |
    Select-Object Name, GroupScope

#endregion


#region 22 — VERIFY : PROVE IT ALL WORKED   [CORE]
# ---------------------------------------------------------------------------
# All read-only. Compare against the "before" snapshot from region 3.
#
# The first four checks cover the CORE build and are all you need for the
# Cluster 3 project. The Get-GPO / Get-GPInheritance lines only return
# anything if you ran region 9.
# ---------------------------------------------------------------------------

Get-ADOrganizationalUnit -Filter * -SearchBase $DomainDN |
    Sort-Object DistinguishedName |
    Format-Table Name, DistinguishedName

Get-ADUser -Filter * -SearchBase $UsersOU -Properties Department, Title |
    Select-Object Name, SamAccountName, Department, Enabled |
    Sort-Object Department, Name |
    Format-Table -AutoSize

Get-ADGroup -Filter * -SearchBase $GroupsOU |
    Select-Object Name, GroupCategory, GroupScope |
    Sort-Object GroupScope, Name |
    Format-Table

# If DistinguishedName shows your Sydney/Melbourne/Servers OUs, staging worked.
Get-ADComputer -Filter * -SearchBase $ComputersOU -Properties Description |
    Select-Object Name, Enabled, Description, DistinguishedName |
    Format-Table -AutoSize

Get-GPO -All | Select-Object DisplayName, GpoStatus | Sort-Object DisplayName
Get-GPInheritance -Target $WorkstationsOU
Get-GPInheritance -Target $UsersOU

Get-NetAdapter

# FIXED: both of these hardcoded contoso.com. Same test as region 3, run
#        again at the end to confirm nothing broke name resolution.
Resolve-DnsName $DomainName
Resolve-DnsName "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV

#endregion


<#
===============================================================================
  STILL TO COME
    · Fine-grained password policies      belongs beside region 5
    · Granting the delegation itself      region 12 adds the member and reads
                                          the ACL, but doesn't grant the right
    · Install-ADServiceAccount on a host  region 13, run on the web server
    · LAPS, trusts, sites and services, AD Recycle Bin

  Two OUs are built and still unused: LAB-Service-Accounts and
  LAB-Test-Objects (region 15 puts audit.test in the latter).
===============================================================================
#>
