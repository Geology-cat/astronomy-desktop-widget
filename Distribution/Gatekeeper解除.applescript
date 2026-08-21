use scripting additions

property expectedBundleIdentifier : "jp.yamashitaujou.AstronomyDesktopWidget"
property applicationName : "天文情報ウィジェット"

on run
    set targetPath to my findInstalledApp()
    if targetPath is missing value then set targetPath to my requestAppSelection()
    if targetPath is missing value then return

    set dialogResult to display dialog ¬
        "次の「天文情報ウィジェット」の隔離属性だけを解除し、起動します。" & return & return & ¬
        targetPath & return & return & ¬
        "Mac全体のGatekeeper設定は変更しません。配布元を信頼できる場合のみ続けてください。" ¬
        with title "天文情報ウィジェット Gatekeeper解除" ¬
        buttons {"キャンセル", "解除して起動"} ¬
        default button "解除して起動" ¬
        cancel button "キャンセル" ¬
        with icon caution

    if button returned of dialogResult is not "解除して起動" then return

    try
        do shell script ¬
            "/usr/bin/xattr -dr com.apple.quarantine " & quoted form of targetPath ¬
            with administrator privileges
    on error errorMessage number errorNumber
        display alert "隔離属性を解除できませんでした" message ¬
            "エラー " & errorNumber & ": " & errorMessage ¬
            as critical buttons {"OK"} default button "OK"
        return
    end try

    try
        do shell script "/usr/bin/open " & quoted form of targetPath
        display notification "初回起動の準備が完了しました。" with title applicationName
    on error errorMessage number errorNumber
        display alert "天文情報ウィジェットを起動できませんでした" message ¬
            "隔離属性の解除は完了しています。アプリケーションフォルダから起動してください。" & ¬
            return & return & "エラー " & errorNumber & ": " & errorMessage ¬
            buttons {"OK"} default button "OK"
    end try
end run

-- アプリケーションフォルダ内の対象アプリを既知の名前とBundle IDから探します。
on findInstalledApp()
    set homePath to POSIX path of (path to home folder)
    set candidatePaths to {¬
        "/Applications/天文情報ウィジェット.app", ¬
        homePath & "Applications/天文情報ウィジェット.app"}

    repeat with candidatePath in candidatePaths
        set resolvedPath to contents of candidatePath
        if my isExpectedApplication(resolvedPath) then return resolvedPath
    end repeat

    set searchRoots to {"/Applications", homePath & "Applications"}
    repeat with searchRoot in searchRoots
        set rootPath to contents of searchRoot
        try
            do shell script "/bin/test -d " & quoted form of rootPath
            set searchResult to do shell script ¬
                "/usr/bin/mdfind -onlyin " & quoted form of rootPath & ¬
                " 'kMDItemCFBundleIdentifier == \"" & expectedBundleIdentifier & "\"c'"

            repeat with resultPath in paragraphs of searchResult
                set resolvedPath to contents of resultPath
                if my isExpectedApplication(resolvedPath) then return resolvedPath
            end repeat
        end try
    end repeat

    return missing value
end findInstalledApp

-- 自動検出できない場合は、ユーザーが選んだアプリのBundle IDを確認します。
on requestAppSelection()
    set dialogResult to display dialog ¬
        "アプリケーションフォルダ内で「天文情報ウィジェット」を自動検出できませんでした。" & ¬
        return & return & "コピーした「天文情報ウィジェット.app」を選択してください。" ¬
        with title "天文情報ウィジェット Gatekeeper解除" ¬
        buttons {"キャンセル", "アプリを選択…"} ¬
        default button "アプリを選択…" ¬
        cancel button "キャンセル" ¬
        with icon caution

    if button returned of dialogResult is not "アプリを選択…" then return missing value

    try
        set selectedApp to (choose file ¬
            with prompt "コピーした「天文情報ウィジェット.app」を選択してください。" ¬
            of type {"com.apple.application-bundle"} ¬
            default location (path to applications folder))
        set selectedPath to POSIX path of selectedApp

        if my isExpectedApplication(selectedPath) then return selectedPath

        display alert "対象のアプリではありません" message ¬
            "選択したアプリのBundle IDが一致しません。天文情報ウィジェット.appを選択してください。" ¬
            as critical buttons {"OK"} default button "OK"
    on error errorMessage number errorNumber
        if errorNumber is -128 then return missing value
        display alert "アプリを選択できませんでした" message ¬
            "エラー " & errorNumber & ": " & errorMessage ¬
            as critical buttons {"OK"} default button "OK"
    end try

    return missing value
end requestAppSelection

-- 指定パスが対象のアプリバンドルかを判定します。
on isExpectedApplication(appPath)
    try
        do shell script "/bin/test -d " & quoted form of appPath
        set plistPath to appPath & "/Contents/Info.plist"
        set bundleIdentifier to do shell script ¬
            "/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' " & quoted form of plistPath
        return bundleIdentifier is expectedBundleIdentifier
    on error
        return false
    end try
end isExpectedApplication
