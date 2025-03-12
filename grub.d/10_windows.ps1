$ErrorActionPreference="Stop"

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

$prefix="$env:prefix"
$exec_prefix="$env:exec_prefix"
$datarootdir="$env:datarootdir"

$env:TEXTDOMAIN="$env:PACKAGE"
$env:TEXTDOMAINDIR="$env:localedir"

. "$env:pkgdatadir/grub-mkconfig_lib.ps1"

if($PSVersionTable.PSVersion.Major -gt 5 -and -not $IsWindows) {
  exit 0
}

# Try C: even if current system is on other partition.
switch -Regex ($SYSTEMDRIVE) {
  '^[Cc]:$' { $drives = 'C:' }
  '^[D-Zd-z]:$' { $drives = "C: $SYSTEMDRIVE" }
  default { exit 0 }
}


function get_os_name_from_boot_ini
{
  # Fail if no or more than one partition.
  if((Get-CimInstance -Class "MSFT_Partition" -Namespace "root\Microsoft\Windows\Storage").Length -ne 1) {
    return ""
  }

  # Search 'default=PARTITION'
  $get_os_name_from_boot_ini_part=((Get-Content $args[0] | Select-String -Pattern "^default=") -replace "^default=", "" -replace "\\", "/" -replace "[ $grub_tab\r]*$", "" | Select-Object -First 1)
  if(-not $get_os_name_from_boot_ini_part) {
    return ""
  }

  # Search 'PARTITION="NAME" ...'
  Get-Content $args[0] -replace "\", "/" -match "^$get_os_name_from_boot_ini_part=`"\([^`"]*\).*`".*$'"
  $get_os_name_from_boot_ini_name=${matches[1]}
  if(-not $get_os_name_from_boot_ini_name) {
    return ""
  }

  Write-Output "$get_os_name_from_boot_ini_name"
}



foreach($drv in $drives) {

  if(-not (Test-Path "$drv" -PathType Leaf)) {
    continue
  }

  $needmap=
  $osid=

  # Check for Vista bootmgr.
  if((Test-Path "$drv/bootmgr" -PathType Leaf) -and (Test-Path "$drv/boot/bcd" -PathType Leaf)) {
    $OS="$(gettext "Windows Vista/7 (loader)")"
    $osid="bootmgr"
  }
  # Check for NTLDR.
  elseif((Test-Path "$drv/ntldr" -PathType Leaf) -and (Test-Path "$drv/ntdetect.com" -PathType Leaf) -and (Test-Path "$drv/boot.ini" -PathType Leaf)) {
    $OS=(& get_os_name_from_boot_ini "$drv/boot.ini")
    if($OS -eq "") {
      $OS="$(gettext "Windows NT/2000/XP (loader)")"
    }
    $osid="ntldr"
    $needmap="t"
  }
  else {
    continue
  }

  # Get boot device.
  $dev=(& ${grub_probe} -t device "\\.\$drv" 2> $null)
  if(-not $dev) {
    continue
  }

  Write-Error -ErrorAction Continue (& gettext_printf "Found {0} on {1} ({2})`n" "$OS" "$drv" "$dev")
  Write-Output @"
menuentry '$(Write-Output "$OS" | grub_quote)' \$menuentry_id_option '$osid-$(grub_get_device_id "${dev}")' {
"@

  Write-Output (& save_default_entry | ForEach-Object { "$grub_tab$_" })
  Write-Output (& prepare_grub_to_access_device "$dev" | ForEach-Object { "$grub_tab$_" })
  if($needmap) {
    Write-Output @"
	drivemap -s (hd0) \$root
"@
  }
  Write-Output @"
	chainloader +1
}
"@
}

