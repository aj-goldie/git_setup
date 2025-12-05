-- Cursor Personal.app
-- Launches Cursor with the default user data directory for personal account (aj-goldie)
-- This keeps personal GitHub authentication separate from work (bai-admin)

on run
    set userDataDir to "/Users/alexgoldsmith/Library/Application Support/Cursor"
    set profileName to "Personal Laptop - PERSONAL"
    
    -- Launch Cursor with explicit user-data-dir (default location)
    do shell script "open -na '/Applications/Cursor.app' --args --user-data-dir " & quoted form of userDataDir & " --profile " & quoted form of profileName
end run