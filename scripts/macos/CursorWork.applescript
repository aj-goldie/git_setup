-- Cursor Work.app
-- Launches Cursor with a separate user data directory for work account (bai-admin)
-- This keeps work GitHub authentication separate from personal (aj-goldie)

on run
    set userDataDir to "/Users/alexgoldsmith/Library/Application Support/Cursor Work"
    set profileName to "Personal Laptop - WORK"
    
    -- Launch Cursor with custom user-data-dir
    do shell script "open -na '/Applications/Cursor.app' --args --user-data-dir " & quoted form of userDataDir & " --profile " & quoted form of profileName
end run


