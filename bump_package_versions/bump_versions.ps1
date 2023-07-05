# Functionality

function Get-Projs {
    param (
        [string]$folderPath
    )
    
    return Get-ChildItem -Path $folderPath -Filter "*.csproj" -Recurse | Select-Object -ExpandProperty FullName
}

function Get-PackageReferences {
    param (
        [string]$filePath
    )
    
    $content = Get-Content -Path $filePath
    $object = [xml]$content
    
    $packageReferences = $object.SelectNodes("//PackageReference")
    
    $result = foreach ($reference in $packageReferences) {
        $include = $reference.GetAttribute("Include")
        $version = $reference.GetAttribute("Version")
        
        [PSCustomObject]@{
            Include = $include
            Version = $version
        }
    }
    
    return $result
}

function Get-TargetPackageReferences {
    $filePath = "package_references.json"
    
    if (-not (Test-Path $filePath)) {
        Write-Host "Package references file not found: $filePath"
        return
    }
    
    $content = Get-Content -Path $filePath -Raw
    $references = $content | ConvertFrom-Json

    return $references.packages
}

function Get-TargetVersion {
    param (
        [string]$include
    )
    
    $references = Get-TargetPackageReferences
    
    if (-not $references) {
        Write-Host "Package references not available."

        return
    }
    
    $matchingReference = $references | Where-Object { $_.Include -eq $include }
    
    if ($matchingReference) {
        return $matchingReference.Version
    }
}

function Set-PackageReferenceVersion {
    param (
        [string]$filePath,
        [string]$include,
        [string]$targetVersion
    )

    $xml = [xml](Get-Content -Path $filePath)
    $packageReferenceNode = $xml.SelectSingleNode("//PackageReference[@Include='$include']")

    if ($packageReferenceNode) {
        $packageReferenceNode.SetAttribute("Version", $targetVersion)
        $xml.Save($filePath)

        Write-Host "PackageReference '$include' in '$filePath' updated to version '$targetVersion'."
    }
    else {
        Write-Host "PackageReference with Include '$include' not found in '$filePath'."
    }
}

# Logic

Start-Transcript -Path "$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

$paths = Get-Projs -folderPath $PSScriptRoot

if ($paths.Length -gt 0) {
    Write-Output ("{0} project files found." -f $paths.Length)
} 
else {
    Write-Output "No project files found."

    return
}

foreach ($path in $paths) {
    Write-Output ("`n{0}:" -f (Get-Item -Path $path).BaseName)
    
    $references = Get-PackageReferences -filePath $path

    foreach ($reference in $references) {
        Write-Output ("`t{0} [{1}]" -f $reference.Include, $reference.Version)

        $targetVersion = Get-TargetVersion -include $reference.Include

        if ($targetVersion -and $reference.Version -ne $targetVersion) {
            Write-Output ("`t`tVersion mismatch found [{0}] ~= [{1}] - proceeding with update.." -f $targetVersion, $reference.Version)

            Set-PackageReferenceVersion -filePath $path -include $reference.Include -targetVersion $targetVersion
        } 
    }
}