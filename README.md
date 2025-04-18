# Repo Updater

![Windows](https://img.shields.io/badge/OS-Windows-blue?logo=windows) ![Created with Vibe Coding](https://img.shields.io/badge/Created%20with-Vibe%20Coding-9cf)

Repo Updater is a PowerShell utility for managing and updating multiple Git repositories from a single root directory. It supports both command-line and interactive menu-driven modes, making it easy to keep your projects up to date.

## Features
- Batch update multiple Git repositories with a single command
- Interactive mode for easy setup and management
- Customizable list of repositories and branches
- Configuration file for persistent settings
- Summary logging and error reporting

## Setup
1. **Clone or Download** this repository to your local machine.
2. **Ensure you have:**
   - PowerShell (Windows comes with PowerShell pre-installed)
   - Git installed and available in your system's PATH

## Configuration
Repo Updater uses a configuration file (default: `%USERPROFILE%\repos.json`) to store:
- The root directory path
- The list of repositories (by folder name)
- The list of branches to manage (default: `master`, `main`)

You can specify a custom config file with the `-ConfigPath` parameter.

## Usage
### Interactive Mode
Run the script with the `-Interactive` switch for a menu-driven interface:

```powershell
.\Update-GitRepositories.ps1 -Interactive
```

**Interactive Mode Features:**
- **Set Root Directory:** Easily set or change the root folder containing your repositories. The script will prompt you to create the directory if it does not exist.
- **View Repository List:** Display all currently managed repositories.
- **Add Repository:** Add a new repository by entering its folder name (must exist under the root directory).
- **Remove Repository:** Remove a repository from the list by selecting it from a numbered menu.
- **Update All Repositories:** Select a branch and update all repositories in the list. The script will show progress and a summary of successes and errors.
- **Manage Branches:** Add or remove branch names to be managed. You can select branches to update in the update step.
- **Menu Navigation:** Use the Up/Down arrow keys to navigate, Enter to select, and Backspace to go back or cancel certain actions.
- **Configuration Persistence:** All changes are saved to the configuration file, so your settings persist between runs.

### Command-Line Mode
You can also use the script directly with parameters:

- **Set/Update Root Directory:**
  ```powershell
  .\Update-GitRepositories.ps1 -RootDir "C:\GitProjects"
  ```
- **Update the repository list:**
  ```powershell
  .\Update-GitRepositories.ps1 -RootDir "C:\GitProjects" -UpdateRepos -NewRepos "repo1","repo2"
  ```
- **Append a repository to the list:**
  ```powershell
  .\Update-GitRepositories.ps1 -RootDir "C:\GitProjects" -UpdateRepos -NewRepos "repo3" -AppendRepos
  ```
- **Specify a custom config file:**
  ```powershell
  .\Update-GitRepositories.ps1 -ConfigPath "C:\path\to\myconfig.json" -Interactive
  ```

## How It Works
- The script reads the configuration file for the root directory, repositories, and branches.
- For each repository, it checks out the specified branch (default: `master` or `main`) and pulls the latest changes.
- You can manage the list of repositories and branches either interactively or via command-line parameters.

## Tips
- Repository names are folder names under the root directory.
- Branches can be managed interactively or by editing the config file.
- The script will create the config file if it does not exist.
- All operations and errors are logged to the console for review.

## Example Configuration File (`repos.json`)
```json
{
  "Repositories": ["repo1", "repo2"],
  "RootDirectory": "C:\\GitProjects",
  "Branches": ["master", "main"]
}
```

## License
This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
