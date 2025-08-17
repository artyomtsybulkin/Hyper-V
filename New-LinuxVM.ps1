# Create standalone Hyper-V host virtual machine

$role = [PSCustomObject]@{
    node       = "localhost"
    vm         = "vm-podman-1"
    iso        = "C:\Sources"
    dist       = "fedora-coreos-42.20250721.3.0-live-iso.x86_64.iso"
    storage    = "C:\Hyper-V"
    vlan       = 0
}

$state = Get-VM -Name $role.vm -ErrorAction SilentlyContinue

if ($state) {
    Write-Warning "VM $($role.vm) already exists on $($role.node)."
} else {
    Write-Warning "Creating VM $($role.vm) on $($role.node)."
    # Create VM and attach regular storage
    $vm_path = "$($role.storage)\$($role.vm)\Virtual Machines"
    $vhd_path = "$($role.storage)\$($role.vm)\Virtual Hard Disks"
    if (-not (Test-Path $vm_path)) {
        New-Item -Path $vm_path -ItemType Directory -Force
    }
    if (-not (Test-Path $vhd_path)) {
        New-Item -Path $vhd_path -ItemType Directory -Force
    }
    New-VM -Name $role.vm -Generation 2 -Path $vm_path
    New-VHD -Path "$vhd_path\$($role.vm)-sda.vhdx"`
        -Dynamic -SizeBytes 256Gb -BlockSizeBytes 1MB
    Add-VMHardDiskDrive -VMName $role.vm `
        -Path "$vhd_path\$($role.vm)-sda.vhdx"
    # Configure VM settings
    Set-VM -Name $role.vm `
        -ProcessorCount 4 `
        -AutomaticCheckpointsEnabled $false -CheckpointType Production `
        -AutomaticStopAction ShutDown `
        -AutomaticStartAction Start -AutomaticStartDelay 30
    Set-VMMemory -VMName $role.vm `
        -StartupBytes 4Gb -DynamicMemoryEnabled $false
    Add-VMDvdDrive -VMName $role.vm `
        -Path "$($role.iso)\$($role.dist)"
    Set-VMFirmware -VMName $role.vm `
        -EnableSecureBoot On `
        -SecureBootTemplate MicrosoftUEFICertificateAuthority `
        -BootOrder @(
            (Get-VMHardDiskDrive -VMName $role.vm), 
            (Get-VMDvdDrive -VMName $role.vm)
        )
    Set-VMNetworkAdapter -VMName $role.vm `
        -IPsecOffloadMaximumSecurityAssociation 0 -VmqWeight 0
    Set-VMNetworkAdapterVlan -VMName $role.vm `
        -Access -VlanId $role.vlan
    Connect-VMNetworkAdapter -VMName $role.vm `
        -SwitchName "vSwitch"
}