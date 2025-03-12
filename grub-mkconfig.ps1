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

. "./env-def.ps1"

$prefix="$env:prefix"
$exec_prefix="$env:exec_prefix"
$datarootdir="$env:datarootdir"

$sbindir="$env:sbindir"
$bindir="$env:bindir"
$sysconfdir="$env:sysconfdir"
$PACKAGE_NAME="$env:PACKAGE_NAME"
$PACKAGE_VERSION="$env:PACKAGE_VERSION"
$host_os="$env:host_os"
$datadir="$env:datadir"
if("x$env:pkgdatadir" -eq "x") {
    $env:pkgdatadir="${datadir}/$env:PACKAGE"
}

$grub_cfg=""
$grub_mkconfig_dir="${sysconfdir}/grub.d"

$self=$MyInvocation.MyCommand.Name

$grub_probe="${sbindir}/$env:grub_probe"
$grub_file="${bindir}/$env:grub_file"
$grub_editenv="${bindir}/$env:grub_editenv"
$grub_script_check="${bindir}/$env:grub_script_check"

$env:TEXTDOMAIN="$env:PACKAGE"
$env:TEXTDOMAINDIR="$env:localedir"

. "${env:pkgdatadir}/grub-mkconfig_lib.ps1"

# Usage: usage
# Print the usage.
function usage {
    gettext_printf "Usage: {0} [OPTION]`n" "$self"
    gettext "Generate a grub config file"
    Write-Output ""
    print_option_help "-o, --output=$(gettext FILE)" "$(gettext "output generated config to FILE [default=stdout]")"
    print_option_help "-h, --help" "$(gettext "print this message and exit")"
    print_option_help "-V, --version" "$(gettext "print the version information and exit")"
    Write-Output ""
    # Don't want to send people to the FSF for an unofficial port
    # Consider mentioning GitHub issues?
    # gettext "Report bugs to <bug-grub@gnu.org>."
}

function argument {
  $opt=$args[0]

  if($args.Length -eq 1) {
      Write-Error -ErrorAction Continue (& gettext_printf "{0}: option requires an argument -- '{1}'`n" "$self" "$opt")
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
      $grub_cfg=(argument $option $args[$($i + 1)..($args.Length - 1)])
      $i++
      break
    }
    "--output" {
      $grub_cfg=(argument $option $args[$i..($args.Length - 1)])
      $i++
      break
    }
    "--output=*" {
      $grub_cfg=($option -replace "^--output=", "")
      break
    }
    "-*" {
      Write-Error -ErrorAction Continue (& gettext_printf "Unrecognized option '{0}'`n" "$option")
      usage
      exit 1
    }
    default {}
  }
}

if(-not (Test-Path $grub_probe -PathType Leaf)) {
    Write-Error -ErrorAction Continue (& gettext_printf "{0}: Not found.`n" $grub_probe)
    exit 1
}

# Device containing our userland.  Typically used for root= parameter.
$env:GRUB_DEVICE=(& ${grub_probe} --target=device "\\.\$env:SystemDrive")
$env:GRUB_DEVICE_UUID=(& ${grub_probe} --device ${env:GRUB_DEVICE} --target=fs_uuid 2> $null)
if(-not $env:GRUB_DEVICE_UUID) {
  $env:GRUB_DEVICE_UUID=$true
}
$env:GRUB_DEVICE_PARTUUID=(& ${grub_probe} --device ${env:GRUB_DEVICE} --target=partuuid 2> $null)
if(-not $env:GRUB_DEVICE_PARTUUID) {
  $env:GRUB_DEVICE_PARTUUID=$true
}

# Device containing our /boot partition.  Usually the same as GRUB_DEVICE.
$env:GRUB_DEVICE_BOOT=(& ${grub_probe} --target=device "\\.\$env:SystemDrive")
$env:GRUB_DEVICE_BOOT_UUID=(& ${grub_probe} --device ${env:GRUB_DEVICE_BOOT} --target=fs_uuid 2> $null)
if(-not $env:GRUB_DEVICE_BOOT_UUID) {
  $env:GRUB_DEVICE_BOOT_UUID=$true
}

# Disable os-prober by default due to security reasons.
$env:GRUB_DISABLE_OS_PROBER="true"

# Filesystem for the device containing our userland.  Used for stuff like
# choosing Hurd filesystem module.
$env:GRUB_FS=(& ${grub_probe} --device ${env:GRUB_DEVICE} --target=fs 2> $null)
if(-not $env:GRUB_FS) {
  $env:GRUB_FS="ntfs"
}

# Provide a default set of stock linux early initrd images.
# Define here so the list can be modified in the sourced config file.
if("x${env:GRUB_EARLY_INITRD_LINUX_STOCK}" -eq "x") {
	$env:GRUB_EARLY_INITRD_LINUX_STOCK="intel-uc.img intel-ucode.img amd-uc.img amd-ucode.img early_ucode.cpio microcode.cpio"
}

if(Test-Path "${sysconfdir}/default/grub" -PathType Leaf) {
  . "${sysconfdir}/default/grub"
}

if("x${env:GRUB_DISABLE_UUID}" -eq "xtrue") {
  if(-not "${env:GRUB_DISABLE_LINUX_UUID}") {
    $env:GRUB_DISABLE_LINUX_UUID="true"
  }
  if(-not "${env:GRUB_DISABLE_LINUX_PARTUUID}") {
    $env:GRUB_DISABLE_LINUX_PARTUUID="true"
  }
}

# XXX: should this be deprecated at some point?
if("x${env:GRUB_TERMINAL}" -ne "x") {
  $env:GRUB_TERMINAL_INPUT="${env:GRUB_TERMINAL}"
  $env:GRUB_TERMINAL_OUTPUT="${env:GRUB_TERMINAL}"
}

$termoutdefault=0
if("x${env:GRUB_TERMINAL_OUTPUT}" -eq "x") {
    $env:GRUB_TERMINAL_OUTPUT="gfxterm";
    $termoutdefault=1;
}

foreach($x in ${env:GRUB_TERMINAL_OUTPUT} -split " ") {
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
      Write-Error -ErrorAction Continue "Invalid output terminal `"${env:GRUB_TERMINAL_OUTPUT}`""
      exit 1
    }
  }
}

$env:GRUB_ACTUAL_DEFAULT="$env:GRUB_DEFAULT"

if("x${env:GRUB_ACTUAL_DEFAULT}" -eq "xsaved") {
  $env:GRUB_ACTUAL_DEFAULT=(& ${grub_editenv} - list ) -replace "`nsaved_entry=",""
}


# These are defined in this script, export them here so that user can
# override them.
# $env:GRUB_DEVICE
# $env:GRUB_DEVICE_UUID
# $env:GRUB_DEVICE_PARTUUID
# $env:GRUB_DEVICE_BOOT
# $env:GRUB_DEVICE_BOOT_UUID
# $env:GRUB_DISABLE_OS_PROBER
# $env:GRUB_FS
# $env:GRUB_FONT
# $env:GRUB_PRELOAD_MODULES
# $env:GRUB_ACTUAL_DEFAULT

# These are optional, user-defined variables.
# $env:GRUB_DEFAULT
# $env:GRUB_HIDDEN_TIMEOUT
# $env:GRUB_HIDDEN_TIMEOUT_QUIET
# $env:GRUB_TIMEOUT
# $env:GRUB_TIMEOUT_STYLE
# $env:GRUB_DEFAULT_BUTTON
# $env:GRUB_HIDDEN_TIMEOUT_BUTTON
# $env:GRUB_TIMEOUT_BUTTON
# $env:GRUB_TIMEOUT_STYLE_BUTTON
# $env:GRUB_BUTTON_CMOS_ADDRESS
# $env:GRUB_BUTTON_CMOS_CLEAN
# $env:GRUB_DISTRIBUTOR
# $env:GRUB_CMDLINE_LINUX
# $env:GRUB_CMDLINE_LINUX_DEFAULT
# $env:GRUB_CMDLINE_LINUX_RECOVERY
# $env:GRUB_CMDLINE_XEN
# $env:GRUB_CMDLINE_XEN_DEFAULT
# $env:GRUB_CMDLINE_LINUX_XEN_REPLACE
# $env:GRUB_CMDLINE_LINUX_XEN_REPLACE_DEFAULT
# $env:GRUB_CMDLINE_NETBSD
# $env:GRUB_CMDLINE_NETBSD_DEFAULT
# $env:GRUB_CMDLINE_GNUMACH
# $env:GRUB_TOP_LEVEL
# $env:GRUB_TOP_LEVEL_XEN
# $env:GRUB_TOP_LEVEL_OS_PROBER
# $env:GRUB_EARLY_INITRD_LINUX_CUSTOM
# $env:GRUB_EARLY_INITRD_LINUX_STOCK
# $env:GRUB_TERMINAL_INPUT
# $env:GRUB_TERMINAL_OUTPUT
# $env:GRUB_SERIAL_COMMAND
# $env:GRUB_DISABLE_UUID
# $env:GRUB_DISABLE_LINUX_UUID
# $env:GRUB_DISABLE_LINUX_PARTUUID
# $env:GRUB_DISABLE_RECOVERY
# $env:GRUB_VIDEO_BACKEND
# $env:GRUB_GFXMODE
# $env:GRUB_BACKGROUND
# $env:GRUB_THEME
# $env:GRUB_GFXPAYLOAD_LINUX
# $env:GRUB_INIT_TUNE
# $env:GRUB_SAVEDEFAULT
# $env:GRUB_ENABLE_CRYPTODISK
# $env:GRUB_BADRAM
# $env:GRUB_OS_PROBER_SKIP_LIST
# $env:GRUB_DISABLE_SUBMENU

if("x${grub_cfg}" -ne "x") {
  Remove-Item -Force "${grub_cfg}.new" -ErrorAction SilentlyContinue
  Start-Transcript -Path "${grub_cfg}.new" -UseMinimalHeader
  $acl = Get-Acl -Path "${grub_cfg}.new"
  $acl.SetAccessRuleProtection($true, $false)
  $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
  $fileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl
  $type = [System.Security.AccessControl.AccessControlType]::Allow
  $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($identity, $fileSystemRights, $type)
  $acl.AddAccessRule($rule)
  Set-Acl -Path "${grub_cfg}.new" -AclObject $acl
}
Write-Error -ErrorAction Continue (& gettext "Generating grub configuration file ...")
Write-Error -ErrorAction Continue ""

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
      if((grub_file_is_not_garbage $i.FullName) -eq 0 -and (Test-Path $i.FullName -PathType Leaf)) {
        Write-Output ""
        Write-Output "### BEGIN $i ###"
        & $i.FullName
        Write-Output "### END $i ###"
      }
    }
  }
}

if("x${grub_cfg}" -ne "x") {
  if(-not (& ${grub_script_check} "${grub_cfg}.new")) {
    # TRANSLATORS: %s is replaced by filename
    Write-Error -ErrorAction Continue (& gettext_printf @"
    Syntax errors are detected in generated GRUB config file.
Ensure that there are no errors in /etc/default/grub
and /etc/grub.d/* files or please file a bug report with
{0} file attached." "${grub_cfg}.new
"@)
    Write-Error -ErrorAction Continue
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

Write-Error -ErrorAction Continue (& gettext "done")
Write-Error -ErrorAction Continue ""
