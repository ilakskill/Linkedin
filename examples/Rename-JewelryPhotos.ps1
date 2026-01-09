[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path,

    [string]$ApiKey,

    [switch]$Recurse,

    [switch]$Apply,

    [int]$DelayMs = 0,

    [string]$LogPath = (Join-Path (Get-Location) "rename-plan.csv"),

    [string]$ErrorLogPath = (Join-Path (Get-Location) "rename-errors.csv"),

    [switch]$ListModels,

    [string]$Model = "gemini-2.0-flash-lite",

    [ValidateSet("auto", "v1", "v1beta")]
    [string]$ApiVersion = "auto",

    [int]$Limit = 0,

    [string]$ExifToolPath = "exiftool",

    [switch]$WriteMetadata
)

$ErrorActionPreference = "Stop"

$script:Categories = @("Ring", "Bracelet", "Necklace", "Earrings", "Anklet", "Brooch", "Watch", "Other")
$script:CategoryMap = @{
    "ring"      = "Ring"
    "rings"     = "Ring"
    "bracelet"  = "Bracelet"
    "bracelets" = "Bracelet"
    "necklace"  = "Necklace"
    "necklaces" = "Necklace"
    "earring"   = "Earrings"
    "earrings"  = "Earrings"
    "anklet"    = "Anklet"
    "anklets"   = "Anklet"
    "brooch"    = "Brooch"
    "brooches"  = "Brooch"
    "watch"     = "Watch"
    "watches"   = "Watch"
    "other"     = "Other"
}

function Ensure-ParentDirectory {
    param([Parameter(Mandatory)] [string]$FilePath)
    $parent = Split-Path -Parent $FilePath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
}

function Write-CsvRow {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [object]$Row
    )
    Ensure-ParentDirectory -FilePath $FilePath
    $Row | Export-Csv -LiteralPath $FilePath -Append -NoTypeInformation
}

function Get-MimeType {
    param([Parameter(Mandatory)] [string]$Extension)
    switch ($Extension.ToLowerInvariant()) {
        ".jpg" { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".png" { "image/png" }
        ".webp" { "image/webp" }
        ".gif" { "image/gif" }
        ".bmp" { "image/bmp" }
        ".tif" { "image/tiff" }
        ".tiff" { "image/tiff" }
        ".heic" { "image/heic" }
        ".heif" { "image/heif" }
        ".avif" { "image/avif" }
        default { "application/octet-stream" }
    }
}

function Get-ReverseDateKey {
    param([Parameter(Mandatory)] [datetime]$DateTime)
    $stamp = $DateTime.ToString("yyyyMMddHHmmss")
    $reverse = 99991231235959 - [int64]$stamp
    return "{0:D14}" -f $reverse
}

function Normalize-Category {
    param([string]$Text)
    if (-not $Text) {
        return "Other"
    }
    $token = ($Text -split '\s+')[0]
    $token = $token.Trim().Trim(".", ",", ";", ":", "!", "?", "'", '"', "(", ")", "[", "]", "{", "}")
    $key = $token.ToLowerInvariant()
    if ($script:CategoryMap.ContainsKey($key)) {
        return $script:CategoryMap[$key]
    }
    return "Other"
}

function Get-HttpErrorDetails {
    param([Parameter(Mandatory)] [object]$ErrorRecord)

    $statusCode = $null
    $body = $null
    $message = $ErrorRecord.Exception.Message

    if ($ErrorRecord.Exception -is [System.Net.WebException]) {
        $response = $ErrorRecord.Exception.Response
        if ($response) {
            try { $statusCode = [int]$response.StatusCode } catch { }
            try {
                $stream = $response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $body = $reader.ReadToEnd()
                    $reader.Close()
                }
            } catch { }
        }
    } elseif ($ErrorRecord.Exception.PSObject.TypeNames -contains "Microsoft.PowerShell.Commands.HttpResponseException") {
        $response = $ErrorRecord.Exception.Response
        if ($response) {
            try { $statusCode = [int]$response.StatusCode } catch { }
            try { $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } catch { }
        }
    }

    return [pscustomobject]@{
        StatusCode = $statusCode
        Body       = $body
        Message    = $message
    }
}

function Invoke-GeminiRequest {
    param(
        [Parameter(Mandatory)] [string]$ApiKey,
        [Parameter(Mandatory)] [string]$Model,
        [Parameter(Mandatory)] [string]$Body,
        [Parameter(Mandatory)] [string]$ApiVersion
    )

    # Try v1beta first as it has more models available
    $versions = if ($ApiVersion -eq "auto") { @("v1beta", "v1") } else { @($ApiVersion) }
    $lastError = $null

    foreach ($version in $versions) {
        $uri = "https://generativelanguage.googleapis.com/$version/models/${Model}:generateContent?key=$ApiKey"
        Write-Verbose "Calling: $uri"
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json; charset=utf-8" -Body $Body -ErrorAction Stop
            return [pscustomobject]@{ Success = $true; Response = $response; ApiVersion = $version }
        } catch {
            $lastError = Get-HttpErrorDetails -ErrorRecord $_
            $lastError | Add-Member -NotePropertyName ApiVersion -NotePropertyValue $version -Force
            Write-Verbose "Failed with $version : $($lastError.Message)"
        }
    }

    return [pscustomobject]@{ Success = $false; Error = $lastError }
}

function Invoke-GeminiClassifyImage {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string]$ApiKey,
        [Parameter(Mandatory)] [string]$Model,
        [Parameter(Mandatory)] [string]$ApiVersion
    )

    $extension = [System.IO.Path]::GetExtension($FilePath)
    $mimeType = Get-MimeType -Extension $extension
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $data = [Convert]::ToBase64String($bytes)

    $prompt = @"
Analyze this jewelry photo and provide the following details in exactly this format:
Category: [Ring|Bracelet|Necklace|Earrings|Anklet|Brooch|Watch|Other]
Color: [primary color like Gold, Silver, Rose-Gold, White, Black, Blue, Red, Green, Multi-color, etc.]
Style: [style like Chain, Pendant, Choker, Statement, Hoop, Stud, Cuff, Bangle, Tennis, Solitaire, Cluster, etc.]
Material: [material like Gold, Sterling-Silver, Platinum, Stainless-Steel, Copper, Leather, Pearl, Diamond, Crystal, Gemstone, etc.]

Use hyphens instead of spaces within each value. Return ONLY these 4 lines, nothing else.
"@
    $body = @{
        contents = @(
            @{
                parts = @(
                    @{ text = $prompt }
                    @{ inline_data = @{ mime_type = $mimeType; data = $data } }
                )
            }
        )
    } | ConvertTo-Json -Depth 8

    $result = Invoke-GeminiRequest -ApiKey $ApiKey -Model $Model -Body $body -ApiVersion $ApiVersion
    if (-not $result.Success) {
        return [pscustomobject]@{ Success = $false; Error = $result.Error }
    }

    $raw = $result.Response.candidates[0].content.parts[0].text
    if (-not $raw) {
        return [pscustomobject]@{
            Success = $false
            Error   = [pscustomobject]@{
                StatusCode = $null
                Body       = $null
                Message    = "No text returned by model."
                ApiVersion = $result.ApiVersion
            }
        }
    }

    # Parse the response
    $category = "Other"
    $color = "Unknown"
    $style = "Unknown"
    $material = "Unknown"

    # Function to sanitize values for filenames
    function Sanitize-Value {
        param([string]$val)
        # Take only first value if comma-separated, replace spaces/special chars with hyphens
        $val = ($val -split '[,;/]')[0].Trim()
        $val = $val -replace '[<>:"/\\|?*\[\]]', ''
        $val = $val -replace '\s+', '-'
        $val = $val -replace '-+', '-'
        $val = $val.Trim('-')
        if (-not $val) { $val = "Unknown" }
        return $val
    }

    foreach ($line in ($raw -split "`n")) {
        $line = $line.Trim()
        if ($line -match "^Category:\s*(.+)$") {
            $category = Normalize-Category -Text $Matches[1].Trim()
        }
        elseif ($line -match "^Color:\s*(.+)$") {
            $color = Sanitize-Value $Matches[1]
        }
        elseif ($line -match "^Style:\s*(.+)$") {
            $style = Sanitize-Value $Matches[1]
        }
        elseif ($line -match "^Material:\s*(.+)$") {
            $material = Sanitize-Value $Matches[1]
        }
    }

    return [pscustomobject]@{
        Success    = $true
        Category   = $category
        Color      = $color
        Style      = $style
        Material   = $material
        Raw        = $raw
        ApiVersion = $result.ApiVersion
    }
}

function Get-GeminiModels {
    param(
        [Parameter(Mandatory)] [string]$ApiKey,
        [Parameter(Mandatory)] [string]$ApiVersion
    )

    $versions = if ($ApiVersion -eq "auto") { @("v1", "v1beta") } else { @($ApiVersion) }
    foreach ($version in $versions) {
        $uri = "https://generativelanguage.googleapis.com/$version/models?key=$ApiKey"
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop
            Write-Host "Models ($version):"
            $response.models | ForEach-Object { $_.name } | Sort-Object | ForEach-Object { Write-Host "  $_" }
        } catch {
            $details = Get-HttpErrorDetails -ErrorRecord $_
            Write-Warning ("Failed to list models for {0}. Status: {1}. {2}" -f $version, $details.StatusCode, $details.Message)
            if ($details.Body) {
                Write-Warning $details.Body
            }
            if ($ApiVersion -ne "auto") {
                throw
            }
        }
    }
}

function Get-UniqueTargetPath {
    param(
        [Parameter(Mandatory)] [string]$DesiredPath,
        [Parameter(Mandatory)] [string]$BaseName,
        [Parameter(Mandatory)] [string]$Extension,
        [Parameter(Mandatory)] [string]$SourcePath,
        [Parameter(Mandatory)] [hashtable]$Used
    )

    $candidate = $DesiredPath
    $suffix = 1
    while ($Used.ContainsKey($candidate.ToLower()) -or ((Test-Path -LiteralPath $candidate) -and ($candidate -ine $SourcePath))) {
        $dir = Split-Path -Parent $DesiredPath
        $candidate = Join-Path $dir ("{0}-{1}{2}" -f $BaseName, $suffix, $Extension)
        $suffix++
    }
    $Used[$candidate.ToLower()] = $true
    return $candidate
}

function Write-ImageMetadata {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string]$Category,
        [Parameter(Mandatory)] [string]$Color,
        [Parameter(Mandatory)] [string]$Style,
        [Parameter(Mandatory)] [string]$Material,
        [Parameter(Mandatory)] [string]$ExifTool
    )

    $title = "$Category $Color $Style $Material"
    $subject = "Jewelry - $Category"
    $comment = "Category: $Category | Color: $Color | Style: $Style | Material: $Material | Classified by AI"

    # Build arguments - each tag separately for Windows filtering
    $exifArgs = @(
        "-overwrite_original"
        "-Title=$title"
        "-Subject=$subject"
        "-XPSubject=$subject"
        "-Comment=$comment"
        "-XPComment=$comment"
        "-Description=$comment"
        "-ImageDescription=$comment"
        # Individual tags for filtering (Windows uses these)
        "-Keywords=Jewelry"
        "-Keywords=Category-$Category"
        "-Keywords=Color-$Color"
        "-Keywords=Style-$Style"
        "-Keywords=Material-$Material"
        "-Keywords=$Category"
        "-Keywords=$Color"
        "-Keywords=$Style"
        "-Keywords=$Material"
        # XMP Keywords (same structure)
        "-XMP-dc:Subject=Jewelry"
        "-XMP-dc:Subject=Category-$Category"
        "-XMP-dc:Subject=Color-$Color"
        "-XMP-dc:Subject=Style-$Style"
        "-XMP-dc:Subject=Material-$Material"
        "-XMP-dc:Subject=$Category"
        "-XMP-dc:Subject=$Color"
        "-XMP-dc:Subject=$Style"
        "-XMP-dc:Subject=$Material"
        # IPTC Keywords
        "-IPTC:Keywords=Jewelry"
        "-IPTC:Keywords=Category-$Category"
        "-IPTC:Keywords=Color-$Color"
        "-IPTC:Keywords=Style-$Style"
        "-IPTC:Keywords=Material-$Material"
        $FilePath
    )

    try {
        $output = & $ExifTool @exifArgs 2>&1
        if ($LASTEXITCODE -eq 0) {
            return [pscustomobject]@{ Success = $true; Message = "Metadata written" }
        } else {
            return [pscustomobject]@{ Success = $false; Message = "$output" }
        }
    } catch {
        return [pscustomobject]@{ Success = $false; Message = $_.Exception.Message }
    }
}

if (-not $ApiKey) {
    $ApiKey = $env:GOOGLE_API_KEY
}

if ($ListModels) {
    if (-not $ApiKey) {
        throw "ApiKey not provided. Use -ApiKey or set GOOGLE_API_KEY."
    }
    Get-GeminiModels -ApiKey $ApiKey -ApiVersion $ApiVersion
    if (-not $Path) {
        return
    }
}

if (-not $Path) {
    throw "Path is required unless -ListModels is used alone."
}

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Path does not exist: $Path"
}

if (-not $ApiKey) {
    throw "ApiKey not provided. Use -ApiKey or set GOOGLE_API_KEY."
}

# Verify ExifTool if metadata writing is requested
if ($WriteMetadata) {
    try {
        $exifTest = & $ExifToolPath -ver 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "ExifTool not working"
        }
        Write-Host "ExifTool found: v$exifTest" -ForegroundColor Green
    } catch {
        throw "ExifTool not found at '$ExifToolPath'. Download from https://exiftool.org/ and specify path with -ExifToolPath or add to PATH."
    }
}

$imageExtensions = @(".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tif", ".tiff", ".heic", ".heif", ".avif")
$files = Get-ChildItem -LiteralPath $Path -File -Recurse:$Recurse -ErrorAction Stop |
    Where-Object { $imageExtensions -contains $_.Extension.ToLowerInvariant() }

if (-not $files) {
    Write-Host "No image files found."
    return
}

# Apply limit if specified
if ($Limit -gt 0 -and @($files).Count -gt $Limit) {
    $files = @($files) | Select-Object -First $Limit
    Write-Host "Limited to first $Limit file(s) for testing." -ForegroundColor Yellow
}

$classified = @()
$fileCount = @($files).Count
$currentFile = 0
Write-Host "Processing $fileCount image(s)..." -ForegroundColor Cyan
Write-Host ""

foreach ($file in $files) {
    $currentFile++
    $created = $file.CreationTime
    if ($created -eq [datetime]::MinValue) {
        $created = $file.LastWriteTime
    }

    Write-Host "[$currentFile/$fileCount] $($file.Name) ... " -NoNewline

    $result = Invoke-GeminiClassifyImage -FilePath $file.FullName -ApiKey $ApiKey -Model $Model -ApiVersion $ApiVersion
    if (-not $result.Success) {
        Write-Host "ERROR" -ForegroundColor Red
        $errorRow = [pscustomobject]@{
            Timestamp  = (Get-Date).ToString("s")
            FilePath   = $file.FullName
            ApiVersion = $result.Error.ApiVersion
            StatusCode = $result.Error.StatusCode
            Message    = $result.Error.Message
            Body       = $result.Error.Body
        }
        Write-CsvRow -FilePath $ErrorLogPath -Row $errorRow
        Write-Warning ("  -> {0}" -f $result.Error.Message)
    } else {
        Write-Host "$($result.Category) $($result.Color) $($result.Style) $($result.Material)" -ForegroundColor Green
        $classified += [pscustomobject]@{
            File        = $file
            Created     = $created
            Category    = $result.Category
            Color       = $result.Color
            Style       = $result.Style
            Material    = $result.Material
            RawCategory = $result.Raw
        }
    }

    if ($DelayMs -gt 0) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

if (-not $classified) {
    Write-Host "No files were classified successfully."
    return
}

$usedTargets = @{}
$plan = @()

foreach ($group in ($classified | Group-Object Category)) {
    $seq = 1
    $sorted = $group.Group | Sort-Object @{ Expression = "Created"; Ascending = $true }, @{ Expression = { $_.File.Name }; Ascending = $true }
    foreach ($item in $sorted) {
        $created = $item.Created
        $reverseKey = Get-ReverseDateKey -DateTime $created
        $dateKey = $created.ToString("yyyyMMdd")
        $seqStr = $seq.ToString().PadLeft(3, "0")
        # Format: Category ReverseDateKey (Color) (Style) (Material) DateKey_Seq
        $baseName = "{0} {1} ({2}) ({3}) ({4}) {5}_{6}" -f $item.Category, $reverseKey, $item.Color, $item.Style, $item.Material, $dateKey, $seqStr
        $ext = $item.File.Extension
        $desiredPath = Join-Path $item.File.DirectoryName ($baseName + $ext)
        $targetPath = Get-UniqueTargetPath -DesiredPath $desiredPath -BaseName $baseName -Extension $ext -SourcePath $item.File.FullName -Used $usedTargets

        $action = if ($targetPath -ieq $item.File.FullName) { "NoChange" } elseif ($Apply) { "Rename" } else { "Preview" }

        $planRow = [pscustomobject]@{
            SourcePath     = $item.File.FullName
            TargetPath     = $targetPath
            Category       = $item.Category
            Color          = $item.Color
            Style          = $item.Style
            Material       = $item.Material
            RawCategory    = $item.RawCategory
            CreatedTime    = $created.ToString("yyyy-MM-dd HH:mm:ss")
            ReverseDateKey = $reverseKey
            DateKey        = $dateKey
            Sequence       = $seqStr
            Action         = $action
        }

        $plan += $planRow
        Write-CsvRow -FilePath $LogPath -Row $planRow

        $seq++
    }
}

Write-Host ("Planned renames: {0}" -f ($plan | Where-Object { $_.Action -ne "NoChange" }).Count)
Write-Host ("Log written: {0}" -f $LogPath)
if (Test-Path -LiteralPath $ErrorLogPath) {
    Write-Host ("Error log: {0}" -f $ErrorLogPath)
}

if (-not $Apply) {
    Write-Host "Preview mode only. Use -Apply to rename files."
    return
}

$toRename = $plan | Where-Object { $_.Action -eq "Rename" }
if (-not $toRename) {
    Write-Host "No files need renaming."
    return
}

$tempMap = @()
foreach ($row in $toRename) {
    $dir = Split-Path -Parent $row.SourcePath
    $tempName = "__tmp__{0}.tmp" -f ([Guid]::NewGuid().ToString("N"))
    $tempPath = Join-Path $dir $tempName
    try {
        Move-Item -LiteralPath $row.SourcePath -Destination $tempPath -ErrorAction Stop
        $tempMap += [pscustomobject]@{
            TempPath = $tempPath
            TargetPath = $row.TargetPath
            OriginalName = Split-Path -Leaf $row.SourcePath
            NewName = Split-Path -Leaf $row.TargetPath
            Category = $row.Category
            Color = $row.Color
            Style = $row.Style
            Material = $row.Material
        }
    } catch {
        Write-Warning ("Failed temp rename for {0}: {1}" -f $row.SourcePath, $_.Exception.Message)
    }
}

$renameReport = @()
foreach ($item in $tempMap) {
    try {
        Move-Item -LiteralPath $item.TempPath -Destination $item.TargetPath -ErrorAction Stop
        $metadataStatus = "N/A"

        # Write metadata if requested
        if ($WriteMetadata) {
            $metaResult = Write-ImageMetadata -FilePath $item.TargetPath -Category $item.Category -Color $item.Color -Style $item.Style -Material $item.Material -ExifTool $ExifToolPath
            if ($metaResult.Success) {
                $metadataStatus = "Written"
            } else {
                $metadataStatus = "Failed: $($metaResult.Message)"
            }
        }

        $renameReport += [pscustomobject]@{
            OriginalFileName = $item.OriginalName
            NewFileName = $item.NewName
            Status = "Success"
            Metadata = $metadataStatus
        }
    } catch {
        Write-Warning ("Failed final rename for {0}: {1}" -f $item.TempPath, $_.Exception.Message)
        $renameReport += [pscustomobject]@{
            OriginalFileName = $item.OriginalName
            NewFileName = $item.NewName
            Status = "Failed: $($_.Exception.Message)"
            Metadata = "Skipped"
        }
    }
}

# Write rename report to output folder
$reportPath = Join-Path $Path ("rename-report_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$renameReport | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host "Rename report saved to: $reportPath" -ForegroundColor Green
Write-Host "Successfully renamed: $($renameReport | Where-Object { $_.Status -eq 'Success' } | Measure-Object | Select-Object -ExpandProperty Count) file(s)" -ForegroundColor Cyan
