$ErrorActionPreference = "Stop"

# grub-mkconfig helper script.
# Copyright (C) 2006,2007,2008,2009,2010  Free Software Foundation, Inc.
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

$prefix = "@prefix@"
$exec_prefix = "@exec_prefix@"
$datarootdir = "@datarootdir@"
$grub_lang = [System.Globalization.CultureInfo]::CurrentCulture.Name

$env:TEXTDOMAIN = "@PACKAGE@"
$env:TEXTDOMAINDIR = "@localedir@"

. "$pkgdatadir/grub-mkconfig_lib.ps1"

# Do this as early as possible, since other commands might depend on it.
# (e.g. the `loadfont' command might need lvm or raid modules)
foreach ($i in ${GRUB_PRELOAD_MODULES}) {
  Write-Output "insmod $i"
}

if ("x${GRUB_DEFAULT}" -eq "x") { $GRUB_DEFAULT = 0 }
if ("x${GRUB_DEFAULT}" -eq "xsaved") { $GRUB_DEFAULT = '${saved_entry}' }
if ("x${GRUB_TIMEOUT}" -eq "x") { $GRUB_TIMEOUT = 5 }
if ("x${GRUB_GFXMODE}" -eq "x") { $GRUB_GFXMODE = "auto" }

if ("x${GRUB_DEFAULT_BUTTON}" -eq "x") { $GRUB_DEFAULT_BUTTON = "$GRUB_DEFAULT" }
if ("x${GRUB_DEFAULT_BUTTON}" -eq "xsaved") { $GRUB_DEFAULT_BUTTON = '${saved_entry}' }
if ("x${GRUB_TIMEOUT_BUTTON}" -eq "x") { $GRUB_TIMEOUT_BUTTON = "$GRUB_TIMEOUT" }

Write-Output @"
if [ -s \$prefix/grubenv ]; then
  load_env
fi
"@
if ("x$GRUB_BUTTON_CMOS_ADDRESS" -ne "x") {
  Write-Output @"
if cmostest $GRUB_BUTTON_CMOS_ADDRESS ; then
   set default="${GRUB_DEFAULT_BUTTON}"
elif [ "\${next_entry}" ] ; then
   set default="\${next_entry}"
   set next_entry=
   save_env next_entry
   set boot_once=true
else
   set default="${GRUB_DEFAULT}"
fi
"@
}
else {
  Write-Output @"
if [ "\${next_entry}" ] ; then
   set default="\${next_entry}"
   set next_entry=
   save_env next_entry
   set boot_once=true
else
   set default="${GRUB_DEFAULT}"
fi
"@
}
Write-Output @"

if [ x"\${feature_menuentry_id}" = xy ]; then
  menuentry_id_option="--id"
else
  menuentry_id_option=""
fi

export menuentry_id_option

if [ "\${prev_saved_entry}" ]; then
  set saved_entry="\${prev_saved_entry}"
  save_env saved_entry
  set prev_saved_entry=
  save_env prev_saved_entry
  set boot_once=true
fi

function savedefault {
  if [ -z "\${boot_once}" ]; then
    saved_entry="\${chosen}"
    save_env saved_entry
  fi
}

function load_video {
"@
if ("${GRUB_VIDEO_BACKEND}" ) {
  Write-Output @"
  insmod ${GRUB_VIDEO_BACKEND}
"@
}
else {
  # If all_video.mod isn't available load all modules available
  # with versions prior to introduction of all_video.mod
  Write-Output @"
  if [ x\$feature_all_video_module = xy ]; then
    insmod all_video
  else
    insmod efi_gop
    insmod efi_uga
    insmod ieee1275_fb
    insmod vbe
    insmod vga
    insmod video_bochs
    insmod video_cirrus
  fi
"@
}
Write-Output @"
}

"@

$serial = 0
$gfxterm = 0

foreach ($x in $GRUB_TERMINAL_INPUT, $GRUB_TERMINAL_OUTPUT) {
  if ("serial" -eq $x) {
    $serial = 1
  }
  if ("gfxterm" -eq $x) {
    $gfxterm = 1
  }
}

if ("x$serial" -eq "x1") {
  if ("x${GRUB_SERIAL_COMMAND}" -eq "x") {
    grub_warn "$(gettext "Requested serial terminal but GRUB_SERIAL_COMMAND is unspecified. Default parameters will be used.")"
    $GRUB_SERIAL_COMMAND = serial
  }
  Write-Output "${GRUB_SERIAL_COMMAND}"
}

if ("x$gfxterm" -eq "x1") {
  if ("$GRUB_FONT") {
    # Make the font accessible
    prepare_grub_to_access_device `$ { grub_probe } --target=device "${GRUB_FONT}"`
      Write-Output @"
if loadfont `make_system_path_relative_to_its_root "${GRUB_FONT}"` ; then
"@
  }
  else {
    :Dirs foreach ($dir in "${pkgdatadir}", (Write-Output '/@bootdirname@/@grubdirname@' | ForEach-Object { $_ -replace '/+', '/' }), "/usr/share/grub") {
      :Charsets foreach ($basename in "unicode", "unifont", "ascii") {
        $path = "${dir}/${basename}.pf2"
        if (is_path_readable_by_grub "${path}" > $null) {
          $font_path = "${path}"
        }
        else {
          continue
        }
        break :Dirs
      }
    }
    if ("${font_path}") {
      Write-Output @"
if [ x\$feature_default_font_path = xy ] ; then
   font=unicode
else
"@
      # Make the font accessible
      prepare_grub_to_access_device `$ { grub_probe } --target=device "${font_path}"`
        Write-Output @"
    font="`make_system_path_relative_to_its_root "${font_path}"`"
        }

if loadfont \$font ; then
"@
    }
    else {
      Write-Output @"
if loadfont unicode ; then
"@
    }
  }

  Write-Output @"
  set gfxmode=${GRUB_GFXMODE}
  load_video
  insmod gfxterm
"@

  # Gettext variables and module
  if ("x${grub_lang}" -ne "xC" -and "x${LANG}" -ne "xPOSIX" -and "x${LANG}" -ne "x") {
    Write-Output @"
  set locale_dir=\$prefix/locale
  set lang=${grub_lang}
  insmod gettext
"@
  }

  Write-Output @"
fi
"@
}

switch ("x$env:GRUB_TERMINAL_INPUT") {
  "x" {
    # Just use the native terminal
  }
  default {
    Write-Output @"
terminal_input $env:GRUB_TERMINAL_INPUT
"@
  }
}

switch ("x$env:GRUB_TERMINAL_OUTPUT") {
  "x" {
    # Just use the native terminal
  }
  default {
    Write-Output @"
terminal_output $env:GRUB_TERMINAL_OUTPUT
"@
  }
}


if ("x$gfxterm" -eq "x1") {
  if ("x$GRUB_THEME" -ne "x" -and (Test-Path "$GRUB_THEME" -PathType Leaf) -and (is_path_readable_by_grub "$GRUB_THEME")) {
    Write-Error "$(gettext_printf "Found theme: %s\n")" "$GRUB_THEME"

    prepare_grub_to_access_device `$ { grub_probe } --target=device "$GRUB_THEME"`
      Write-Output @"
insmod gfxmenu
"@
    $themedir = (Split-Path -Parent "$GRUB_THEME")
    Get-ChildItem -Path "$themedir"/*.pf2, "$themedir"/f/*.pf | ForEach-Object {
      if (Test-Path "$_" -PathType Leaf) {
        Write-Output @"
loadfont (\$root)`make_system_path_relative_to_its_root $_`
"@
      }
    }
    if ( (Get-ChildItem "$themedir/*.jpg") -or (Get-ChildItem "$themedir/*.jpeg")) {
      Write-Output @"
insmod jpeg
"@
    }
    if (Get-ChildItem "$themedir/*.png") {
      Write-Output @"
insmod png
"@
    }
    if (Get-ChildItem "$themedir/*.tga") {
      Write-Output @"
insmod tga
"@
    }
	    
    Write-Output @"
set theme=(\$root)`make_system_path_relative_to_its_root $GRUB_THEME`
export theme
"@
  }
  elseif ("x$GRUB_BACKGROUND" -ne "x" -and (Test-File "$GRUB_BACKGROUND" -PathType Leaf) -and (is_path_readable_by_grub "$GRUB_BACKGROUND")) {
    Write-Error "$(gettext_printf "Found background: %s\n")" "$GRUB_BACKGROUND"
    switch -Wildcard ($GRUB_BACKGROUND) {
      '*.png' { $reader = 'png' }
      '*.tga' { $reader = 'tga' }
      '*.jpg' { $reader = 'jpeg' }
      '*.jpeg' { $reader = 'jpeg' }
      default {
        Write-Error "$(gettext "Unsupported image format")"
        Write-Error ""
        exit 1
      }
    }
    prepare_grub_to_access_device `$ { grub_probe } --target=device "$GRUB_BACKGROUND"`
      Write-Output @"
insmod $reader
background_image -m stretch "`make_system_path_relative_to_its_root "$GRUB_BACKGROUND"`"
"@
  }
}

function make_timeout {
  if ("x${args[2]}" -ne "x") {
    $timeout = "${args[1]}"
    $style = "${args[2]}"
  }
  elseif ("x${args[0]}" -ne "x" -and "x${args[0]}" -ne "x0") {
    # Handle the deprecated GRUB_HIDDEN_TIMEOUT scheme.
    $timeout = "${args[0]}"
    if ("x${args[1]}" -ne "x0") {
      grub_warn "$(gettext "Setting GRUB_TIMEOUT to a non-zero value when GRUB_HIDDEN_TIMEOUT is set is no longer supported.")"
    }
    if ("x${GRUB_HIDDEN_TIMEOUT_QUIET}" -eq "xtrue") {
      $style = "hidden"
      $verbose = ""
    }
    else {
      style="countdown"
      verbose=" --verbose"
    }
    else {
      # No hidden timeout, so treat as GRUB_TIMEOUT_STYLE=menu
      $timeout = "${args[1]}"
      $style = "menu"
    }
    Write-Output @"
if [ x\$feature_timeout_style = xy ] ; then
  set timeout_style=${style}
  set timeout=${timeout}
"@
    if ("x${style}" -eq "xmenu") {
      Write-Output @"
# Fallback normal timeout code in case the timeout_style feature is
# unavailable.
else
  set timeout=${timeout}
"@
    }
    else {
      Write-Output @"
# Fallback hidden-timeout code in case the timeout_style feature is
# unavailable.
elif sleep${verbose} --interruptible ${timeout} ; then
  set timeout=0
"@
    }
    Write-Output @"
fi
"@
  }
}

  if ("x$GRUB_BUTTON_CMOS_ADDRESS" -ne "x") {
    Write-Output @"
if cmostest $GRUB_BUTTON_CMOS_ADDRESS ; then
"@
    make_timeout "${GRUB_HIDDEN_TIMEOUT_BUTTON}" "${GRUB_TIMEOUT_BUTTON}" "${GRUB_TIMEOUT_STYLE_BUTTON}"
    Write-Output "else"
    make_timeout "${GRUB_HIDDEN_TIMEOUT}" "${GRUB_TIMEOUT}" "${GRUB_TIMEOUT_STYLE}"
    Write-Output "fi"
    else
    make_timeout "${GRUB_HIDDEN_TIMEOUT}" "${GRUB_TIMEOUT}" "${GRUB_TIMEOUT_STYLE}"
  }

  if ("x$GRUB_BUTTON_CMOS_ADDRESS" -ne "x" -and "x$GRUB_BUTTON_CMOS_CLEAN" -eq "xyes") {
    Write-Output @"
cmosclean $GRUB_BUTTON_CMOS_ADDRESS
"@
  }

  # Play an initial tune
  if ("x${GRUB_INIT_TUNE}" -ne "x") {
    Write-Output "play ${GRUB_INIT_TUNE}"
  }

  if ("x${GRUB_BADRAM}" -ne "x") {
    Write-Output "badram ${GRUB_BADRAM}"
  }
