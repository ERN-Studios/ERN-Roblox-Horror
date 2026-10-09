param(
    [string]$GeneratedImageDirectory = 'C:\Users\mikke\.codex\generated_images\01a06ca9-ea60-7a10-9270-d29045523590',
    [string[]]$BadgeNames
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$badgeImages = [ordered]@{
    'level-1-cleared' = 'exec-fe8d5914-5635-49fe-b891-1c64e625bfd4.png'
    'level-2-cleared' = 'exec-aa4e92ee-a673-4843-8c4b-a0f19ef52170.png'
    # REJECTED escalator variant: retained for provenance only, never upload.
    'level-3-cleared' = 'exec-a826c876-6bdc-4f8c-aace-4a5fa976bd6e.png'
    'level-3-cleared-map-v2' = 'exec-50232b94-b779-4879-a1ce-de35b431433f.png'
    'stay-quiet' = 'exec-98b0458c-a38f-4dda-b8a6-bdc12bd86637.png'
}

$sourceDirectory = Join-Path $PSScriptRoot 'source'
$iconDirectory = Join-Path $PSScriptRoot 'icons-512'
[void](New-Item -ItemType Directory -Path $sourceDirectory -Force)
[void](New-Item -ItemType Directory -Path $iconDirectory -Force)

foreach ($badge in $badgeImages.GetEnumerator()) {
    if ($BadgeNames -and ($BadgeNames -notcontains $badge.Key)) { continue }
    $generatedPath = Join-Path $GeneratedImageDirectory $badge.Value
    $sourcePath = Join-Path $sourceDirectory ($badge.Key + '-source.png')
    $iconPath = Join-Path $iconDirectory ($badge.Key + '.png')
    if ((Test-Path -LiteralPath $sourcePath) -or (Test-Path -LiteralPath $iconPath)) {
        throw "Refusing to overwrite existing badge assets: $($badge.Key)"
    }

    Copy-Item -LiteralPath $generatedPath -Destination $sourcePath
    $sourceImage = [System.Drawing.Image]::FromFile($sourcePath)
    $icon = $null
    $graphics = $null
    $attributes = $null
    try {
        if ($sourceImage.Width -ne $sourceImage.Height) {
            throw "Badge source must be square: $sourcePath"
        }

        $icon = [System.Drawing.Bitmap]::new(512, 512, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($icon)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
        $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $destination = [System.Drawing.Rectangle]::new(0, 0, 512, 512)
        $graphics.DrawImage($sourceImage, $destination, 0, 0, $sourceImage.Width, $sourceImage.Height, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        $icon.Save($iconPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        if ($null -ne $attributes) { $attributes.Dispose() }
        if ($null -ne $graphics) { $graphics.Dispose() }
        if ($null -ne $icon) { $icon.Dispose() }
        $sourceImage.Dispose()
    }

    Get-Item -LiteralPath $iconPath | Select-Object FullName, Length
}
