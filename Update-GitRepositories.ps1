<#
MIT License

Copyright (c) 2025 Matan Shitrit (0xMegaByte)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

<#
.SYNOPSIS
    Updates multiple Git repositories from a list stored in a configuration file.

.DESCRIPTION
    This script accepts a root directory path containing multiple Git repositories and
    updates each repository according to a list stored in a configuration file.
    It can update the master or main branch of each repository, handle errors gracefully,
    and provides summary logging of operations performed.
    
    The script can run in interactive mode (-Interactive switch) providing a menu-driven interface.

.PARAMETER RootDir
    The root directory containing the Git repositories.

.PARAMETER UpdateRepos
    Switch to update the repository list in the configuration file.

.PARAMETER NewRepos
    Array of repository names to add or replace in the configuration.

.PARAMETER AppendRepos
    Switch to append the new repositories to the existing list instead of replacing it.

.PARAMETER ConfigPath
    Optional custom path for the configuration file. Default is "$env:USERPROFILE\repos.json".

.PARAMETER Interactive
    Switch to run the script in interactive mode with a menu-driven interface.

.EXAMPLE
    .\Update-GitRepositories.ps1 -RootDir "C:\GitProjects"

.EXAMPLE
    .\Update-GitRepositories.ps1 -RootDir "C:\GitProjects" -UpdateRepos -NewRepos "repo1","repo2","repo3"

.EXAMPLE
    .\Update-GitRepositories.ps1 -RootDir "C:\GitProjects" -UpdateRepos -NewRepos "repo4" -AppendRepos

.EXAMPLE
    .\Update-GitRepositories.ps1 -Interactive

#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$RootDir,

    [Parameter(Mandatory = $false)]
    [switch]$UpdateRepos,

    [Parameter(Mandatory = $false)]
    [string[]]$NewRepos,

    [Parameter(Mandatory = $false)]
    [switch]$AppendRepos,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$env:USERPROFILE\repos.json",
    
    [Parameter(Mandatory = $false)]
    [switch]$Interactive
)

# Initialize variables for tracking operations and errors
$operations = @()
$errors = @()
$successCount = 0
$errorCount = 0

# Function to write log messages with timestamp
function Write-Log {
    param (
        [string]$Message,
        [string]$Type = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Type] $Message"
    
    # Add to operations log
    $operations += "[$timestamp] [$Type] $Message"
}

# Function to record errors
function Write-Error-Log {
    param (
        [string]$Message,
        [string]$RepoName = ""
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red
    
    # Add to operations and errors log
    $script:operations += "[$timestamp] [ERROR] $Message"
    $script:errors += "[$timestamp] [ERROR] $($RepoName): $Message"
    $script:errorCount++
}

# Function to load repositories from configuration file
function Get-RepositoryList {
    param (
        [string]$ConfigFilePath
    )
    
    try {
        if (Test-Path -Path $ConfigFilePath) {
            $config = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json -ErrorAction Stop
            
            # Check if config has Repositories property
            if (-not (Get-Member -InputObject $config -Name "Repositories" -MemberType Properties)) {
                Write-Log "Configuration file is missing the 'Repositories' property."
                $config | Add-Member -MemberType NoteProperty -Name "Repositories" -Value @()
                $config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFilePath -Force
                Write-Log "Fixed configuration file by adding empty 'Repositories' property."
            }
            
            # Check if config has RootDirectory property
            if (-not (Get-Member -InputObject $config -Name "RootDirectory" -MemberType Properties)) {
                Write-Log "Configuration file is missing the 'RootDirectory' property."
                $config | Add-Member -MemberType NoteProperty -Name "RootDirectory" -Value ""
                $config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFilePath -Force
                Write-Log "Fixed configuration file by adding 'RootDirectory' property."
            }
            
            # Check if config has Branches property
            if (-not (Get-Member -InputObject $config -Name "Branches" -MemberType Properties)) {
                Write-Log "Configuration file is missing the 'Branches' property."
                $config | Add-Member -MemberType NoteProperty -Name "Branches" -Value @("master", "main")
                $config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFilePath -Force
                Write-Log "Fixed configuration file by adding default 'Branches' property."
            }
            
            return $config
        }
        else {
            Write-Log "Configuration file not found. Creating a new one."
            
            # Create the configuration file with an empty array and no root directory
            $initialConfig = @{
                Repositories = @()
                RootDirectory = ""
                Branches = @("master", "main")
            }
            
            $initialConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFilePath -Force
            Write-Log "Created configuration file with empty repository list."
            
            return $initialConfig
        }
    }
    catch {
        Write-Error-Log "Failed to load configuration file: $_"
        return @{
            Repositories = @()
            RootDirectory = ""
            Branches = @("master", "main")
        }
    }
}

# Function to save repositories to configuration file
function Save-RepositoryList {
    param (
        [string]$ConfigFilePath,
        [array]$Repositories,
        [string]$RootDirectory,
        [array]$Branches
    )
    
    try {
        $config = @{
            Repositories = $Repositories
            RootDirectory = $RootDirectory
            Branches = $Branches
        }
        
        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFilePath -Force
        Write-Log "Updated configuration file successfully."
        return $true
    }
    catch {
        Write-Error-Log "Failed to update configuration file: $_"
        return $false
    }
}

# Function to update Git repositories
function Update-GitRepositories {
    param (
        [string]$RootDirectory,
        [array]$Repositories,
        [string]$Branch
    )
    
    # Reset counters
    $script:successCount = 0
    $script:errorCount = 0
    $script:errors = @()
    
    # Ensure RootDir ends with a backslash
    if (-not $RootDirectory.EndsWith('\')) {
        $RootDirectory += '\'
    }
    
    # Check if RootDir exists
    if (-not (Test-Path -Path $RootDirectory -PathType Container)) {
        Write-Error-Log "Root directory '$RootDirectory' does not exist."
        return
    }
    
    Write-Log "Using root directory: $RootDirectory"
    
    if ($Repositories.Count -eq 0) {
        Write-Log "No repositories found in configuration file." -Type "WARN"
        return
    }
    else {
        Write-Log "Processing $($Repositories.Count) repositories."
    }
    
    # Process each repository
    foreach ($repo in $Repositories) {
        Write-Host ("`n" + ('=' * 60)) -ForegroundColor Cyan
        Write-Host "PROCESSING REPOSITORY: " -NoNewline -ForegroundColor White
        Write-Host "$repo" -ForegroundColor Yellow -BackgroundColor DarkBlue
        Write-Host ("`n" + ('=' * 60)) -ForegroundColor Cyan
        
        $repoPath = Join-Path -Path $RootDirectory -ChildPath $repo
        
        # Check if repository directory exists
        if (-not (Test-Path -Path $repoPath -PathType Container)) {
            Write-Host "Repository directory does not exist: $repoPath" -ForegroundColor Red
            Write-Error-Log "Repository directory does not exist: $repoPath" -RepoName $repo
            continue
        }
        
        # Check if it's a valid Git repository
        $gitDirPath = Join-Path -Path $repoPath -ChildPath ".git"
        if (-not (Test-Path -Path $gitDirPath -PathType Container)) {
            Write-Host "Not a valid Git repository (missing .git directory): $repoPath" -ForegroundColor Red
            Write-Error-Log "Not a valid Git repository (missing .git directory): $repoPath" -RepoName $repo
            continue
        }
        
        # Change to repository directory
        try {
            Push-Location $repoPath
            
            # Get current branch
            $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
            Write-Host "Directory: " -NoNewline -ForegroundColor Green
            Write-Host "$repoPath" -ForegroundColor White
            Write-Host "Current branch: " -NoNewline -ForegroundColor Green
            Write-Host "$currentBranch" -ForegroundColor White
            
            # Check for available branches
            $branches = git branch --list 2>$null
            $hasMaster = $branches -match "\s+master$"
            $hasMain = $branches -match "\s+main$"
            
            # Determine which branch to use
            $branchToUse = $null
            if ($hasMaster) {
                $branchToUse = "master"
            }
            elseif ($hasMain) {
                $branchToUse = "main"
            }
            
            if ($null -eq $branchToUse) {
                Write-Host "Neither 'master' nor 'main' branch found." -ForegroundColor Red
                Write-Error-Log "Neither 'master' nor 'main' branch found." -RepoName $repo
                Pop-Location
                continue
            }
            
            # Checkout appropriate branch
            if ($currentBranch -ne $branchToUse) {
                Write-Host "Checking out $branchToUse branch..." -ForegroundColor Cyan
                $checkoutOutput = git checkout $branchToUse 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "Failed to checkout $branchToUse branch: $checkoutOutput" -ForegroundColor Red
                    Write-Error-Log "Failed to checkout $branchToUse branch: $checkoutOutput" -RepoName $repo
                    Pop-Location
                    continue
                }
                Write-Host "Checked out $branchToUse branch." -ForegroundColor Green
            }
            else {
                Write-Host "Already on $branchToUse branch." -ForegroundColor Green
            }
            
            # Pull latest changes
            Write-Host "Pulling latest changes..." -ForegroundColor Cyan
            $pullOutput = git pull 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Failed to pull changes: $pullOutput" -ForegroundColor Red
                Write-Error-Log "Failed to pull changes: $pullOutput" -RepoName $repo
                Pop-Location
                continue
            }
            
            Write-Host "Successfully updated repository: $repo" -ForegroundColor Green
            $script:successCount++
            
            # Return to original directory
            Pop-Location
        }
        catch {
            Write-Host "Error processing repository: $_" -ForegroundColor Red
            Write-Error-Log "Error processing repository: $_" -RepoName $repo
            
            # Ensure we return to the original directory
            if ((Get-Location).Path -eq $repoPath) {
                Pop-Location
            }
        }
    }
    # Generate summary
    Write-Host ("`n" + ('=' * 60)) -ForegroundColor Magenta
    Write-Host "SUMMARY" -ForegroundColor Magenta
    Write-Host ('=' * 60) -ForegroundColor Magenta
    Write-Host "Repositories processed: " -NoNewline -ForegroundColor Cyan
    Write-Host "$($Repositories.Count)" -ForegroundColor White
    Write-Host "Successful updates: " -NoNewline -ForegroundColor Green
    Write-Host "$script:successCount" -ForegroundColor White
    Write-Host "Errors encountered: " -NoNewline -ForegroundColor $(if ($script:errorCount -gt 0) { "Red" } else { "Green" })
    Write-Host "$script:errorCount" -ForegroundColor White
    # Display errors if any
    if ($script:errors.Count -gt 0) {
        Write-Host ("`n" + ('=' * 60)) -ForegroundColor Red
        Write-Host "ERROR DETAILS" -ForegroundColor Red
        Write-Host ('=' * 60) -ForegroundColor Red
        foreach ($err in $script:errors) {
            Write-Host $err -ForegroundColor Red
        }
    }
    Write-Host "`nOperation completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
}

# Function to display interactive menu
function Show-InteractiveMenu {
    param (
        [string]$CurrentRootDir,
        [array]$CurrentRepos,
        [array]$CurrentBranches
    )
    $menuOptions = @(
        "Set Root Directory",
        "View Repository List",
        "Add Repository",
        "Remove Repository",
        "Update All Repositories",
        "Manage Branches",
        "Exit"
    )
    $selected = 0
    while ($true) {
        Clear-Host
        Write-Host "===============================================" -ForegroundColor DarkCyan
        Write-Host "           GIT REPOSITORY MANAGER" -ForegroundColor Yellow
        Write-Host "===============================================" -ForegroundColor DarkCyan
        Write-Host
        Write-Host ("Root Directory: ".PadRight(20)) -NoNewline
        if ([string]::IsNullOrEmpty($CurrentRootDir)) {
            Write-Host "[ Not set ]" -ForegroundColor Red
        } else {
            Write-Host $CurrentRootDir -ForegroundColor Green
        }
        Write-Host ("Repositories: ".PadRight(20)) -NoNewline
        if ($CurrentRepos.Count -eq 0) {
            Write-Host "[ None configured ]" -ForegroundColor Red
        } else {
            Write-Host "$($CurrentRepos.Count) configured" -ForegroundColor Green
        }
        Write-Host ("Branches: ".PadRight(20)) -NoNewline
        if ($CurrentBranches.Count -eq 0) {
            Write-Host "[ None ]" -ForegroundColor Red
        } else {
            Write-Host ($CurrentBranches -join ", ") -ForegroundColor Green
        }
        Write-Host "-----------------------------------------------" -ForegroundColor DarkGray
        Write-Host " MENU OPTIONS:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $menuOptions.Count; $i++) {
            if ($i -eq $selected) {
                Write-Host ("  > " + ($i+1) + ". " + $menuOptions[$i]) -ForegroundColor Black -BackgroundColor Yellow
            } else {
                Write-Host ("    " + ($i+1) + ". " + $menuOptions[$i]) -ForegroundColor White
            }
        }
        Write-Host "-----------------------------------------------" -ForegroundColor DarkGray
        Write-Host "Use Up/Down arrows to navigate, Enter to select, Backspace to go back."
        $key = $null
        $key = [System.Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { if ($selected -gt 0) { $selected-- } }
            'DownArrow' { if ($selected -lt ($menuOptions.Count-1)) { $selected++ } }
            'Enter'     { return ($selected+1).ToString() }
            'Backspace' { return 'BACK' }
        }
    }
}

function Manage-BranchesInteractive {
    param (
        [string]$ConfigFilePath,
        [array]$CurrentBranches
    )
    $branches = $CurrentBranches
    $menuOptions = @("Add Branch", "Remove Branch", "Back to Main Menu")
    $selected = 0
    while ($true) {
        Clear-Host
        Write-Host "===== Manage Branches =====" -ForegroundColor Yellow
        Write-Host "Current Branches:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $branches.Count; $i++) {
            Write-Host "$($i + 1). $($branches[$i])" -ForegroundColor Green
        }
        Write-Host "-----------------------------------------------" -ForegroundColor DarkGray
        Write-Host " MENU OPTIONS:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $menuOptions.Count; $i++) {
            if ($i -eq $selected) {
                Write-Host ("  > " + ($i+1) + ". " + $menuOptions[$i]) -ForegroundColor Black -BackgroundColor Yellow
            } else {
                Write-Host ("    " + ($i+1) + ". " + $menuOptions[$i]) -ForegroundColor White
            }
        }
        Write-Host "-----------------------------------------------" -ForegroundColor DarkGray
        Write-Host "Use Up/Down arrows to navigate, Enter to select, Backspace to go back."
        $key = [System.Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { if ($selected -gt 0) { $selected-- } }
            'DownArrow' { if ($selected -lt ($menuOptions.Count-1)) { $selected++ } }
            'Enter' {
                switch ($selected) {
                    0 { # Add Branch
                        $newBranch = Read-Host -Prompt "Enter branch name to add"
                        if (-not [string]::IsNullOrEmpty($newBranch) -and ($branches -notcontains $newBranch)) {
                            $branches += $newBranch
                            Save-RepositoryList -ConfigFilePath $ConfigFilePath -Repositories $null -RootDirectory $null -Branches $branches
                            Write-Host "Branch '$newBranch' added." -ForegroundColor Green
                        } else {
                            Write-Host "Invalid or duplicate branch name." -ForegroundColor Red
                        }
                        Read-Host "Press Enter to continue"
                    }
                    1 { # Remove Branch
                        if ($branches.Count -eq 0) {
                            Write-Host "No branches to remove." -ForegroundColor Red
                            Read-Host "Press Enter to continue"
                        } else {
                            $removeSelected = 0
                            while ($true) {
                                Clear-Host
                                Write-Host "Select a branch to remove (Backspace to cancel):" -ForegroundColor Yellow
                                for ($j = 0; $j -lt $branches.Count; $j++) {
                                    if ($j -eq $removeSelected) {
                                        Write-Host ("  > " + ($j+1) + ". " + $branches[$j]) -ForegroundColor Black -BackgroundColor Yellow
                                    } else {
                                        Write-Host ("    " + ($j+1) + ". " + $branches[$j]) -ForegroundColor White
                                    }
                                }
                                $rkey = [System.Console]::ReadKey($true)
                                switch ($rkey.Key) {
                                    'UpArrow'   { if ($removeSelected -gt 0) { $removeSelected-- } }
                                    'DownArrow' { if ($removeSelected -lt ($branches.Count-1)) { $removeSelected++ } }
                                    'Enter' {
                                        $branchToRemove = $branches[$removeSelected]
                                        $branches = $branches | Where-Object { $_ -ne $branchToRemove }
                                        Save-RepositoryList -ConfigFilePath $ConfigFilePath -Repositories $null -RootDirectory $null -Branches $branches
                                        Write-Host "Branch '$branchToRemove' removed." -ForegroundColor Green
                                        Read-Host "Press Enter to continue"
                                        break
                                    }
                                    'Backspace' { break }
                                }
                                if ($rkey.Key -eq 'Enter' -or $rkey.Key -eq 'Backspace') { break }
                            }
                        }
                    }
                    2 { return $branches }
                }
            }
            'Backspace' { return $branches }
        }
    }
}

function Select-BranchInteractive {
    param (
        [array]$Branches
    )
    $selected = 0
    while ($true) {
        Clear-Host
        Write-Host "Select a branch to use for update:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $Branches.Count; $i++) {
            if ($i -eq $selected) {
                Write-Host ("  > " + ($i+1) + ". " + $Branches[$i]) -ForegroundColor Black -BackgroundColor Yellow
            } else {
                Write-Host ("    " + ($i+1) + ". " + $Branches[$i]) -ForegroundColor White
            }
        }
        Write-Host "-----------------------------------------------" -ForegroundColor DarkGray
        Write-Host "Use Up/Down arrows to navigate, Enter to select, Backspace to cancel."
        $key = [System.Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { if ($selected -gt 0) { $selected-- } }
            'DownArrow' { if ($selected -lt ($Branches.Count-1)) { $selected++ } }
            'Enter'     { return $Branches[$selected] }
            'Backspace' { return $Branches[0] }
        }
    }
}

# Function to set root directory interactively
function Set-RootDirectoryInteractive {
    $directory = Read-Host -Prompt "Enter the root directory path"
    
    if ([string]::IsNullOrEmpty($directory)) {
        Write-Host "Directory path cannot be empty." -ForegroundColor Red
        return $null
    }
    
    if (-not (Test-Path -Path $directory -PathType Container)) {
        Write-Host "Directory does not exist. Would you like to create it? (Y/N)" -ForegroundColor Yellow
        $createChoice = Read-Host
        
        if ($createChoice -eq "Y" -or $createChoice -eq "y") {
            try {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
                Write-Host "Directory created successfully." -ForegroundColor Green
            } catch {
                Write-Host "Failed to create directory: $_" -ForegroundColor Red
                return $null
            }
        } else {
            return $null
        }
    }
    
    return $directory
}

# Function to run interactive mode
function Start-InteractiveMode {
    param (
        [string]$ConfigFilePath
    )
    
    $config = Get-RepositoryList -ConfigFilePath $ConfigFilePath
    $currentRootDir = $config.RootDirectory
    $currentRepos = $config.Repositories
    $currentBranches = $config.Branches
    
    while ($true) {
        $choice = Show-InteractiveMenu -CurrentRootDir $currentRootDir -CurrentRepos $currentRepos -CurrentBranches $currentBranches
        
        switch ($choice) {
            "1" { 
                # Set Root Directory
                $newRootDir = Set-RootDirectoryInteractive
                if ($null -ne $newRootDir) {
                    $currentRootDir = $newRootDir
                    # Save the root directory to configuration
                    Save-RepositoryList -ConfigFilePath $ConfigFilePath -Repositories $currentRepos -RootDirectory $currentRootDir -Branches $currentBranches
                    Write-Host "Root directory set to: $currentRootDir" -ForegroundColor Green
                    Write-Host "Root directory saved to configuration file." -ForegroundColor Green
                }
                Read-Host "Press Enter to continue"
            }
            
            "2" { 
                # View Repository List
                Clear-Host
                Write-Host "===== Repository List =====" -ForegroundColor Yellow
                if ($currentRepos.Count -eq 0) {
                    Write-Host "No repositories configured." -ForegroundColor Red
                } else {
                    for ($i = 0; $i -lt $currentRepos.Count; $i++) {
                        Write-Host "$($i + 1). $($currentRepos[$i])" -ForegroundColor Cyan
                    }
                }
                Read-Host "Press Enter to continue"
            }
            
            "3" { 
                # Add Repository
                $newRepo = Read-Host -Prompt "Enter repository name to add"
                if (-not [string]::IsNullOrEmpty($newRepo)) {
                    # Ensure $currentRepos is an array to properly handle additions
                    if ($null -eq $currentRepos) {
                        $currentRepos = @()
                    }
                    elseif ($currentRepos -isnot [Array]) {
                        $currentRepos = @($currentRepos)
                    }
                    
                    if ($currentRepos -notcontains $newRepo) {
                        # Add the new repository as a separate entry
                        $currentRepos = @($currentRepos) + @($newRepo)
                        Save-RepositoryList -ConfigFilePath $ConfigFilePath -Repositories $currentRepos -RootDirectory $currentRootDir -Branches $currentBranches
                        Write-Host "Repository '$newRepo' added successfully." -ForegroundColor Green
                        
                        # Reload repositories from configuration to apply changes to current session
                        $config = Get-RepositoryList -ConfigFilePath $ConfigFilePath
                        $currentRepos = $config.Repositories
                        Write-Host "Repository list reloaded from configuration." -ForegroundColor Green
                    } else {
                        Write-Host "Repository '$newRepo' already exists in the list." -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "Repository name cannot be empty." -ForegroundColor Red
                }
                Read-Host "Press Enter to continue"
            }
            
            "4" { 
                # Remove Repository
                Clear-Host
                Write-Host "===== Remove Repository =====" -ForegroundColor Yellow
                if ($currentRepos.Count -eq 0) {
                    Write-Host "No repositories configured to remove." -ForegroundColor Red
                } else {
                    for ($i = 0; $i -lt $currentRepos.Count; $i++) {
                        Write-Host "$($i + 1). $($currentRepos[$i])" -ForegroundColor Cyan
                    }
                    
                    $removeIndex = Read-Host -Prompt "Enter the number of the repository to remove (or 'C' to cancel)"
                    
                    if ($removeIndex -ne "C" -and $removeIndex -ne "c") {
                        try {
                            $index = [int]$removeIndex - 1
                            if ($index -ge 0 -and $index -lt $currentRepos.Count) {
                                $repoToRemove = $currentRepos[$index]
                                $currentRepos = $currentRepos | Where-Object { $_ -ne $repoToRemove }
                                Save-RepositoryList -ConfigFilePath $ConfigFilePath -Repositories $currentRepos -RootDirectory $currentRootDir -Branches $currentBranches
                                Write-Host "Repository '$repoToRemove' removed successfully." -ForegroundColor Green
                            } else {
                                Write-Host "Invalid selection." -ForegroundColor Red
                            }
                        } catch {
                            Write-Host "Invalid input. Please enter a number." -ForegroundColor Red
                        }
                    }
                }
                Read-Host "Press Enter to continue"
            }
            
            "5" { 
                # Update All Repositories
                if ([string]::IsNullOrEmpty($currentRootDir)) {
                    Write-Host "Please set a root directory first." -ForegroundColor Red
                } elseif ($currentRepos.Count -eq 0) {
                    Write-Host "No repositories configured to update." -ForegroundColor Red
                } else {
                    $selectedBranch = Select-BranchInteractive -Branches $currentBranches
                    Clear-Host
                    Write-Host "===== Updating Repositories =====" -ForegroundColor Yellow
                    Update-GitRepositories -RootDirectory $currentRootDir -Repositories $currentRepos -Branch $selectedBranch
                }
                Read-Host "Press Enter to continue"
            }
            
            "6" {
                $currentBranches = Manage-BranchesInteractive -ConfigFilePath $ConfigFilePath -CurrentBranches $currentBranches
                # Reload config to keep in sync
                $config = Get-RepositoryList -ConfigFilePath $ConfigFilePath
                $currentBranches = $config.Branches
            }
            
            "7" { 
                # Exit
                return
            }
            
            default {
                Write-Host "Invalid choice. Please enter a number between 1 and 7." -ForegroundColor Red
                Read-Host "Press Enter to continue"
            }
        }
    }
}

# Main script execution logic
if ($Interactive) {
    # Run in interactive mode
    Start-InteractiveMode -ConfigFilePath $ConfigPath
} else {
    # Run in command line mode
    # Load configuration to get stored root directory if needed
    $config = Get-RepositoryList -ConfigFilePath $ConfigPath
    
    # Use root directory from parameter if provided, otherwise use from config
    if ([string]::IsNullOrEmpty($RootDir)) {
        # Check if we have a root directory in config
        if ([string]::IsNullOrEmpty($config.RootDirectory)) {
            Write-Error-Log "Root directory parameter (-RootDir) is required in non-interactive mode and no saved root directory exists in configuration."
            exit 1
        } else {
            $RootDir = $config.RootDirectory
            Write-Log "Using root directory from configuration file: $RootDir"
        }
    } else {
        # Save the provided root directory to configuration for future use
        Save-RepositoryList -ConfigFilePath $ConfigPath -Repositories $config.Repositories -RootDirectory $RootDir -Branches $config.Branches
        Write-Log "Updated root directory in configuration file."
    }
    
    # Ensure RootDir ends with a backslash
    if (-not $RootDir.EndsWith('\')) {
        $RootDir += '\'
    }
    
    # Check if RootDir exists
    if (-not (Test-Path -Path $RootDir -PathType Container)) {
        Write-Error-Log "Root directory '$RootDir' does not exist."
        exit 1
    }
    
    # Process repositories
    Update-GitRepositories -RootDirectory $RootDir -Repositories $config.Repositories -Branch $config.Branches[0]
}

