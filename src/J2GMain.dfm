object J2GMainForm: TJ2GMainForm
  Left = 0
  Top = 0
  Caption = 'jvcs2git - JEDI VCS to Git exporter'
  ClientHeight = 600
  ClientWidth = 920
  Color = clBtnFace
  Constraints.MinHeight = 560
  Constraints.MinWidth = 800
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  TextHeight = 15
  object pnlEnv: TPanel
    Left = 0
    Top = 0
    Width = 920
    Height = 48
    Align = alTop
    BevelOuter = bvNone
    Color = clInfoBk
    ParentBackground = False
    TabOrder = 0
    Visible = False
    DesignSize = (
      920
      48)
    object lblEnv: TLabel
      Left = 12
      Top = 4
      Width = 600
      Height = 40
      Anchors = [akLeft, akTop, akRight]
      AutoSize = False
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clInfoText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Layout = tlCenter
      WordWrap = True
    end
    object lnkGit: TLinkLabel
      Left = 624
      Top = 15
      Width = 160
      Height = 19
      Anchors = [akTop, akRight]
      Caption = 'Download Git for Windows'
      TabOrder = 0
      OnLinkClick = lnkGitLinkClick
    end
    object btnRecheck: TButton
      Left = 796
      Top = 11
      Width = 112
      Height = 27
      Anchors = [akTop, akRight]
      Caption = 'Check again'
      TabOrder = 1
      OnClick = btnRecheckClick
    end
  end
  object grpConnection: TGroupBox
    AlignWithMargins = True
    Left = 8
    Top = 54
    Width = 904
    Height = 90
    Margins.Left = 8
    Margins.Top = 6
    Margins.Right = 8
    Margins.Bottom = 0
    Align = alTop
    Caption = 'Connection'
    TabOrder = 1
    DesignSize = (
      904
      90)
    object lblIdentity: TLabel
      Left = 12
      Top = 26
      Width = 80
      Height = 15
      Caption = 'Saved identity:'
      FocusControl = cbIdentity
    end
    object lblBranch: TLabel
      Left = 356
      Top = 26
      Width = 92
      Height = 15
      Caption = 'JEDI VCS branch:'
      FocusControl = edBranch
    end
    object lblServer: TLabel
      Left = 12
      Top = 58
      Width = 66
      Height = 15
      Caption = 'Server:port:'
      FocusControl = edServer
    end
    object lblUser: TLabel
      Left = 356
      Top = 58
      Width = 26
      Height = 15
      Caption = 'User:'
      FocusControl = edUser
    end
    object lblPassword: TLabel
      Left = 590
      Top = 58
      Width = 53
      Height = 15
      Caption = 'Password:'
      FocusControl = edPassword
    end
    object cbIdentity: TComboBox
      Left = 116
      Top = 22
      Width = 224
      Height = 23
      Style = csDropDownList
      TabOrder = 0
      OnChange = cbIdentityChange
    end
    object edBranch: TEdit
      Left = 460
      Top = 22
      Width = 120
      Height = 23
      TabOrder = 1
      Text = 'HEAD'
    end
    object edServer: TEdit
      Left = 116
      Top = 54
      Width = 224
      Height = 23
      TabOrder = 2
      TextHint = 'host:2106'
    end
    object edUser: TEdit
      Left = 460
      Top = 54
      Width = 120
      Height = 23
      TabOrder = 3
    end
    object edPassword: TEdit
      Left = 652
      Top = 54
      Width = 120
      Height = 23
      PasswordChar = '*'
      TabOrder = 4
    end
    object btnList: TButton
      Left = 784
      Top = 52
      Width = 110
      Height = 27
      Anchors = [akTop, akRight]
      Caption = 'List projects'
      Default = True
      TabOrder = 5
      OnClick = btnListClick
    end
  end
  object grpOutput: TGroupBox
    AlignWithMargins = True
    Left = 8
    Top = 150
    Width = 904
    Height = 58
    Margins.Left = 8
    Margins.Top = 6
    Margins.Right = 8
    Margins.Bottom = 0
    Align = alTop
    Caption = 'Output'
    TabOrder = 2
    DesignSize = (
      904
      58)
    object lblOutDir: TLabel
      Left = 12
      Top = 26
      Width = 78
      Height = 15
      Caption = 'Output folder:'
      FocusControl = edOutDir
    end
    object edOutDir: TEdit
      Left = 116
      Top = 22
      Width = 656
      Height = 23
      Anchors = [akLeft, akTop, akRight]
      TabOrder = 0
      TextHint = 'one Git repository per project is created here'
      OnExit = edOutDirExit
    end
    object btnBrowse: TButton
      Left = 784
      Top = 20
      Width = 110
      Height = 27
      Anchors = [akTop, akRight]
      Caption = 'Browse...'
      TabOrder = 1
      OnClick = btnBrowseClick
    end
  end
  object pcMain: TPageControl
    AlignWithMargins = True
    Left = 8
    Top = 214
    Width = 904
    Height = 318
    Margins.Left = 8
    Margins.Top = 6
    Margins.Right = 8
    Margins.Bottom = 4
    ActivePage = tsProjects
    Align = alClient
    TabOrder = 3
    object tsProjects: TTabSheet
      Caption = 'Projects'
      object pnlProjTop: TPanel
        Left = 0
        Top = 0
        Width = 896
        Height = 36
        Align = alTop
        BevelOuter = bvNone
        TabOrder = 0
        object chkShowDeleted: TCheckBox
          Left = 8
          Top = 9
          Width = 260
          Height = 17
          Caption = 'Show (and allow) deleted projects'
          TabOrder = 0
          OnClick = chkShowDeletedClick
        end
        object btnCheckAll: TButton
          Left = 280
          Top = 5
          Width = 100
          Height = 25
          Caption = 'Check all'
          TabOrder = 1
          OnClick = btnCheckAllClick
        end
        object btnUncheckAll: TButton
          Left = 386
          Top = 5
          Width = 100
          Height = 25
          Caption = 'Uncheck all'
          TabOrder = 2
          OnClick = btnUncheckAllClick
        end
      end
      object lvProjects: TListView
        Left = 0
        Top = 36
        Width = 896
        Height = 252
        Align = alClient
        Checkboxes = True
        Columns = <
          item
            Caption = 'Project'
            Width = 400
          end
          item
            Alignment = taRightJustify
            Caption = 'ID'
            Width = 80
          end
          item
            Caption = 'Deleted'
            Width = 90
          end>
        HideSelection = False
        ReadOnly = True
        RowSelect = True
        TabOrder = 1
        ViewStyle = vsReport
      end
    end
    object tsAuthors: TTabSheet
      Caption = 'Authors'
      object lblAuthors: TLabel
        AlignWithMargins = True
        Left = 6
        Top = 6
        Width = 884
        Height = 30
        Margins.Left = 6
        Margins.Top = 6
        Margins.Right = 6
        Align = alTop
        Caption =
          'Name and e-mail of each JEDI VCS login (filled by "List projects' +
          '"). Fill them in BEFORE the export: Git cannot change the authors' +
          ' later. The grid is saved to autores.txt in the output folder wh' +
          'en you click Export.'
        WordWrap = True
      end
      object vleAuthors: TValueListEditor
        Left = 0
        Top = 39
        Width = 896
        Height = 249
        Align = alClient
        DisplayOptions = [doColumnTitles, doAutoColResize, doKeyColFixed]
        KeyOptions = []
        TabOrder = 0
        TitleCaptions.Strings = (
          'Login'
          'Full Name <e-mail>')
        ColWidths = (
          200
          690)
      end
    end
    object tsOptions: TTabSheet
      Caption = 'Options'
      object sbOptions: TScrollBox
        Left = 0
        Top = 0
        Width = 896
        Height = 288
        Align = alClient
        BorderStyle = bsNone
        TabOrder = 0
        object grpHistory: TGroupBox
          Left = 8
          Top = 6
          Width = 432
          Height = 188
          Caption = 'History'
          TabOrder = 0
          object lblMinutes: TLabel
            Left = 380
            Top = 26
            Width = 44
            Height = 15
            Caption = 'minutes'
          end
          object rbGroup: TRadioButton
            Left = 12
            Top = 24
            Width = 302
            Height = 19
            Caption = 'Group check-ins (same user + comment) within'
            Checked = True
            TabOrder = 0
            TabStop = True
            OnClick = OptionChanged
          end
          object seGroup: TSpinEdit
            Left = 318
            Top = 22
            Width = 56
            Height = 24
            MaxValue = 1440
            MinValue = 1
            TabOrder = 1
            Value = 10
          end
          object rbNoGroup: TRadioButton
            Left = 12
            Top = 50
            Width = 400
            Height = 19
            Caption = 'One commit per revision (no grouping)'
            TabOrder = 2
            OnClick = OptionChanged
          end
          object chkLocalTime: TCheckBox
            Left = 12
            Top = 76
            Width = 400
            Height = 19
            Caption = 'Commit dates with the local UTC offset (default +0000)'
            TabOrder = 3
          end
          object chkLabels: TCheckBox
            Left = 12
            Top = 102
            Width = 400
            Height = 19
            Caption = 'JEDI VCS labels as Git tags'
            Checked = True
            State = cbChecked
            TabOrder = 4
          end
          object chkDfmText: TCheckBox
            Left = 12
            Top = 128
            Width = 400
            Height = 19
            Caption = 'Convert binary .dfm files to text'
            Checked = True
            State = cbChecked
            TabOrder = 5
          end
          object chkSkipHidden: TCheckBox
            Left = 12
            Top = 154
            Width = 400
            Height = 19
            Caption = 'Skip hidden modules'
            TabOrder = 6
          end
        end
        object grpGit: TGroupBox
          Left = 452
          Top = 6
          Width = 432
          Height = 188
          Caption = 'Git'
          TabOrder = 1
          object lblGitBranch: TLabel
            Left = 12
            Top = 28
            Width = 58
            Height = 15
            Caption = 'Git branch:'
            FocusControl = edGitBranch
          end
          object edGitBranch: TEdit
            Left = 100
            Top = 24
            Width = 160
            Height = 23
            TabOrder = 0
            Text = 'main'
          end
          object chkNoGit: TCheckBox
            Left = 12
            Top = 58
            Width = 410
            Height = 19
            Caption = 'Only write the fast-import stream (do not run git)'
            TabOrder = 1
            OnClick = chkNoGitClick
          end
          object chkKeepCache: TCheckBox
            Left = 12
            Top = 84
            Width = 410
            Height = 19
            Caption = 'Keep the download cache (.jvcs2git-cache)'
            TabOrder = 2
          end
          object chkForce: TCheckBox
            Left = 12
            Top = 110
            Width = 410
            Height = 19
            Caption = 'Recreate repositories already made by jvcs2git (force)'
            TabOrder = 3
          end
        end
        object grpKey: TGroupBox
          Left = 8
          Top = 202
          Width = 876
          Height = 108
          Caption = 'Blowfish key (encrypted revisions)'
          TabOrder = 2
          object rbKeyRegistry: TRadioButton
            Left = 12
            Top = 24
            Width = 500
            Height = 19
            Caption = 'Key saved by the JEDI VCS client (registry)'
            Checked = True
            TabOrder = 0
            TabStop = True
            OnClick = OptionChanged
          end
          object rbKeyFile: TRadioButton
            Left = 12
            Top = 50
            Width = 140
            Height = 19
            Caption = 'Key from a file:'
            TabOrder = 1
            OnClick = OptionChanged
          end
          object edKeyFile: TEdit
            Left = 160
            Top = 48
            Width = 590
            Height = 23
            TabOrder = 2
            TextHint = 'Base64 in the first line; keep it outside the output folder'
          end
          object btnKeyFile: TButton
            Left = 756
            Top = 46
            Width = 110
            Height = 27
            Caption = 'Browse...'
            TabOrder = 3
            OnClick = btnKeyFileClick
          end
          object rbKeyNone: TRadioButton
            Left = 12
            Top = 78
            Width = 500
            Height = 19
            Caption = 'No key (encrypted revisions are skipped)'
            TabOrder = 4
            OnClick = OptionChanged
          end
        end
      end
    end
    object tsLog: TTabSheet
      Caption = 'Log'
      object memLog: TMemo
        Left = 0
        Top = 0
        Width = 896
        Height = 288
        Align = alClient
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Consolas'
        Font.Style = []
        ParentFont = False
        ReadOnly = True
        ScrollBars = ssBoth
        TabOrder = 0
        WordWrap = False
      end
    end
    object tsAbout: TTabSheet
      Caption = 'About'
      object memAbout: TMemo
        AlignWithMargins = True
        Left = 8
        Top = 8
        Width = 880
        Height = 272
        Margins.Left = 8
        Margins.Top = 8
        Margins.Right = 8
        Margins.Bottom = 8
        Align = alClient
        BorderStyle = bsNone
        ParentColor = True
        ReadOnly = True
        TabOrder = 0
      end
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 536
    Width = 920
    Height = 64
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 4
    DesignSize = (
      920
      64)
    object lblStatus: TLabel
      Left = 10
      Top = 34
      Width = 438
      Height = 15
      Anchors = [akLeft, akTop, akRight]
      AutoSize = False
      EllipsisPosition = epEndEllipsis
      ShowAccelChar = False
    end
    object pbProgress: TProgressBar
      Left = 8
      Top = 4
      Width = 904
      Height = 18
      Anchors = [akLeft, akTop, akRight]
      TabOrder = 0
    end
    object btnExport: TButton
      Left = 456
      Top = 28
      Width = 100
      Height = 28
      Anchors = [akTop, akRight]
      Caption = 'Export'
      TabOrder = 1
      OnClick = btnExportClick
    end
    object btnCancel: TButton
      Left = 562
      Top = 28
      Width = 100
      Height = 28
      Anchors = [akTop, akRight]
      Caption = 'Cancel'
      TabOrder = 2
      OnClick = btnCancelClick
    end
    object btnOpenFolder: TButton
      Left = 668
      Top = 28
      Width = 118
      Height = 28
      Anchors = [akTop, akRight]
      Caption = 'Open folder'
      TabOrder = 3
      OnClick = btnOpenFolderClick
    end
    object btnOpenReport: TButton
      Left = 792
      Top = 28
      Width = 120
      Height = 28
      Anchors = [akTop, akRight]
      Caption = 'Open report'
      TabOrder = 4
      OnClick = btnOpenReportClick
    end
  end
end
