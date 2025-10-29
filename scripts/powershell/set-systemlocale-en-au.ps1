<#
.SYNOPSIS
    Sets the system locale, user language, UI language, home location, and culture to English (Australia).
.DESCRIPTION
    This script configures the Windows operating system to use English (Australia) settings for system locale
    and user preferences. It modifies the system locale, user language list, UI language override,
    home location, and culture settings.
.EXAMPLE
    .\set-systemlocale-en-au.ps1
    This example sets the system locale and related settings to English (Australia).

Author: James Kho
Publisher: Atarix
.Date: 2025-10-29
.Version: 1.0

#>

# Set system locale to English (Australia)
Set-WinSystemLocale en-AU

# Set user language list to English (Australia)
Set-WinUserLanguageList en-AU -Force

# Set UI language override to English (Australia)
Set-WinUILanguageOverride en-AU

# Set home location to Australia
Set-WinHomeLocation -GeoId 12  # 12 is Australia

# Set culture to English (Australia)
Set-Culture en-AU