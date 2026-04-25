# U2 — 把 tracking speed 从 1.5 推到 slider max 3.0
defaults write -g com.apple.trackpad.scaling -float 3.0

# U3 — 推超过滑块上限 (5.0 偏夸张，先试 3.5 / 4.0 找甜点)
# defaults write -g com.apple.trackpad.scaling -float 5.0   # 如果 3.0 还不够再放开

# U1 — 启用 3-finger drag + tap，并把 force-click 阈值放到最低（更灵敏）
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -int 2
defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -bool true
defaults write com.apple.AppleMultitouchTrackpad FirstClickThreshold -int 0
defaults write com.apple.AppleMultitouchTrackpad SecondClickThreshold -int 0

# 同步给 BT trackpad 域（macOS 两边都读）
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerTapGesture -int 2
