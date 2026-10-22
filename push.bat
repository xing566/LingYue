@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo 正在推送到 GitHub 仓库 j45byjw6gj-cell/LingYue ...
git remote remove origin >nul 2>&1
git remote add origin https://github.com/j45byjw6gj-cell/LingYue.git
git push -u origin main
if errorlevel 1 (
    echo.
    echo [失败] 推送未完成。可能原因：
    echo   - 弹出的 GitHub 登录窗口未授权
    echo   - 未登录 GitHub，或仓库名/用户名写错
    echo 请确认后重试。
    pause
    exit /b 1
)
echo.
echo [成功] 代码已推送，GitHub Actions 会自动开始编译。
echo 等 1-3 分钟后，到仓库 Actions 页下载 LingYue-ipa.zip。
pause
