#Requires -RunAsAdministrator
$ErrorActionPreference="Stop"

# Generate grub.cfg by inspecting /boot contents.
# Copyright (C) 2006,2007,2008,2009,2010 Free Software Foundation, Inc.
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

$prefix="@prefix@"
$exec_prefix="@exec_prefix@"
$datarootdir="@datarootdir@"

$sbindir="@sbindir@"
$bindir="@bindir@"
$sysconfdir="@sysconfdir@"
$PACKAGE_NAME="@PACKAGE_NAME@"
$PACKAGE_VERSION="@PACKAGE_VERSION@"
$host_os="@host_os@"
$datadir="@datadir@"
if("x$pkgdatadir" -eq "x") {
    $pkgdatadir="${datadir}/@PACKAGE@"
}
# export it for scripts
export $pkgdatadir

$grub_cfg=""
$grub_mkconfig_dir="${sysconfdir}/grub.d"

$self=$MyInvocation.MyCommand.Name

$grub_probe="${sbindir}/@grub_probe@"
$grub_file="${bindir}/@grub_file@"
$grub_editenv="${bindir}/@grub_editenv@"
$grub_script_check="${bindir}/@grub_script_check@"

$env:TEXTDOMAIN="@PACKAGE@"
$env:TEXTDOMAINDIR="@localedir@"

. "${pkgdatadir}/grub-mkconfig_lib"

# Usage: usage
# Print the usage.
function usage {
    gettext_printf "Usage: %s [OPTION]\n" "$self"
    gettext "Generate a grub config file"
    Write-Output ""
    Write-Output ""
    print_option_help "-o, --output=$(gettext FILE)" "$(gettext "output generated config to FILE [default=stdout]")"
    print_option_help "-h, --help" "$(gettext "print this message and exit")"
    print_option_help "-V, --version" "$(gettext "print the version information and exit")"
    Write-Output ""
    # Don't want to send people to the FSF for an unofficial port
    # Consider mentioning GitHub issues?
    # gettext "Report bugs to <bug-grub@gnu.org>."
    Write-Output ""
}

function argument {
  opt=$args[0]

  if(args.Length -eq 1) {
      Write-Error (& gettext_printf "%s: option requires an argument -- \`%s'\n" "$self" "$opt")
      exit 1
  }
  Write-Output $args[1]
}

# Check the arguments.
for($i=0; $i -lt $args.Length; $i++) {
  $option = $args[$i]
  switch -Wildcard ($option) {
    "-h" {
      usage
      exit 0
    }
    "--help" {
      usage
      exit 0
    }
    "-V" {
      Write-Output "$self (${PACKAGE_NAME}) ${PACKAGE_VERSION}"
      exit 0
    }
    "--version" {
      Write-Output "$self (${PACKAGE_NAME}) ${PACKAGE_VERSION}"
      exit 0
    }
    "-o" {
      $grub_cfg=(argument $option $args[$i..($args.Length - 1)])
      $i++
    }
    "--output" {
      $grub_cfg=(argument $option $args[$i..($args.Length - 1)])
      $i++
    }
    "--output=*" {
      $grub_cfg=($option -replace "^--output=", "")
    }
    "-*" {
      Write-Error (& gettext_printf "Unrecognized option \`%s'\n" "$option")
      usage
      exit 1
    }
    default {}
  }
}

if(-not (Test-Path $grub_probe -PathType Leaf)) {
    Write-Error (& gettext_printf "%s: Not found.\n" "$1")
    exit 1
}

# Device containing our userland.  Typically used for root= parameter.
$GRUB_DEVICE=(& ${grub_probe} --target=device "\\.\$env:SystemDrive")
$GRUB_DEVICE_UUID=(& ${grub_probe} --device ${GRUB_DEVICE} --target=fs_uuid 2> $null)
if(-not $GRUB_DEVICE_UUID) {
  $GRUB_DEVICE_UUID=$true
}
$GRUB_DEVICE_PARTUUID=(& ${grub_probe} --device ${GRUB_DEVICE} --target=partuuid 2> $null)
if(-not $GRUB_DEVICE_PARTUUID) {
  $GRUB_DEVICE_PARTUUID=$true
}

# Device containing our /boot partition.  Usually the same as GRUB_DEVICE.
$GRUB_DEVICE_BOOT=(& ${grub_probe} --target=device "\\.\$env:SystemDrive")
$GRUB_DEVICE_BOOT_UUID=(& ${grub_probe} --device ${GRUB_DEVICE_BOOT} --target=fs_uuid 2> $null)
if(-not $GRUB_DEVICE_BOOT_UUID) {
  $GRUB_DEVICE_BOOT_UUID=$true
}

# Disable os-prober by default due to security reasons.
$GRUB_DISABLE_OS_PROBER="true"

# Filesystem for the device containing our userland.  Used for stuff like
# choosing Hurd filesystem module.
$GRUB_FS=(& ${grub_probe} --device ${GRUB_DEVICE} --target=fs 2> $null)
if(-not $GRUB_FS) {
  $GRUB_FS="ntfs"
}

# Provide a default set of stock linux early initrd images.
# Define here so the list can be modified in the sourced config file.
if("x${GRUB_EARLY_INITRD_LINUX_STOCK}" -eq "x") {
	$GRUB_EARLY_INITRD_LINUX_STOCK="intel-uc.img intel-ucode.img amd-uc.img amd-ucode.img early_ucode.cpio microcode.cpio"
}

if(Test-Path "${sysconfdir}/default/grub" -PathType Leaf) {
  . "${sysconfdir}/default/grub"
}

if("x${GRUB_DISABLE_UUID}" -eq "xtrue") {
  if(-not "${GRUB_DISABLE_LINUX_UUID}") {
    $GRUB_DISABLE_LINUX_UUID="true"
  }
  if(-not "${GRUB_DISABLE_LINUX_PARTUUID}") {
    $GRUB_DISABLE_LINUX_PARTUUID="true"
  }
}

# XXX: should this be deprecated at some point?
if("x${GRUB_TERMINAL}" -ne "x") {
  $GRUB_TERMINAL_INPUT="${GRUB_TERMINAL}"
  $GRUB_TERMINAL_OUTPUT="${GRUB_TERMINAL}"
}

$termoutdefault=0
if("x${GRUB_TERMINAL_OUTPUT}" -eq "x") {
    $GRUB_TERMINAL_OUTPUT="gfxterm";
    $termoutdefault=1;
}

foreach($x in ${GRUB_TERMINAL_OUTPUT} -split " ") {
  switch ("x$x") {
    "xgfxterm" {}
    "xconsole" {
      $env:LANG="C"
    }
    "xserial" {
      $env:LANG="C"
    }
    "xofconsole" {
      $env:LANG="C"
    }
    "xvga_text" {
      $env:LANG="C"
    }
    default {
      Write-Error "Invalid output terminal `"${GRUB_TERMINAL_OUTPUT}`""
      exit 1
    }
  }
}

$GRUB_ACTUAL_DEFAULT="$GRUB_DEFAULT"

if("x${GRUB_ACTUAL_DEFAULT}" -eq "xsaved") {
  $GRUB_ACTUAL_DEFAULT=(& ${grub_editenv} - list ) -replace "`nsaved_entry=",""
}


# These are defined in this script, export them here so that user can
# override them.
export GRUB_DEVICE \
  GRUB_DEVICE_UUID \
  GRUB_DEVICE_PARTUUID \
  GRUB_DEVICE_BOOT \
  GRUB_DEVICE_BOOT_UUID \
  GRUB_DISABLE_OS_PROBER \
  GRUB_FS \
  GRUB_FONT \
  GRUB_PRELOAD_MODULES \
  GRUB_ACTUAL_DEFAULT

# These are optional, user-defined variables.
export GRUB_DEFAULT \
  GRUB_HIDDEN_TIMEOUT \
  GRUB_HIDDEN_TIMEOUT_QUIET \
  GRUB_TIMEOUT \
  GRUB_TIMEOUT_STYLE \
  GRUB_DEFAULT_BUTTON \
  GRUB_HIDDEN_TIMEOUT_BUTTON \
  GRUB_TIMEOUT_BUTTON \
  GRUB_TIMEOUT_STYLE_BUTTON \
  GRUB_BUTTON_CMOS_ADDRESS \
  GRUB_BUTTON_CMOS_CLEAN \
  GRUB_DISTRIBUTOR \
  GRUB_CMDLINE_LINUX \
  GRUB_CMDLINE_LINUX_DEFAULT \
  GRUB_CMDLINE_LINUX_RECOVERY \
  GRUB_CMDLINE_XEN \
  GRUB_CMDLINE_XEN_DEFAULT \
  GRUB_CMDLINE_LINUX_XEN_REPLACE \
  GRUB_CMDLINE_LINUX_XEN_REPLACE_DEFAULT \
  GRUB_CMDLINE_NETBSD \
  GRUB_CMDLINE_NETBSD_DEFAULT \
  GRUB_CMDLINE_GNUMACH \
  GRUB_TOP_LEVEL \
  GRUB_TOP_LEVEL_XEN \
  GRUB_TOP_LEVEL_OS_PROBER \
  GRUB_EARLY_INITRD_LINUX_CUSTOM \
  GRUB_EARLY_INITRD_LINUX_STOCK \
  GRUB_TERMINAL_INPUT \
  GRUB_TERMINAL_OUTPUT \
  GRUB_SERIAL_COMMAND \
  GRUB_DISABLE_UUID \
  GRUB_DISABLE_LINUX_UUID \
  GRUB_DISABLE_LINUX_PARTUUID \
  GRUB_DISABLE_RECOVERY \
  GRUB_VIDEO_BACKEND \
  GRUB_GFXMODE \
  GRUB_BACKGROUND \
  GRUB_THEME \
  GRUB_GFXPAYLOAD_LINUX \
  GRUB_INIT_TUNE \
  GRUB_SAVEDEFAULT \
  GRUB_ENABLE_CRYPTODISK \
  GRUB_BADRAM \
  GRUB_OS_PROBER_SKIP_LIST \
  GRUB_DISABLE_SUBMENU

if("x${grub_cfg}" -ne "x") {
  Remove-Item -Force "${grub_cfg}.new"
  Start-Transcript -Path "${grub_cfg}.new"
  $acl = Get-Acl -Path "${grub_cfg}.new"
  $acl.SetAccessRuleProtection($true, $false)
  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
  $fileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl
  $type = [System.Security.AccessControl.AccessControlType]::Allow
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $fileSystemRights, $type)
  $acl.AddAccessRule($rule)
  Set-Acl -Path "${grub_cfg}.new" -AclObject $acl
}
Write-Error (& gettext "Generating grub configuration file ...")
Write-Error ""

Write-Output @"
#
# DO NOT EDIT THIS FILE
#
# It is automatically generated by $self using templates
# from ${grub_mkconfig_dir} and settings from ${sysconfdir}/default/grub
#
"@


foreach($i in Get-ChildItem -Path "${grub_mkconfig_dir}") {
  switch -Wildcard ($i) {
    # emacsen backup files. FIXME: support other editors
    "*~" {}
    # emacsen backup files. FIXME: support other editors
    "*/#*#" {}
    default {
      if(grub_file_is_not_garbage "$i" -and Test-Path "$i" -PathType Leaf) {
        Write-Output ""
        Write-Output "### BEGIN $i ###"
        & "$i"
        Write-Output "### END $i ###"
      }
    }
  }
}

if("x${grub_cfg}" -ne "x") {
  if(-not (& ${grub_script_check} "${grub_cfg}.new")) {
    # TRANSLATORS: %s is replaced by filename
    Write-Error (& gettext_printf "Syntax errors are detected in generated GRUB config file.
Ensure that there are no errors in /etc/default/grub
and /etc/grub.d/* files or please file a bug report with
%s file attached." "${grub_cfg}.new")
    Write-Error
    exit 1
  }
  else {
    # none of the children aborted with error, install the new grub.cfg
    Copy-Item -Path "${grub_cfg}.new" -Destination ${grub_cfg}
    $acl = Get-Acl -Path "${grub_cfg}"
    $acl.SetAccessRuleProtection($true, $false)
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $fileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl
    $type = [System.Security.AccessControl.AccessControlType]::Allow
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $fileSystemRights, $type)
    $acl.AddAccessRule($rule)
    Set-Acl -Path "${grub_cfg}" -AclObject $acl
    Remove-Item -Force "${grub_cfg}.new"
    Stop-Transcript
  }
}

Write-Error (& gettext "done")
Write-Error ""
