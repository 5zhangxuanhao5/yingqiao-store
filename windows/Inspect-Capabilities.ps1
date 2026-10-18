# Read only. Does not install drivers, change signing policy, capture screens or connect anywhere.
$ErrorActionPreference = 'Stop'
$os = Get-CimInstance Win32_OperatingSystem
$gpu = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion
$adapters = Get-NetAdapter -Physical | Select-Object InterfaceDescription, MediaType, Status, LinkSpeed
[pscustomobject]@{
    OSVersion = $os.Version
    Architecture = $os.OSArchitecture
    Graphics = $gpu
    PhysicalNetworkAdapters = $adapters
    ExtensionDriverImplemented = $false
    HardwareEncoderVerified = $false
    Note = 'Inventory is local only; do not publish without redacting device details. No compatibility claim.'
} | ConvertTo-Json -Depth 5
