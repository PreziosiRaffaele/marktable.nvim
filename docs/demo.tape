# Demo GIF for the README.
# Regenerate from the repository root with: vhs docs/demo.tape

Output docs/demo.gif

Require nvim

Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 18
Set Width 1200
Set Height 700
Set Padding 20
# Neovim's default dark colors, so the padding matches the editor background.
Set Theme { "name": "nvim-default", "background": "#14161b", "foreground": "#e0e2ea", "cursor": "#e0e2ea", "selection": "#4f5258", "black": "#07080d", "red": "#ffc0b9", "green": "#b3f6c0", "yellow": "#fce094", "blue": "#a6dbff", "magenta": "#ffcaff", "cyan": "#8cf8f7", "white": "#eef1f8", "brightBlack": "#4f5258", "brightRed": "#ffc0b9", "brightGreen": "#b3f6c0", "brightYellow": "#fce094", "brightBlue": "#a6dbff", "brightMagenta": "#ffcaff", "brightCyan": "#8cf8f7", "brightWhite": "#eef1f8" }
Set TypingSpeed 70ms
Set Framerate 20

Hide
Type "export ROOT=$PWD PS1='$ ' && cd $(mktemp -d) && clear"
Enter
Type "cat > decisions.md <<'EOF'"
Enter
Type "# Storage for the sync service"
Enter
Enter
Type "Decision log from the storage spike, one row per option."
Enter
Enter
Type "| Option | Description | Recommendation |"
Enter
Type "| --- | --- | --- |"
Enter
Type "| SQLite | Embedded database in a single file.<br>No server to run. | Preferred |"
Enter
Type "| Postgres | Full relational server with strong tooling. | Fallback |"
Enter
Type "| JSON files | One file per record, easy to diff. | Avoid |"
Enter
Type "EOF"
Enter
Type `nvim --clean --cmd "set rtp^=$ROOT" -c "nnoremap K <Cmd>MarktableRowView<CR>" -c "set noshowcmd" +7 decisions.md`
Enter
Sleep 1.5s
Show

# Peek at the row under the cursor.
Sleep 1s
Type "K"
Sleep 1.5s

# Focus the view and browse.
Type "K"
Sleep 1s
Type "]r"
Sleep 1.2s
Type "]r"
Sleep 1.2s
Type "[r"
Sleep 0.6s
Type "[r"
Sleep 1.2s

# Append to the recommendation and save.
Type "G"
Sleep 0.6s
Type "A"
Sleep 0.8s
Type " for v1"
Sleep 0.5s
Escape
Sleep 0.5s
Type ":w"
Sleep 0.4s
Enter
Sleep 1.5s

# Next row: add a line to the description and save.
Type "]r"
Sleep 1.2s
Type "5G"
Sleep 0.6s
Type "o"
Sleep 0.8s
Type "Needs a managed instance."
Sleep 0.5s
Escape
Sleep 0.5s
Type ":w"
Sleep 0.4s
Enter
Sleep 1.5s

# Close the view and look at the updated table.
Type "q"
Sleep 2.5s
