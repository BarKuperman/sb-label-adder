Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "Subway Builder Label Adder"
$form.Size = New-Object System.Drawing.Size(550,300)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$labelBaseMap = New-Object System.Windows.Forms.Label
$labelBaseMap.Location = New-Object System.Drawing.Point(15,20)
$labelBaseMap.Size = New-Object System.Drawing.Size(120,20)
$labelBaseMap.Text = "Base Map (.pmtiles):"
$form.Controls.Add($labelBaseMap)

$textBoxBaseMap = New-Object System.Windows.Forms.TextBox
$textBoxBaseMap.Location = New-Object System.Drawing.Point(140,18)
$textBoxBaseMap.Size = New-Object System.Drawing.Size(300,20)
$form.Controls.Add($textBoxBaseMap)

$buttonBrowse = New-Object System.Windows.Forms.Button
$buttonBrowse.Location = New-Object System.Drawing.Point(450,16)
$buttonBrowse.Size = New-Object System.Drawing.Size(75,23)
$buttonBrowse.Text = "Browse..."
$buttonBrowse.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "PMTiles Files (*.pmtiles)|*.pmtiles|All Files (*.*)|*.*"
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textBoxBaseMap.Text = $openFileDialog.FileName
    }
})
$form.Controls.Add($buttonBrowse)

$labelBbox = New-Object System.Windows.Forms.Label
$labelBbox.Location = New-Object System.Drawing.Point(15,60)
$labelBbox.Size = New-Object System.Drawing.Size(120,20)
$labelBbox.Text = "BBox (Optional):"
$form.Controls.Add($labelBbox)

$textBoxBbox = New-Object System.Windows.Forms.TextBox
$textBoxBbox.Location = New-Object System.Drawing.Point(140,58)
$textBoxBbox.Size = New-Object System.Drawing.Size(300,20)
$form.Controls.Add($textBoxBbox)

$checkBoxPreferEnglish = New-Object System.Windows.Forms.CheckBox
$checkBoxPreferEnglish.Location = New-Object System.Drawing.Point(140,90)
$checkBoxPreferEnglish.Size = New-Object System.Drawing.Size(350,20)
$checkBoxPreferEnglish.Text = "--prefer-english: Fallback to English names when available"
$form.Controls.Add($checkBoxPreferEnglish)

$checkBoxForceEnglish = New-Object System.Windows.Forms.CheckBox
$checkBoxForceEnglish.Location = New-Object System.Drawing.Point(140,115)
$checkBoxForceEnglish.Size = New-Object System.Drawing.Size(400,20)
$checkBoxForceEnglish.Text = "--force-english: Only use English names (drops un-translated ones)"
$form.Controls.Add($checkBoxForceEnglish)

$checkBoxSan = New-Object System.Windows.Forms.CheckBox
$checkBoxSan.Location = New-Object System.Drawing.Point(140,140)
$checkBoxSan.Size = New-Object System.Drawing.Size(350,20)
$checkBoxSan.Text = "--san: Move OSM suburb tags to neighborhoods layer"
$form.Controls.Add($checkBoxSan)

$buttonRun = New-Object System.Windows.Forms.Button
$buttonRun.Location = New-Object System.Drawing.Point(180,190)
$buttonRun.Size = New-Object System.Drawing.Size(180,40)
$buttonRun.Text = "Generate Map!"
$buttonRun.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$buttonRun.Add_Click({
    if ([string]::IsNullOrWhiteSpace($textBoxBaseMap.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Please select a base .pmtiles map first.")
        return
    }
    
    # We rely on GUI.bat changing the working directory correctly
    $scriptDir = (Get-Location).Path
    $escapedPath = $textBoxBaseMap.Text.Replace('\', '/')
    
    # To prevent bash from choking on spaces in the script's absolute Windows path,
    # we navigate to the folder directly and execute from the working directory.
    Set-Location -Path $scriptDir
    
    $argList = @('./build_labeled_map.sh', '--base-map', "$escapedPath")
    
    if (-not [string]::IsNullOrWhiteSpace($textBoxBbox.Text)) {
        $argList += '--bbox'
        $argList += "$($textBoxBbox.Text)"
    }
    
    if ($checkBoxPreferEnglish.Checked) { $argList += '--prefer-english' }
    if ($checkBoxForceEnglish.Checked) { $argList += '--force-english' }
    if ($checkBoxSan.Checked) { $argList += '--san' }
    
    $form.Hide()
    
    Clear-Host
    Write-Host "========================================="
    Write-Host "  Subway Builder Label Adder is running  "
    Write-Host "=========================================`n"
    
    # Properly pass the array to the executable
    & wsl @argList
    
    Write-Host "`n========================================="
    Write-Host "Finished! You can press any key to close this window..."
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
    
    $form.Close()
})
$form.Controls.Add($buttonRun)

$form.ShowDialog()
