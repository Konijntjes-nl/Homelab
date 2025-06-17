# Define the path to analyze
$Path = "D:"

# Get folder sizes and sort by size
Get-ChildItem -Path $Path -Directory -Recurse |
    ForEach-Object {
        $_ | Add-Member -MemberType NoteProperty -Name FolderSize -Value (
            (Get-ChildItem -Path $_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
        ) -PassThru
    } |
    Sort-Object -Property FolderSize -Descending |
    Select-Object -First 10 Name, @{Name="Size(GB)"; Expression={[math]::Round($_.FolderSize / 1GB, 2)}}
