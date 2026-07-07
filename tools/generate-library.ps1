param(
    [string]$ServerWz = "C:\Users\DELL\Desktop\MapleRoot Full Repack\Server\wz",
    [string]$ClientData = "C:\Users\DELL\Desktop\KairoMS\Data",
    [string]$OutFile = (Join-Path (Split-Path $PSScriptRoot -Parent) "data\items.json")
)

$ErrorActionPreference = "Stop"

function Require-Folder {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Folder not found: $Path"
    }
}

function Require-File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: $Path"
    }
}

function Load-Xml {
    param([string]$Path)
    Require-File $Path
    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $false
    $doc.Load($Path)
    return $doc
}

function Get-Attr {
    param(
        [System.Xml.XmlNode]$Node,
        [string]$Name
    )
    if ($null -eq $Node -or $null -eq $Node.Attributes[$Name]) {
        return ""
    }
    return $Node.Attributes[$Name].Value
}

function Clean-MapleText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $clean = $Text -replace "\\r", "`r" -replace "\\n", "`n"
    $clean = $clean -replace "#[a-zA-Z0-9]", ""
    $clean = $clean -replace "\s+\r?\n", "`n"
    return $clean.Trim()
}

function Get-EquipCategory {
    param([int]$ItemId)

    if (($ItemId -ge 1010000 -and $ItemId -lt 1040000) -or ($ItemId -ge 1120000 -and $ItemId -lt 1200000)) { return "Accessory" }
    if ($ItemId -ge 1000000 -and $ItemId -lt 1010000) { return "Cap" }
    if ($ItemId -ge 1100000 -and $ItemId -lt 1110000) { return "Cape" }
    if ($ItemId -ge 1040000 -and $ItemId -lt 1050000) { return "Coat" }
    if (($ItemId -ge 20000 -and $ItemId -lt 30000) -or ($ItemId -ge 50000 -and $ItemId -lt 60000)) { return "Face" }
    if ($ItemId -ge 1080000 -and $ItemId -lt 1090000) { return "Glove" }
    if (($ItemId -ge 30000 -and $ItemId -lt 50000) -or ($ItemId -ge 60000 -and $ItemId -lt 70000)) { return "Hair" }
    if ($ItemId -ge 1050000 -and $ItemId -lt 1060000) { return "Longcoat" }
    if ($ItemId -ge 1060000 -and $ItemId -lt 1070000) { return "Pants" }
    if ($ItemId -ge 1802000 -and $ItemId -lt 1842000) { return "PetEquip" }
    if ($ItemId -ge 1112000 -and $ItemId -lt 1120000) { return "Ring" }
    if ($ItemId -ge 1090000 -and $ItemId -lt 1100000) { return "Shield" }
    if ($ItemId -ge 1070000 -and $ItemId -lt 1080000) { return "Shoes" }
    if ($ItemId -ge 1900000 -and $ItemId -lt 2000000) { return "TamingMob" }
    if ($ItemId -ge 1210000 -and $ItemId -lt 1800000) { return "Weapon" }
    return "Equipment"
}

function Get-ItemAssetGroup {
    param([int]$ItemId)
    return ("{0:D8}" -f $ItemId).Substring(0, 4)
}

function New-FileSet {
    param(
        [string]$Path,
        [string]$Filter
    )

    $set = @{}
    if (Test-Path -LiteralPath $Path -PathType Container) {
        Get-ChildItem -LiteralPath $Path -Filter $Filter -File | ForEach-Object {
            $set[$_.Name] = $true
        }
    }
    return $set
}

function Test-EquipAsset {
    param(
        [int]$ItemId,
        [string]$Category,
        [string]$Root,
        [bool]$Server
    )

    $fileName = "{0:D8}.img" -f $ItemId
    if ($Server) {
        $fileName = "$fileName.xml"
        return $script:ServerEquipSets.ContainsKey($Category) -and $script:ServerEquipSets[$Category].ContainsKey($fileName)
    }
    return $script:ClientEquipSets.ContainsKey($Category) -and $script:ClientEquipSets[$Category].ContainsKey($fileName)
}

function Test-ItemAsset {
    param(
        [int]$ItemId,
        [string]$Category,
        [string]$Root,
        [bool]$Server
    )

    $group = Get-ItemAssetGroup $ItemId
    $fileName = "$group.img"
    if ($Server) {
        $fileName = "$fileName.xml"
        return $script:ServerItemSets.ContainsKey($Category) -and $script:ServerItemSets[$Category].ContainsKey($fileName)
    }
    return $script:ClientItemSets.ContainsKey($Category) -and $script:ClientItemSets[$Category].ContainsKey($fileName)
}

function New-ItemRecord {
    param(
        [int]$Id,
        [string]$Name,
        [string]$Desc,
        [string]$Type,
        [string]$Category,
        [bool]$ClientAsset,
        [bool]$ServerAsset
    )

    return [pscustomobject]@{
        id = $Id
        name = $Name
        desc = $Desc
        type = $Type
        category = $Category
        clientAsset = $ClientAsset
        serverAsset = $ServerAsset
        search = (($Id.ToString(), $Name, $Desc, $Type, $Category) -join " ").ToLowerInvariant()
    }
}

function Add-RecordFromNode {
    param(
        [System.Collections.Generic.List[object]]$Items,
        [System.Xml.XmlNode]$Node,
        [string]$Type,
        [string]$Category
    )

    $idText = Get-Attr $Node "name"
    $id = 0
    if (-not [int]::TryParse($idText, [ref]$id)) {
        return
    }

    $name = Clean-MapleText (Get-Attr ($Node.SelectSingleNode("./string[@name='name']")) "value")
    if ([string]::IsNullOrWhiteSpace($name)) {
        return
    }

    $desc = Clean-MapleText (Get-Attr ($Node.SelectSingleNode("./string[@name='desc']")) "value")

    if ($Type -eq "Equipment") {
        $actualCategory = if ($Category) { $Category } else { Get-EquipCategory $id }
        $clientAsset = Test-EquipAsset -ItemId $id -Category $actualCategory -Root $ClientData -Server $false
        $serverAsset = Test-EquipAsset -ItemId $id -Category $actualCategory -Root $ServerWz -Server $true
    } else {
        $actualCategory = $Category
        $clientAsset = Test-ItemAsset -ItemId $id -Category $actualCategory -Root $ClientData -Server $false
        $serverAsset = Test-ItemAsset -ItemId $id -Category $actualCategory -Root $ServerWz -Server $true
    }

    $Items.Add((New-ItemRecord -Id $id -Name $name -Desc $desc -Type $Type -Category $actualCategory -ClientAsset $clientAsset -ServerAsset $serverAsset))
}

Require-Folder $ServerWz
Require-Folder $ClientData

$stringRoot = Join-Path $ServerWz "String.wz"
Require-Folder $stringRoot

$script:ClientEquipSets = @{}
$script:ServerEquipSets = @{}
$equipCategories = @("Accessory", "Afterimage", "Cap", "Cape", "Coat", "Dragon", "Face", "Glove", "Hair", "Longcoat", "Pants", "PetEquip", "Ring", "Shield", "Shoes", "TamingMob", "Weapon")
foreach ($category in $equipCategories) {
    $script:ClientEquipSets[$category] = New-FileSet -Path (Join-Path $ClientData "Character\$category") -Filter "*.img"
    $script:ServerEquipSets[$category] = New-FileSet -Path (Join-Path $ServerWz "Character.wz\$category") -Filter "*.img.xml"
}

$script:ClientItemSets = @{}
$script:ServerItemSets = @{}
$itemCategories = @("Cash", "Consume", "Etc", "Install", "Pet", "Special")
foreach ($category in $itemCategories) {
    $script:ClientItemSets[$category] = New-FileSet -Path (Join-Path $ClientData "Item\$category") -Filter "*.img"
    $script:ServerItemSets[$category] = New-FileSet -Path (Join-Path $ServerWz "Item.wz\$category") -Filter "*.img.xml"
}

$items = New-Object System.Collections.Generic.List[object]

$eqpDoc = Load-Xml (Join-Path $stringRoot "Eqp.img.xml")
$eqpRoot = $eqpDoc.SelectSingleNode("/imgdir[@name='Eqp.img']/imgdir[@name='Eqp']")
foreach ($categoryNode in $eqpRoot.SelectNodes("./imgdir[@name]")) {
    $category = Get-Attr $categoryNode "name"
    foreach ($itemNode in $categoryNode.SelectNodes("./imgdir[@name]")) {
        Add-RecordFromNode -Items $items -Node $itemNode -Type "Equipment" -Category $category
    }
}

$itemStringFiles = @(
    @{ File = "Consume.img.xml"; Type = "Use"; Category = "Consume"; Nested = "" },
    @{ File = "Etc.img.xml"; Type = "Etc"; Category = "Etc"; Nested = "Etc" },
    @{ File = "Ins.img.xml"; Type = "Setup"; Category = "Install"; Nested = "" },
    @{ File = "Cash.img.xml"; Type = "Cash"; Category = "Cash"; Nested = "" },
    @{ File = "Pet.img.xml"; Type = "Pet"; Category = "Pet"; Nested = "" }
)

foreach ($spec in $itemStringFiles) {
    $path = Join-Path $stringRoot $spec.File
    if (-not (Test-Path -LiteralPath $path)) {
        continue
    }

    $doc = Load-Xml $path
    $root = $doc.DocumentElement
    $parent = $root
    if ($spec.Nested) {
        $parent = $root.SelectSingleNode("./imgdir[@name='$($spec.Nested)']")
    }

    if ($null -eq $parent) {
        continue
    }

    foreach ($itemNode in $parent.SelectNodes("./imgdir[@name]")) {
        Add-RecordFromNode -Items $items -Node $itemNode -Type $spec.Type -Category $spec.Category
    }
}

$sorted = @($items | Sort-Object @{ Expression = "name"; Ascending = $true }, @{ Expression = "id"; Ascending = $true })

$payload = [pscustomobject]@{
    generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    serverWz = $ServerWz
    clientData = $ClientData
    total = $sorted.Count
    items = $sorted
}

$outDir = Split-Path $OutFile -Parent
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}

$json = $payload | ConvertTo-Json -Depth 8 -Compress
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutFile, $json, $utf8NoBom)

Write-Host "Generated KairoMS library database:"
Write-Host $OutFile
Write-Host "Items: $($sorted.Count)"
