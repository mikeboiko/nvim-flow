Output nvim-flow-demo.gif
Set Shell "bash"
Set FontFamily "Hack Nerd Font Mono"
Set FontSize 18
Set Width 1000
Set Height 700
Set Padding 20
Set TypingSpeed 70ms

Type "cd ~/demo"
Enter
Sleep 800ms

Type "nvim test.py"
Enter
Sleep 2s

Type ":FlowRun"
Enter
Sleep 3s

Type "gg"
Sleep 300ms
Type "j"
Sleep 300ms
Type " db"
Sleep 1s

Type ":FlowDebug"
Enter
Sleep 6s

Type ":qa!"
Enter
