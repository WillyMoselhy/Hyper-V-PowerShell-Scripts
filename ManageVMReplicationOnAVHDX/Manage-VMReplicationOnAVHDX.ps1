Param(
    [Parameter(Position = 1, Mandatory = $true)]
    # List of VMs to run the script against.
    [string[]] $Name,

    [Parameter(Mandatory = $false)]
    # Path to store log file
    [string] $LogFolder,

    [Parameter(Mandatory = $false)]
    # Show log on screen
    [switch] $HostMode
)

    
#region: Script Configuration
    $ErrorActionPreference = "Stop"
    if($LogFolder){
        $LogFolderObject = New-Item -Path $LogFolder -ItemType Directory -Force
        $TimeStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $LogPath = "$LogFolderObject\ManageVMReplicationOnAVHDX_$TimeStamp.log"
    }
    if($LogPath){ # Logs will be saved to disk at the specified location
        $ScriptMode=$true
    }
    else{ # Logs will not be saved to disk
        $ScriptMode = $false
    }
    $LogLevel = 0
    $Trace    = ""   
#endregion: Script Configuration

#region: Logging Functions 
    #This writes the actual output - used by other functions
    function WriteLine ([string]$line,[string]$ForegroundColor, [switch]$NoNewLine){
        if($Script:ScriptMode){
            if($NoNewLine) {
                $Script:Trace += "$line"
            }
            else {
                $Script:Trace += "$line`r`n"
            }
            Set-Content -Path $script:LogPath -Value $Script:Trace
        }
        if($Script:HostMode){
            $Params = @{
                NoNewLine       = $NoNewLine -eq $true
                ForegroundColor = if($ForegroundColor) {$ForegroundColor} else {"White"}
            }
            Write-Host $line @Params
        }
    }
    
    #This handles informational logs
    function WriteInfo([string]$message,[switch]$WaitForResult,[string[]]$AdditionalStringArray,[string]$AdditionalMultilineString){
        if($WaitForResult){
            WriteLine "[$(Get-Date -Format hh:mm:ss)] INFO:    $("`t" * $script:LogLevel)$message" -NoNewline
        }
        else{
            WriteLine "[$(Get-Date -Format hh:mm:ss)] INFO:    $("`t" * $script:LogLevel)$message"  
        }
        if($AdditionalStringArray){
                foreach ($String in $AdditionalStringArray){
                    WriteLine "[$(Get-Date -Format hh:mm:ss)]          $("`t" * $script:LogLevel)`t$String"     
                }
       
        }
        if($AdditionalMultilineString){
            foreach ($String in ($AdditionalMultilineString -split "`r`n" | Where-Object {$_ -ne ""})){
                WriteLine "[$(Get-Date -Format hh:mm:ss)]          $("`t" * $script:LogLevel)`t$String"     
            }
       
        }
    }

    #This writes results - should be used after -WaitFor Result in WriteInfo
    function WriteResult([string]$message,[switch]$Pass,[switch]$Success){
        if($Pass){
            WriteLine " - Pass" -ForegroundColor Cyan
            if($message){
                WriteLine "[$(Get-Date -Format hh:mm:ss)] INFO:    $("`t" * $script:LogLevel)`t$message" -ForegroundColor Cyan
            }
        }
        if($Success){
            WriteLine " - Success" -ForegroundColor Green
            if($message){
                WriteLine "[$(Get-Date -Format hh:mm:ss)] INFO:    $("`t" * $script:LogLevel)`t$message" -ForegroundColor Green
            }
        } 
    }

    #This write highlighted info
    function WriteInfoHighlighted([string]$message,[string[]]$AdditionalStringArray,[string]$AdditionalMultilineString){ 
        WriteLine "[$(Get-Date -Format hh:mm:ss)] INFO:    $("`t" * $script:LogLevel)$message"  -ForegroundColor Cyan
        if($AdditionalStringArray){
            foreach ($String in $AdditionalStringArray){
                WriteLine "[$(Get-Date -Format hh:mm:ss)]          $("`t" * $script:LogLevel)`t$String" -ForegroundColor Cyan
            }
        }
        if($AdditionalMultilineString){
            foreach ($String in ($AdditionalMultilineString -split "`r`n" | Where-Object {$_ -ne ""})){
                WriteLine "[$(Get-Date -Format hh:mm:ss)]          $("`t" * $script:LogLevel)`t$String" -ForegroundColor Cyan
            }
        }
    }

    #This write warning logs
    function WriteWarning([string]$message,[string[]]$AdditionalStringArray,[string]$AdditionalMultilineString){ 
        WriteLine "[$(Get-Date -Format hh:mm:ss)] WARNING: $("`t" * $script:LogLevel)$message"  -ForegroundColor Yellow
        if($AdditionalStringArray){
            foreach ($String in $AdditionalStringArray){
                WriteLine "[$(Get-Date -Format hh:mm:ss)]          $("`t" * $script:LogLevel)`t$String" -ForegroundColor Yellow
            }
        }
        if($AdditionalMultilineString){
            foreach ($String in ($AdditionalMultilineString -split "`r`n" | Where-Object {$_ -ne ""})){
                WriteLine "[$(Get-Date -Format hh:mm:ss)]          $("`t" * $script:LogLevel)`t$String" -ForegroundColor Yellow
            }
        }
    }

    #This logs errors
    function WriteError([string]$message){
        WriteLine ""
        WriteLine "[$(Get-Date -Format hh:mm:ss)] ERROR:   $("`t`t" * $script:LogLevel)$message" -ForegroundColor Red
        
    }

    #This logs errors and terminated script
    function WriteErrorAndExit($message){
        WriteLine "[$(Get-Date -Format hh:mm:ss)] ERROR:   $("`t" * $script:LogLevel)$message"  -ForegroundColor Red
        Write-Host "Press any key to continue ..."
        $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | OUT-NULL
        $HOST.UI.RawUI.Flushinputbuffer()
        Throw "Terminating Error"
    }

#endregion: Logging Functions

#region: Script Functions
function VMReplicationState ($VMName){
    WriteInfo "Getting replication state for $VMName"
        $ReplicationState = Get-VMReplication -VMName $VMName -ErrorAction SilentlyContinue -ErrorVariable StateError
    
    if($ReplicationState){
        WriteInfo "Replication state is: $($ReplicationState.State.ToString())"
        return @{
            Enabled = $true
            State   = $ReplicationState.State.ToString() #Ideally should return Replicating or Suspended
        }
    }
    else{ #If we failed to get replication state return the error
        WriteWarning "Did not retreive replication state: $($StateError[0].Exception.Message)"
        return @{
            Enabled = $false
            Error   = $StateError[0].Exception.Message
        }
    }
}

function AHVDXFilesAttached ($VM){
    WriteInfo "Getting list of VM Disks" -WaitForResult
        $VMDisks = $VM.HardDrives.Path
    WriteResult -Success -message "VM has $($VMdisks.Count) disks"

    WriteInfo "Filtering by AVHDX"
        $AVHDXs = $VMDisks |Where-Object {$_ -like "*.AVHDX"}
    
    if($AVHDXs){ # We have AVHDXs!
        WriteInfo "The following disks are AVHDX" -AdditionalMultilineString $AVHDXs
        return $true
    }
    else{
        WriteInfo "VM does not have any AVHDX disks attached."
        return $false
    }
}
#endregion: Script Functions


WriteInfo -message "Working on $Env:COMPUTERNAME - $(Get-Date -Format U)"
WriteInfo -message "$(whoami.exe)"
WriteInfo -message "Will process the following VMs" -AdditionalStringArray $Name
foreach ($VMName in $Name){
    $LogLevel = 0
    WriteInfo -message "Processing VM: $VMName"
    $LogLevel++
    
    #region: Get VM replication state
    WriteInfo -message "ENTER: Get VM replication state"
    $LogLevel++
    
        $ReplicationState = VMReplicationState -VMName $VMName
    
    $LogLevel--
    WriteInfo -message "Exit: Get VM replication state"
    #endregion: Get VM replication state
    
    if($ReplicationState.Enabled){ #We skip if replication is disabled
        WriteInfo -message "Getting VM Object" -WaitForResult
            $VM = Get-VM -Name $VMName
        WriteResult -Success

        #region: Check for attached AVHDX files
        WriteInfo -message "ENTER: Check for attached AVHDX files"
        $LogLevel++
        
            $AVHDXAttached = AHVDXFilesAttached -VM $VM
        
        $LogLevel--
        WriteInfo -message "Exit: Check for attached AVHDX files"
        #endregion: Check for attached AVHDX files

        #region: Perform action depending on state and AVHDX results
        WriteInfo -message "ENTER: Perform action depending on state and AVHDX results"
        $LogLevel++
        
            $SwitchString = "Replication: $($ReplicationState.State) - AVHDX Attached: $AVHDXAttached"
            WriteInfo -message "$SwitchString"

            Switch ($SwitchString){
                "Replication: Replicating - AVHDX Attached: True"{
                    WriteInfo -message ">>> Suspending VM replication for '$VMName' <<<" -WaitForResult
                        Suspend-VMReplication -VM $VM
                    WriteResult -Success
                }
                "Replication: Suspended - AVHDX Attached: False"{
                    WriteInfo -message ">>> Resuming VM replication for '$VMName' <<<" -WaitForResult
                        Resume-VMReplication -VM $VM
                    WriteResult -Success

                } 
                default{
                    WriteInfo -message ">>> Will not change VM replication state for '$VMName' <<<"
                }               
            }
        
        $LogLevel--
        WriteInfo -message "Exit: Perform action depending on state and AVHDX results"
        #endregion: Perform action depending on state and AVHDX results 
    }
    else{
        WriteInfo "Skipping VM"
        continue
    }
}
$LogLevel = 0
WriteInfo "Finished processing all VMs"
WriteInfo "Terminating script"