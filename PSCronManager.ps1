#Either "# Requires -Modules BW.Utils.PSCron" or load module from the path folder direct if not installed in modules...
Import-Module -name .\BW.Utils.PSCron

#Point it as the Schedule config file and thats it
$shedulerTextFile = ".\schedule.txt"

#Here be dragons...
#
#Load the scheduler file and return an object list (reloads after each run or hourly - so no need to restart services!)
function GetJobs ($schedulefile) {
    $schJob=@()
    Foreach ($schefline in gc $schedulefile | where {$_ -notmatch '^#.*' -AND $_ -ne ''}){
        $Scheduletask = $schefline.split("`t")
        if ($Scheduletask.Length -eq 3) { 
        $schJob+=([pscustomobject]@{cron=$Scheduletask[0];command=$Scheduletask[1];path=$Scheduletask[2]})
            } else {
        write-host "Error in file: $schefline "
        }
    }
    return ,$schJob
}

#Start the merry go round
while ($true) {
    $ReferenceDate = Get-PSCronDate
    $LogFileTimestamp = $ReferenceDate.Local.ToString('yyyy-MM-dd')
    $LogFileName = "$PSScriptRoot\logs\cron-$LogFileTimestamp.log"

    # Here we use splatting to combine common cron options
    $CronSplat = @{
        ReferenceDate = $ReferenceDate
        LogPath       = $LogFileName
        Append        = $true
        TimeOut       = 3600
    }

    #clean up log files older than 7 days
    Get-ChildItem  .\logs -Filter *.log |    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |    Remove-Item -Confirm:$false -Force -ErrorAction SilentlyContinue


    #Reload schedule and set timeout to 1hr or next runtime
    $joblist= getjobs $shedulerTextFile
    $sleep = 3600
    foreach ($sctask in $joblist){
        #Squirt the comand into a scriptblock
        $pscmd= "Start-Process -FilePath ""$($sctask.command)"" -WorkingDirectory ""$($sctask.path)"""
        $scriptblock= [scriptblock]::create($pscmd)
        #Do stuff
        Invoke-PSCronJob $sctask.cron "$($sctask.command)" $scriptblock @CronSplat -PassThru
        #work out when the next execute time is
        $nextrun= (New-TimeSpan -End $((Get-PSCronNextRun $sctask.cron).local)).TotalSeconds
        if ($nextrun -lt $sleep -and $nextrun -ge 1) {$sleep = $nextrun}
        }
    write-host "Sleeping for $([Math]::Truncate($sleep)) seconds"
    $sleep++
    sleep $sleep

}