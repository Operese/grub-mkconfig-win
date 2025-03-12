# Helper library for grub-mkconfig
# Copyright (C) 2007,2008,2009,2010  Free Software Foundation, Inc.
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
$datadir = "$env:datadir"
$bindir = "$env:bindir"
$sbindir = "$env:sbindir"
if ("x$env:pkgdatadir" -eq "x") {
  $env:pkgdatadir = "${datadir}/$env:PACKAGE"
}

if ("x$grub_probe" -eq "x") {
  $grub_probe = "${sbindir}/$env:grub_probe"
}

if ("x$grub_file" -eq "x") {
  $grub_file = "${bindir}/$env:grub_file"
}
if ("x$grub_mkrelpath" -eq "x") {
  $grub_mkrelpath="${bindir}/$env:grub_mkrelpath"
}

if (-not (Get-Command gettext -ErrorAction SilentlyContinue > $null)) {
  function gettext {
    "{0}" -f "$args"
  }
}

if (-not (Get-Command printf -ErrorAction SilentlyContinue > $null)) {
  function printf {
    [Console]::Write($args[0] -f $args[1..$($args.Length - 1)])
  }
}

function grub_warn {
  Write-Error -ErrorAction Continue "$(gettext "Warning:")" "$args"
}

function make_system_path_relative_to_its_root {
  & "${grub_mkrelpath}" $args[0]
}

function is_path_readable_by_grub {
  $path=$args[0]

  # abort if path doesn't exist
  if (-not (Test-Path "$path" -PathType Leaf)) {
    return 1
  }

  # abort if file is in a filesystem we can't read
  if (-not (& "${grub_probe}" -t fs "$path" > $null 2>&1)) {
    return 1
  }

  # ... or if we can't figure out the abstraction module, for example if
  # memberlist fails on an LVM volume group.
  $abstractions = (& ${grub_probe} -t abstraction "$path" 2> /dev/null)
  if (-not $abstractions) {
    return 1
  }

  if ("x$env:GRUB_ENABLE_CRYPTODISK" -eq "xy" ) {
    return 0
  }
  
  foreach ($abstraction in $abstractions -split '\s') {
    if ("x$abstraction" -eq "xcryptodisk") {
      return 1
    }
  }

  return 0
}

function convert_system_path_to_grub_path {
  $path=$args[0]

  grub_warn "convert_system_path_to_grub_path() is deprecated.  Use prepare_grub_to_access_device() instead."

  # abort if GRUB can't access the path
  if (-not (is_path_readable_by_grub "${path}")) {
    return 1
  }

  $drive = (& ${grub_probe} -t drive "$path")
  if (-not $drive) {
    return 1
  }

  $relative_path = (make_system_path_relative_to_its_root "$path")
  if (-not $relative_path) {
    return 1
  }

  Write-Output "${drive}${relative_path}"
}

function save_default_entry {
  if ("x${env:GRUB_SAVEDEFAULT}" -eq "xtrue") {
    Write-Output @"
savedefault
"@
  }
}

function prepare_grub_to_access_device {
  $partmap = (& ${grub_probe} --device $args --target=partmap)
  foreach ($module in $partmap -split "`n") {
    switch ($module) {
      "netbsd" {
        Write-Output "insmod part_bsd"
      }
      "openbsd" {
        Write-Output "insmod part_bsd"
      }
      default {
        Write-Output "insmod part_${module}"
      }
    }
  }

  # Abstraction modules aren't auto-loaded.
  $abstraction = (& ${grub_probe} --device $args --target=abstraction)
  foreach ($module in $abstraction -split "`n") {
    Write-Output "insmod ${module}"
  }

  $fs = (& ${grub_probe} --device $args --target=fs)
  foreach ($module in $fs -split "`n") {
    Write-Output "insmod ${module}"
  }

  if ( "x$env:GRUB_ENABLE_CRYPTODISK" -eq "xy") {
    foreach ($uuid in (& ${grub_probe} --device $args --target=cryptodisk_uuid)) {
      Write-Output "cryptomount -u $uuid"
    }
  }

  # If there's a filesystem UUID that GRUB is capable of identifying, use it;
  # otherwise set root as per value in device.map.
  $fs_hint = (& ${grub_probe} --device $args --target=compatibility_hint)
  if ("x$fs_hint" -ne "x") {
    Write-Output "set root='$fs_hint'"
  }
  $fs_uuid = (& ${grub_probe} --device $args --target=fs_uuid 2> $null)
  if ("x${env:GRUB_DISABLE_UUID}" -ne "xtrue" -and $fs_uuid) {
    $hints=(& ${grub_probe} --device $args --target=hints_string 2> $null)
    if ("x$hints" -ne "x") {
      Write-Output "if [ x\$feature_platform_search_hint = xy ]; then"
      Write-Output "  search --no-floppy --fs-uuid --set=root ${hints} ${fs_uuid}"
      Write-Output "else"
      Write-Output "  search --no-floppy --fs-uuid --set=root ${fs_uuid}"
      Write-Output "fi"
    }
    else {
      Write-Output "search --no-floppy --fs-uuid --set=root ${fs_uuid}"
    }
  }
}

function grub_get_device_id {
  $device = $args[0]
  $fs_uuid = (& ${grub_probe} --device ${device} --target=fs_uuid 2> $null)
  if ("x${env:GRUB_DISABLE_UUID}" -ne "xtrue" -and $fs_uuid) {
    Write-Output "$fs_uuid";
  }
  else {
    Write-Output $device -replace ' ', '_'
  }
}

function grub_file_is_not_garbage {
  if (Test-Path $args[0] -PathType Leaf) {
    switch -Wildcard ($args[0]) {
      '*.dpkg-*' { return 1 } # debian dpkg
      '*.rpmsave' { return 1 } 
      '*.rpmnew' { return 1 }
      'README*' { return 1 }
      '*/README*' { return 1 } # documentation
      '*.sig' { return 1 } # signatures
    }
  }
  else {
    return 1
  }
  return 0
}

function version_sort {
  switch ($version_sort_sort_has_v) {
    'yes' {
      $args | Sort-Object { [Version]$_ }-Culture InvariantCulture
    }
    'no' {
  
      $args | Sort-Object { ([int]($_ -replace "\D.*", "")) } -Culture InvariantCulture
    }
    default { 
      $version_sort_sort_has_v = "yes"
      $args | Sort-Object { [Version]$_ }-Culture InvariantCulture
    }
  }
}

# Given an item as the first argument and a list as the subsequent arguments,
# returns the list with the first argument moved to the front if it exists in
# the list.
function grub_move_to_front
{
  $item=$args[0]

  $item_found=$false
  foreach($i in $args[1..($args.Length - 1)]) {
  if("x$i" -eq "x$item") {
  $item_found=$true
  }
  }

  if("x$item_found" -eq "xtrue") {
  Write-Output "$item"
  }
  foreach($i in $args[1..($args.Length - 1)]) {
  if("x$i" -eq "x$item") {
    continue
  }
  Write-Output "$i"
  }
}

# One layer of quotation is eaten by "" and the second by sed; so this turns
# ' into \'.
function grub_quote {
  $args[0] -replace "'", "'\\''"
}

function gettext_quoted {
  grub_quote (gettext "$args")
}

# Run the first argument through gettext, and then pass that and all
# remaining arguments to printf.  This is a useful abbreviation and tends to
# be easier to type.
function gettext_printf {
  $gettext_printf_format=$args[0]
  $gettext_printf_args=$args[1..($args.Length - 1)]
  printf "$(gettext "$gettext_printf_format")" @gettext_printf_args
}

function uses_abstraction {
  $device=$args[0]

  $abstraction=(& ${grub_probe} --device ${device} --target=abstraction)
  foreach($module in ${abstraction} -split "`n") {
    if("x${module}" -eq "x$($args[1])") {
      return 0
    }
  }
  return 1
}

function print_option_help {
  if("x$print_option_help_wc" -eq "x") {
    $print_option_help_wc="-L"
  }
  if("x$grub_have_fmt" -eq "x") {
  $grub_have_fmt="y";
}
  $print_option_help_lead="  $($args[0])"
  $print_option_help_lspace="$(($print_option_help_lead -split "`n" | Measure-Object -Property Length -Maximum).Maximum)"
  $print_option_help_fill="$((26 - $print_option_help_lspace))"
  printf "{0}" "$print_option_help_lead"
  if($print_option_help_fill -le 0) {
  $print_option_help_nl=y
  Write-Output ""
  }
  else {
  $print_option_help_i=0;
  while($print_option_help_i -lt $print_option_help_fill) {
  printf " "
  $print_option_help_i++
  }
  $print_option_help_nl="n"
  }
  if("x$grub_have_fmt" -eq "xy") {
  $print_option_help_split="$(($args[1]  -split '(.{1,50})(?:\s+|$)' -join "`n").Trim())"
  }
  else {
  $print_option_help_split=$args[1]
  }
  if("x$print_option_help_nl" -eq "xy") {
    $print_option_help_split | ForEach-Object {
      "                          $_"
  }  
  }
  else {
    $print_option_help_split | ForEach-Object -Begin { $n = 0 } -Process {
      if ($n -eq 1) {
          "                          $_"
      } else {
          $_
      }
      $n = 1
  }
  
  }
}

function grub_fmt {
  ($args[0] -split '(.{1,40})(?:\s+|$)' -join "`n").Trim()
}

$grub_tab="	"

function grub_add_tab {
  $args[0] -replace "^", $grub_tab
}

