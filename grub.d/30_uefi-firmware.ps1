$ErrorActionPreference="Stop"

# grub-mkconfig helper script.
# Copyright (C) 2020  Free Software Foundation, Inc.
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

$LABEL="UEFI Firmware Settings"

Write-Error -ErrorAction Continue (& gettext_printf "Adding boot menu entry for UEFI Firmware Settings ...`n")

Write-Output @"
if [ "\$grub_platform" = "efi" ]; then
	fwsetup --is-supported
	if [ "\$?" = 0 ]; then
		menuentry '$LABEL' \$menuentry_id_option 'uefi-firmware' {
			fwsetup
		}
	fi
fi
"@
