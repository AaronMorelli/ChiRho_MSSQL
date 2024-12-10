# InstallationArtifacts

The Powershell script `generate_installation_artifacts.ps1` places its output in this directory. These generated .sql files contain the actual DDL that will be run during the installation process. They contain the same contents as the various files in the `Code\` directory, with 2 exceptions:

- All tokens (such as `@@CHIRHO_SCHEMA@@` have been resolved to their true runtime values)
- The many files under `Code\` have been collapsed down into just a few large .sql files that will be run, either by the installer, or manually (when a TempDB install is done)