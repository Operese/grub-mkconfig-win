$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

# grub-mkconfig helper script.
# Copyright (C) 2008,2009,2010  Free Software Foundation, Inc.
#
# GRUB is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# GRUB is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with GRUB.  If not, see <http://www.gnu.org/licenses/>.

. "${env:pkgdatadir}/env-def.ps1"

$prefix = "$env:prefix"
$exec_prefix = "$env:exec_prefix"
$datarootdir = "$env:datarootdir"

$env:TEXTDOMAIN = "$env:PACKAGE"
$env:TEXTDOMAINDIR = "$env:localedir"

. "$env:pkgdatadir/grub-mkconfig_lib.ps1"

if ($PSVersionTable.PSVersion.Major -gt 5 -and -not $IsWindows) {
  exit 0
}

# Try C: even if current system is on other partition.
switch -Regex ($env:SystemDrive) {
  '^[Cc]:$' { $drives = 'C:' }
  '^[D-Zd-z]:$' { $drives = "C: $env:SystemDrive" }
  default { exit 0 }
}

foreach ($drv in $drives -split " ") {

  if (-not (Test-Path "$drv")) {
    continue
  }

  # Check for Vista bootmgr.
  if (Test-Path "$drv/Windows/System32/winload.exe" -PathType Leaf) {
    $OS = "$(gettext "Windows NT (loader)")"
    $osid = "bootmgr"
  }
  else {
    continue
  }

  # Get boot device.
  $dev = (& ${grub_probe} -t device "\\.\$drv" 2> $null)
  if (-not $dev) {
    continue
  }

  gettext_printf "Found {0} on {1} ({2})`n" "$OS" "$drv" "$dev"
  Write-Output @"
menuentry '$(grub_quote "$OS")' --class windows --class os `$menuentry_id_option '$osid-$(grub_get_device_id "${dev}")' {
"@

  Write-Output (& save_default_entry | ForEach-Object { "$grub_tab$_" })
  Write-Output (& prepare_grub_to_access_device "$dev" | ForEach-Object { "$grub_tab$_" })
  Write-Output @"
	chainloader +1
}
"@
}

