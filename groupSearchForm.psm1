#Requires -Modules ActiveDirectory
[void][System.Reflection.Assembly]::Load('System.Drawing, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a')
[void][System.Reflection.Assembly]::Load('System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')

function Add-ADGroupForm
{

    param(
        [string[]]$SecurityGroups
    )

    $Script:allADGroups = (Get-ADGroup -filter *).SamAccountName | Sort-Object

    $groupSearchForm = New-Object -TypeName System.Windows.Forms.Form

    $groupSearchLabel = (New-Object -TypeName System.Windows.Forms.Label)
    $groupSearchTextBox = (New-Object -TypeName System.Windows.Forms.TextBox)
    $groupSelectLabel = (New-Object -TypeName System.Windows.Forms.Label)
    $groupSelectComboBox = (New-Object -TypeName System.Windows.Forms.ComboBox)
    $selectedGroupsLabel = (New-Object -TypeName System.Windows.Forms.Label)
    $selectedGroupsListBox = (New-Object -TypeName System.Windows.Forms.ListBox)
    $searchButton = (New-Object -TypeName System.Windows.Forms.Button)
    $addGroupButton = (New-Object -TypeName System.Windows.Forms.Button)
    $removeGroupButton = (New-Object -TypeName System.Windows.Forms.Button)
    $confirmButton = (New-Object -TypeName System.Windows.Forms.Button)
    $groupSearchForm.SuspendLayout()

    ##############
    ### LABELS ###
    ##############

    #groupSearchLabel
    $groupSearchLabel.AutoSize = $true
    $groupSearchLabel.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]13,[System.Int32]15))
    $groupSearchLabel.Name = [System.String]'groupSearchLabel'
    $groupSearchLabel.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList @([System.Int32]35,[System.Int32]13))
    $groupSearchLabel.Text = [System.String]'AD Group Search'

    #groupSelectLabel
    $groupSelectLabel.AutoSize = $true
    $groupSelectLabel.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]12,[System.Int32]78))
    $groupSelectLabel.Name = [System.String]'groupSelectLabel'
    $groupSelectLabel.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList @([System.Int32]35,[System.Int32]13))
    $groupSelectLabel.Text = [System.String]'AD Group Select'

    #selectedGroupsLabel
    $selectedGroupsLabel.AutoSize = $true
    $selectedGroupsLabel.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]12,[System.Int32]156))
    $selectedGroupsLabel.Name = [System.String]'selectedGroupsLabel'
    $selectedGroupsLabel.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList @([System.Int32]35,[System.Int32]13))
    $selectedGroupsLabel.Text = [System.String]'New Hire AD Groups'

    ############################
    ### TEXT AND COMBO BOXES ###
    ############################

    #groupSearchTextBox
    $groupSearchTextBox.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]12,[System.Int32]34))
    $groupSearchTextBox.Add_KeyDown({
        if($_.KeyCode -eq 'Enter'){$searchButton.PerformClick(); $groupSearchTextBox.SelectAll()}
        #if($_.KeyCode -eq '^' -and $_.KeyCode -eq 'A'){$groupSearchTextBox.SelectAll()}
    })
    $groupSearchTextBox.Name = [System.String]'groupSearchTextBox'
    $groupSearchTextBox.ShortcutsEnabled = $true
    $groupSearchTextBox.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList @([System.Int32]252,[System.Int32]20))
    $groupSearchTextBox.TabIndex = [System.Int32]0


    #groupSelectComboBox
    $groupSelectComboBox.FormattingEnabled = $true
    $groupSelectComboBox.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]12,[System.Int32]97))
    $groupSelectComboBox.Add_KeyDown({if($_.KeyCode -eq 'Enter'){$addGroupButton.PerformClick()}})
    $groupSelectComboBox.Name = [System.String]'groupSelectComboBox'
    $groupSelectComboBox.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList @([System.Int32]252,[System.Int32]21))
    $groupSelectComboBox.TabIndex = [System.Int32]2
    $Script:allADGroups | ForEach-Object{[void]$groupSelectComboBox.Items.Add($_)}

    #selectedGroupsListBox
    $selectedGroupsListBox.FormattingEnabled = $true
    $selectedGroupsListBox.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]12,[System.Int32]175))
    $selectedGroupsListBox.Name = [System.String]'selectedGroupsListBox'
    $selectedGroupsListBox.Sorted = $true
    $selectedGroupsListBox.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList @([System.Int32]252,[System.Int32]212))
    $selectedGroupsListBox.SelectionMode = [System.Windows.Forms.SelectionMode]::MultiExtended
    $selectedGroupsListBox.TabIndex = [System.Int32]4
    $SecurityGroups | Sort-Object -Unique | ForEach-Object{[void]$selectedGroupsListBox.Items.Add($_)}


    ###############
    ### BUTTONS ###
    ###############

    #searchButton
    $searchButton.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]300,[System.Int32]32))
    $searchButton.Name = [System.String]'searchButton'
    $searchButton.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList @([System.Int32]116,[System.Int32]23))
    $searchButton.TabIndex = [System.Int32]1
    $searchButton.Text = [System.String]'Search'
    $searchButton.UseVisualStyleBackColor = $true
    $searchButton.Add_Click({
        #If the list of all AD groups contains an exact match for the search string, adds to ListBox
        if($Script:allADGroups -contains $groupSearchTextBox.Text -and `
        $selectedGroupsListBox.Items -notcontains $groupSearchTextBox.Text)
        {$selectedGroupsListBox.Items.Add($groupSearchTextBox.Text)}
        #If more than one result, updates combo box w/matching values
        else{
            #Resets comboBox
            $groupSelectComboBox.Items.Clear()
            #Assigns matching results to searchResults
            $searchResults = try{$Script:allADGroups | Where-Object {$_ -match $groupSearchTextBox.Text}}
                            catch{$null}
            #If no results, adds all AD groups to results
            if(!$searchResults){$searchResults = $Script:allADGroups}

            #Adds search results to drop-down combo box
            foreach($result in $searchResults){[void]$groupSelectComboBox.Items.Add($result)}
            $groupSelectComboBox.Text = $groupSelectComboBox.Items[0]
        }
        #Refreshes form
        $groupSearchForm.Refresh()
    })

    #addGroupButton
    $addGroupButton.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]300,[System.Int32]95))
    $addGroupButton.Name = [System.String]'addGroupButton'
    $addGroupButton.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList @([System.Int32]116,[System.Int32]23))
    $addGroupButton.TabIndex = [System.Int32]3
    $addGroupButton.Text = [System.String]'Add'
    $addGroupButton.UseVisualStyleBackColor = $true
    $addGroupButton.Add_Click({
        if($selectedGroupsListBox.Items -notcontains $groupSelectComboBox.SelectedItem)
        {$selectedGroupsListBox.Items.Add($groupSelectComboBox.SelectedItem)}
    })

    #removeGroupButton
    $removeGroupButton.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]300,[System.Int32]175))
    $removeGroupButton.Name = [System.String]'removeGroupButton'
    $removeGroupButton.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList @([System.Int32]116,[System.Int32]23))
    $removeGroupButton.TabIndex = [System.Int32]5
    $removeGroupButton.Text = [System.String]'Remove'
    $removeGroupButton.Add_Click({
        #https://sharepoint.stackexchange.com/questions/131782/collection-was-modified-enumeration-operation-may-not-execute-delete-all-librar
        $valuesToRemove = @()
        $selectedGroupsListBox.SelectedItems | ForEach-Object{
            #Excludes imported values from SecurityGroups parameter
            if($SecurityGroups -notcontains $_){$valuesToRemove += $_}
        }
        $ValuesToRemove | ForEach-Object{[void]$selectedGroupsListBox.Items.Remove("$_")}
        #Resets selection in listbox
        $selectedGroupsListBox.ClearSelected()
    })
    $removeGroupButton.UseVisualStyleBackColor = $true

    #confirmButton
    $confirmButton.Location = (New-Object -TypeName System.Drawing.Point -ArgumentList @([System.Int32]319,[System.Int32]404))
    $confirmButton.Name = [System.String]'confirmButton'
    $confirmButton.Size = (New-Object -TypeName System.Drawing.Size -ArgumentList @([System.Int32]116,[System.Int32]23))
    $confirmButton.TabIndex = [System.Int32]6
    $confirmButton.Text = [System.String]'Confirm'
    $confirmButton.Add_Click({
        $groupSearchForm.DialogResult = 'OK'
        $groupSearchForm.Close()
    })
    $confirmButton.UseVisualStyleBackColor = $true


    #####################
    ### FORM & OUTPUT ###
    #####################

    #groupSearchForm Properties
    $groupSearchForm.ClientSize = (New-Object -TypeName System.Drawing.Size -ArgumentList @([System.Int32]447,[System.Int32]439))
    $groupSearchForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    #Sets on top
    $groupSearchForm.Topmost = $True
    #Sets a 'shown' event that sets the form as active
    $groupSearchForm.Add_Shown({$groupSearchForm.Activate()})
    $groupSearchForm.Name = [System.String]'groupSearchForm'
    $groupSearchForm.Text = "AD Group Search"
    $groupSearchForm.MaximizeBox = $false
    $groupSearchForm.MinimizeBox = $false
    $groupSearchForm.ControlBox = $false
    #Disallow resize:  https://stackoverflow.com/questions/11021950/powershell-disabling-windows-forms-resize
    $groupSearchForm.FormBorderStyle = 'FixedDialog'
    $groupSearchForm.ResumeLayout($false)
    #AddLabels
    $groupSearchForm.Controls.AddRange(@($groupSearchLabel, $groupSelectLabel, $selectedGroupsLabel))
    #AddBoxes
    $groupSearchForm.Controls.AddRange(@($groupSearchTextBox, $selectedGroupsListBox, $groupSelectComboBox))
    #AddButtons
    $groupSearchForm.Controls.AddRange(@($searchButton, $addGroupButton, $removeGroupButton, $confirmButton))
    #Render
    $groupSearchForm.PerformLayout()
    [void]$groupSearchForm.Focus()

    $DialogResult = $groupSearchForm.ShowDialog()

    if($DialogResult -eq 'OK')
    {
        $SecurityGroups = $selectedGroupsListBox.Items

        $SecurityGroups
    }
}