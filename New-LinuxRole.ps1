# Create a new Linux VM role in Hyper-V cluster

$role = [PSCustomObject]@{
    cluster    = "cluster.domain.com"
    node       = "server.domain.com"
    vm         = "docker-vm.domain.com"
    iso        = "C:\ClusterStorage\Volume1\Setup"
    dist       = "AlmaLinux-10.0-x86_64-minimal.iso"
    storage    = "C:\ClusterStorage\Volume3"
    vlan       = 1
}

$state = Get-VM -Name $role.vm `
    -CimSession $role.cluster -ErrorAction SilentlyContinue

if ($state) {
    Write-Warning "VM $($role.vm) already exists on $($role.cluster)."
} else {
    Write-Warning "Creating VM $($role.vm) on $($role.cluster)."
    # Create VM and attach regular storage
    Invoke-Command -ComputerName $role.node -ScriptBlock {
        param($role)
        $vm_path = "$($role.storage)\Hyper-V\$($role.vm)\Virtual Machines"
        $vhd_path = "$($role.storage)\Hyper-V\$($role.vm)\Virtual Hard Disks"
        if (-not (Test-Path $vm_path)) {
            New-Item -Path $vm_path -ItemType Directory -Force
        }
        if (-not (Test-Path $vhd_path)) {
            New-Item -Path $vhd_path -ItemType Directory -Force
        }
        New-VM -Name $role.vm -Generation 2 -Path $vm_path
        New-VHD -Path "$vhd_path\$($role.vm)-sda.vhdx" `
            -Dynamic -SizeBytes 256Gb -BlockSizeBytes 1MB
        Add-VMHardDiskDrive -VMName $role.vm `
            -Path "$vhd_path\$($role.vm)-sda.vhdx"
    } -ArgumentList $role
    # Configure VM settings
    Set-VM -Name $role.vm -CimSession $role.node `
        -AutomaticCheckpointsEnabled $false -CheckpointType Production `
        -AutomaticStopAction ShutDown `
        -AutomaticStartAction Start -AutomaticStartDelay 30
    Set-VMMemory -VMName $role.vm -CimSession $role.node `
        -StartupBytes 8Gb -DynamicMemoryEnabled $false
    Add-VMDvdDrive -VMName $role.vm -CimSession $role.node `
        -Path "$($role.iso)\$($role.dist)"
    Set-VMFirmware -VMName $role.vm -CimSession $role.node `
        -EnableSecureBoot On `
        -SecureBootTemplate MicrosoftUEFICertificateAuthority `
        -BootOrder @(
            (Get-VMHardDiskDrive -VMName $role.vm -CimSession $role.node), 
            (Get-VMDvdDrive -VMName $role.vm -CimSession $role.node)
        )
    Set-VMNetworkAdapter -VMName $role.vm -CimSession $role.node `
        -IPsecOffloadMaximumSecurityAssociation 0 -VmqWeight 0
    Set-VMNetworkAdapterVlan -VMName $role.vm -CimSession $role.node `
        -Access -VlanId $role.vlan
    Connect-VMNetworkAdapter -VMName $role.vm -CimSession $role.node `
        -SwitchName "vSwitch"
    # Add VM to cluster
    Add-ClusterVirtualMachineRole -VMName $role.vm -Cluster $role.cluster
}