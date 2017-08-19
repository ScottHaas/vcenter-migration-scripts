<#
.SYNOPSIS
Set Custom Attributes to VMs including vmFolder location and vNIC portgroup assignments. 
Mostly used for migrations between vCenters.

.PARAMETER Server
The hostname of the vCenter

.PARAMETER WhatIf
What if option to dry run

.EXAMPLE
PS> Set-VMAttrs-vmFolderandvNICs.ps1 -Server vcenter.domain.com -WhatIf
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true,HelpMessage="FQDN vCenter")]
    [ValidateNotNullOrEmpty()]
    [string]$server,

    [Parameter(Mandatory=$false,HelpMessage="What if option")]
    [switch]$WhatIf
)

#Functions
function Get-VMFolderPath {  
 <#  
 .SYNOPSIS  
 Get folder path of Virtual Machines  
 .DESCRIPTION  
 The function retrives complete folder Path from vcenter (Inventory >> Vms and Templates)  
 .NOTES   
 Author: Kunal Udapi  
 http://kunaludapi.blogspot.com
 Version 1  
 .PARAMETER N/a  
 No Parameters Required  
 .EXAMPLE  
  PS> Get-VM vmname | Get-VMFolderPath  
 .EXAMPLE  
  PS> Get-VM | Get-VMFolderPath  
 .EXAMPLE  
  PS> Get-VM | Get-VMFolderPath | Out-File c:\vmfolderPathlistl.txt  
 #>  
   Begin {} 
   Process {  
     foreach ($vm in $Input) {  
       $DataCenter = $vm | Get-Datacenter  
       $DataCenterName = $DataCenter.Name  
       #$VMname = $vm.Name  
       $VMname = ""
       $VMParentName = $vm.Folder  
       if ($VMParentName.Name -eq "vm") {  
         $FolderStructure = "{0}\{1}" -f $DataCenterName, $VMname  
         $FodlerStructure = $dataCenterName + "\"
         $FolderStructure  
         Continue  
       }#if ($VMParentName.Name -eq "vm")  
       else {  
         $FolderStructure = "{0}\{1}" -f $VMParentName.Name, $VMname  
         $VMParentID = Get-Folder -Id $VMParentName.ParentId  
         do {  
           $ParentFolderName = $VMParentID.Name  
           if ($ParentFolderName -eq "vm") {  
             $FolderStructure = "$DataCenterName\$FolderStructure"  
             $FolderStructure  
             break  
           } #if ($ParentFolderName -eq "vm")  
           $FolderStructure = "$ParentFolderName\$FolderStructure"  
           $VMParentID = Get-Folder -Id $VMParentID.ParentId  
         }   
         until ($VMParentName.ParentId -eq $DataCenter.Id)  
       } #else ($VMParentName.Name -eq "vm")  
     } 
   }   
   End {}   
 } 

#Connect
$viserver = connect-viserver $Server -ErrorAction Stop

#Main Code
$vms = get-vm -server $viserver
[System.Collections.ArrayList]$currVMCustomAttNames = @()
$currVMCustomAttNames += (get-customattribute -targetType VirtualMachine).Name

foreach ($vm in $vms){
    #vmFolder Attribute
    $newvmFolderValue = $vm|get-vmfolderpath
    if ($currVMCustomAttNames|?{$_ -eq "vmFolder"}){
        $currvmFolderValue = ($vm|get-annotation -customattribute "vmFolder").Value
        if ($currvmFolderValue -ne $newvmFolderValue){
            #write-host "curr: $currvmFolderValue - new: $newvmFolderValue"
            write-host "`nSetting $vm attribute vmFolder to $newvmFolderValue"
            try{$null = set-annotation -entity $vm -CustomAttribute "vmFolder" -value $newvmFolderValue -ErrorVariable Err -Whatif:$whatif}catch{write-host "Error: $Err"}
        }
    } else {
        write-host "`nCreating new attribute vmFolder"
        try{$null = New-CustomAttribute -targettype VirtualMachine -name "vmFolder" -ErrorVariable Err -Whatif:$whatif}catch{write-host "Error: $Err"}
        $currVMCustomAttNames += "vmFolder"
        write-host "Setting $vm attribute vmFolder to $newvmFolderValue"
        try{$null = set-annotation -entity $vm -CustomAttribute "vmFolder" -value $newvmFolderValue -ErrorVariable Err -Whatif:$whatif}catch{write-host "Error: $Err"}
    }

    #vNics
    #A number is added to each tag so vNIC0,vNIC1,vNIC2, etc
    $vmnics = get-networkadapter -vm $vm
    foreach ($vmnic in $vmnics){
        $vmname = $vm.name
        $networkvnic = "vNIC" + $vmnic.Name.split(" ")[-1]
        if (![string]::IsNullOrWhiteSpace($vmnic.NetworkName)){
            $networkname = $vmnic.NetworkName
            if ($currVMCustomAttNames|?{$_ -eq $networkvnic}){
               $currValue = ($vm|get-annotation -customattribute $networkvnic).value
               if ($currValue -ne $networkname){
                    write-host "Setting $vm attribute $networkvnic to $networkname"
                    try{$null = Set-Annotation -entity $vm -CustomAttribute $networkvnic -value $networkname -ErrorVariable Err -Whatif:$whatif}catch{write-host "Error: $Err"}
               }
            } else {
                write-host "Creating new attribute $networkvnic"
                try{$null = New-CustomAttribute -targettype VirtualMachine -name $networkvnic -ErrorVariable Err -Whatif:$whatif}catch{write-host "Error: $Err"}
                $currVMCustomAttNames += "$networkvnic"
                write-host "Setting $vm attribute $networkvnic to $networkname"
                try{$null = Set-Annotation -entity $vm -CustomAttribute $networkvnic -value $networkname -ErrorVariable Err -Whatif:$whatif}catch{write-host "Error: $Err"}
            }
        }
    }
}
write-host "Script Complete."
Disconnect-VIServer $viserver -confirm:$false