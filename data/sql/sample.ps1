Clear-Host
write-host "Starting script at $(Get-Date)"

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name Az.Synapse -Force

# Prompt user for a password for the SQL Database
$sqlUser = "asa.sql.admin"

$sqlPasswordSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "SqlPassword"
$sqlPassword = '';
$ssPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sqlPasswordSecret.SecretValue)
try {
    $sqlPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr)
} finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
}
$global:sqlPassword = $sqlPassword

$suffix = (Get-AzResourceGroup -Name $resourceGroupName).Tags["DeploymentId"]
$resourceGroupName = "data-engineering-synapse-$suffix"
$synapseWorkspace = "asaworkspace$suffix"
$dataLakeAccountName = "asadatalake$suffix"
$sqlDatabaseName = "SQLPool01"

# Create database
write-host "Creating the $sqlDatabaseName database..."
sqlcmd -S "$synapseWorkspace.sql.azuresynapse.net" -U $sqlUser -P $sqlPassword -d $sqlDatabaseName -I -i setup.sql

# Load data
write-host "Loading data..."
Get-ChildItem "./data/*.txt" -File | Foreach-Object {
    write-host ""
    $file = $_.FullName
    Write-Host "$file"
    $table = $_.Name.Replace(".txt","")
    bcp dbo.$table in $file -S "$synapseWorkspace.sql.azuresynapse.net" -U $sqlUser -P $sqlPassword -d $sqlDatabaseName -f $file.Replace("txt", "fmt") -q -k -E -b 5000
}

# Pause SQL Pool
# write-host "Pausing the $sqlDatabaseName SQL Pool..."
# Suspend-AzSynapseSqlPool -WorkspaceName $synapseWorkspace -Name $sqlDatabaseName -AsJob

# Upload solution script
write-host "Uploading script..."
$solutionScriptPath = "Solution.sql"
Set-AzSynapseSqlScript -WorkspaceName $synapseWorkspace -DefinitionFile $solutionScriptPath -sqlPoolName $sqlDatabaseName -sqlDatabaseName $sqlDatabaseName

write-host "Script completed at $(Get-Date)"