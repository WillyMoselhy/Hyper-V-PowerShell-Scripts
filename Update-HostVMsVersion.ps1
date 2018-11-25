function UpdateOrSkip{
    $Choice = 0
    do{
        $Choice = Read-Host  'Press Enter to update, S to skip'
    }
    until  ($Choice -eq "" -or $Choice -eq "s")
    switch ($Choice){
        ""  {return $true} #True means update the vm version
        "s" {return $false}
    }
}
function UpdateVMVersion{
    Write-Host "`t$VMName is offline." -ForegroundColor Green
    Update-VMVersion -VM $VM
    Write-Host "`tVM version updated." -ForegroundColor Green
}
 
$CurrentVMVersion = (Get-VMHostSupportedVersion -Default).Version.ToString()
$OldVMs = Get-VM | ?{$_.Version -ne $CurrentVMVersion}
 
foreach ($VM in $OldVMs){
    $VMName = $VM.Name
    Write-Host "`nNow Processing: $VMName" -ForegroundColor Cyan
    switch ($VM.State){
        "Off"{
            if(UpdateOrSkip){ UpdateVMVersion }
        }
        "Running"{
            if(UpdateOrSkip){ 
                Write-Host "`tShutting down VM: $VMName" -ForegroundColor DarkYellow
                Stop-VM -VM $VM
                $VMState = ($VM | Get-VM).State
                if($VMState -eq "Off"){
                    UpdateVMVersion
                    Start-VM -VM $VM
                    Write-Host "`tVM Started"
                }
                else{
                    Write-Host "`tFailed to shutdown $VMName."
                }
            }
        }
        Default{
            Write-Host "`t$VMName is $($VM.State) and cannot be processed" -ForegroundColor Red
        }
    }
}
