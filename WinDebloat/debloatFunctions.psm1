$global:helpersExecuted = $false
#Requires -RunAsAdministrator
function Remove-App {
# Function for removing Apps
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$appName
    )

    try {
        # Check if the app is installed
        $installedPackage = Get-AppxPackage -Name $appName -ErrorAction SilentlyContinue
        
        if ($installedPackage) {
            $packageFullName = $installedPackage.PackageFullName
            $result = Remove-AppxPackage -Package $packageFullName -ErrorAction Stop

            if ($null -eq $result) {
                Write-Output "[+] $appName has been successfully removed."
            } else {
                Write-Output "[-] Failed to remove $appName."
            }
        }
        else {
            Write-Output "[?] $appName not found on the system."
        }
        # Check if the app is provisioned
        $provisionedPackage = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $appName } -ErrorAction SilentlyContinue
        if ($provisionedPackage) {
            $result = Remove-AppxProvisionedPackage -PackageName $provisionedPackage.PackageName -Online  

            if ($result) {
                Write-Output "[+] Provisioned $appName has been successfully removed."
            } else {
                Write-Output "[-] Failed to remove provisioned app $appName."
            }
        } else {
            Write-Output "[?] Provisioned $appName not found on the system."
        }
    } 
    catch {
        Write-Error "An error occurred while removing the app or provisioned package. Error: $_"
    }
}


function Remove-Service {
# Function for removing Services
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$serviceName
    )

    try {
        $service = Get-Service -Name $serviceName -ErrorAction Stop

        if ($service) {
            $service | Set-Service -StartupType Manual -ErrorAction Stop
            Write-Output "[+] $serviceName has been disabled."
        } else {
            Write-Output "[-] $serviceName not found."
        }
    }
    catch {
        Write-Error "An error occurred while setting the service startup type. Error: $_"
    }
}

function Delete-Task {
# Function for disabling scheduled tasks
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$name,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$value
    )

    try {
        $output = Disable-ScheduledTask -TaskName $value -ErrorAction SilentlyContinue
        if ($output){
            Write-Output "[+] Scheduled task '$name' has been disabled."
        }
        else{
            Write-Output "[-] Scheduled task '$name' not found."
        }
    
    }
    catch {
        Write-Error "An error occurred while disabling the scheduled task. Error: $_"
    }
}

function Remove-RegistryValue {
# Function for setting Registry items
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $name,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $path,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $value,

        [Parameter(Mandatory=$true)]
        [ValidateSet("String", "ExpandString", "Binary", "DWord", "QWord", "MultiString", "Unknown")]
        [string] $type,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $data
    )

    try {
        # Validate the value based on the type parameter
        if ($type -eq "DWord" -or $type -eq "QWord") {
            $validatedData = [int64]::Parse($data)
        }
        elseif ($type -eq "Binary") {
            $validatedData = [byte[]]::new(($data -split '(.{2})' | Where-Object { $_ -match '..' } | ForEach-Object { [convert]::ToByte($_, 16) }))

        }
        else {
            $validatedData = $data
        }

        # check if path exists. If not, create the path for the registry value
        if (!(Test-Path -Path $path)) {
            # Create the registry key
            New-Item -Path $path -Force | Out-Null
            Write-Output "`t[+] Registry key created: $path"
        }
        else {
            Write-Output "`t[-] Registry key already exists: $path"
        }

        Set-ItemProperty -Path $path -Name $value -Value $validatedData -Type $type -Force | Out-Null
        Write-Output "[+] $name has been successful"
    }
    catch {
        Write-Error "Failed to update the registry value. Error: $_"
    }
}

function Remove-Path {
# Function for removing Paths/Programs
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$name,

        [Parameter(Mandatory=$true)]
        [ValidateSet("file", "dir")]
        [string]$type,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$path
    )

    try {
        if ($type -eq "file") {
            if (Test-Path -Path $path -PathType Leaf) {
                Remove-Item -Path $path -Force
                Write-Output "[+] $name has been removed."
            } else {
                Write-Output "[-] $path does not exist."
            }
        }
        elseif ($type -eq "dir") {
            if (Test-Path -Path $path -PathType Container) {
                Remove-Item -Path $path -Recurse -Force
                Write-Output "[+] $name has been removed."
            } else {
                Write-Output "[-] $path does not exist."
            }
        }
    }
    catch {
        Write-Error "An error occurred while removing the $type $path. Error: $_"
    }
}


function Remove-Custom {
# Function for removing items in need of custom code.
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$name,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$cmds
    )

    try {
        Write-Output "[+] Executing commands for '$name':"
        foreach ($cmd in $cmds) {
            Write-Output "`t[+] Executing command: $cmd"
            start-process powershell -ArgumentList "-WindowStyle","Hidden","-Command",$cmd -Wait
            Write-Host "`t[+] Process completed. Moving to next."
        }
        Write-Output "[+] All commands for '$name' have been executed successfully."
    }
    catch {
        Write-Error "An error occurred while executing commands for '$name'. Error: $_"
    }
}

# WORKER MAIN
function Set-Configuration {
    param(
        [Parameter(Position = 0)]
        [string]$configFile = (Join-Path -Path $PSScriptRoot -ChildPath "debloatConfig.xml")
    )

    try {
        # Load and parse the XML config file
        $config = [xml](Get-Content $configFile)

        # Process the apps
        if ($config.config.apps.app) {
            $config.config.apps.app | ForEach-Object {
                $appName = $_.name
                Remove-App -appName $appName
            }
        }


        # Process the services
        if ($config.config.services.service) {
            $config.config.services.service | ForEach-Object {
                $serviceName = $_.name
                Remove-Service -serviceName $serviceName
            }
        }

        # Process the services
        if ($config.config.tasks.task) {
            $config.config.tasks.task | ForEach-Object {
                $descName = $_.name
                $taskName = $_.value
                Delete-Task -name $descName -value $taskName
            }
        }

        # Process the registry items
        if ($config.config."registry-items"."registry-item") {
            $config.config."registry-items"."registry-item" | ForEach-Object {
                $name = $_.name
                $path = $_.path
                $value = $_.value
                $type = $_.type
                $data = $_.data
                Remove-RegistryValue -name $name -path $path -value $value -type $type -data $data
            }
        }

        # Process the path items
        if ($config.config."path-items"."path-item") {
            $config.config."path-items"."path-item" | ForEach-Object {
                $name = $_.name
                $type = $_.type
                $path = $_.path
                Remove-Path -name $name -type $type -path $path
            }
        }

        # Process the custom items
        if ($config.config."custom-items"."custom-item") {
            $config.config."custom-items"."custom-item" | ForEach-Object {
                $name = $_.name
                $cmds = @($_.cmd | ForEach-Object { $_.value })
                Remove-Custom -name $name -cmds $cmds
            }
        }

        if (!$global:helpersExecuted) {
            # TODO Needs to not run twice -- maybe global variable (?) but thats ugly
            # Unpinning all Start Tiles
            Write-Output "[+] Unpinning all Start Menu Tiles."
            $key = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount\*start.tilegrid`$windows.data.curatedtilecollection.tilecollection\Current"
            $data = $key.Data[0..25] + ([byte[]](202,50,0,226,44,1,1,0,0))
            Set-ItemProperty -Path $key.PSPath -Name "Data" -Type Binary -Value $data
            Stop-Process -Name "ShellExperienceHost" -Force -ErrorAction SilentlyContinue

            # Set the flag to indicate the operation has been executed
            $global:helpersExecuted = $true
        }
    }
    catch {
        Write-Error "An error occurred while applying config. Error: $_"
    }
}
