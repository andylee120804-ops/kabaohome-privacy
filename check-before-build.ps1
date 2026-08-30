# ============================================
# 卡宝Home 发布前自动检查脚本 (Windows PowerShell)
# 使用方式: .\check-before-build.ps1
# ============================================

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "🔍 卡宝Home - 发布前自动检查" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$ErrorCount = 0
$WarnCount = 0

function Check-File {
    param([string]$Path)
    if (Test-Path $Path) {
        Write-Host "✅ $Path" -ForegroundColor Green
    } else {
        Write-Host "❌ $Path (缺失)" -ForegroundColor Red
        script:ErrorCount++
    }
}

function Check-Dir {
    param([string]$Path)
    if (Test-Path $Path) {
        Write-Host "✅ $Path\" -ForegroundColor Green
    } else {
        Write-Host "❌ $Path\ (缺失)" -ForegroundColor Red
        script:ErrorCount++
    }
}

Write-Host "📁 1. 检查项目结构..." -ForegroundColor Yellow
Write-Host "----------------------------------------"
Check-File "build-profile.json5"
Check-File "oh-package.json5"
Check-File "hvigorfile.ts"
Check-Dir "entry/src/main/ets"
Check-Dir "entry/src/main/ets/pages"
Check-Dir "entry/src/main/ets/viewmodel"
Check-Dir "entry/src/main/ets/service"
Check-Dir "entry/src/main/ets/model"
Check-Dir "entry/src/main/ets/components"
Check-Dir "entry/src/main/resources"

Write-Host ""
Write-Host "📄 2. 检查核心文件..." -ForegroundColor Yellow
Write-Host "----------------------------------------"
Check-File "entry/src/main/module.json5"
Check-File "entry/src/main/ets/entryability/EntryAbility.ets"
Check-File "entry/src/main/ets/common/Constants.ets"
Check-File "entry/src/main/ets/common/Utils.ets"
Check-File "entry/src/main/ets/service/LocalDbService.ets"
Check-File "entry/src/main/ets/service/AuthService.ets"
Check-File "entry/src/main/ets/pages/Index.ets"
Check-File "entry/src/main/ets/pages/FamilySetupPage.ets"
Check-File "entry/src/main/ets/pages/SettingsPage.ets"

Write-Host ""
Write-Host "📱 3. 检查页面文件..." -ForegroundColor Yellow
Write-Host "----------------------------------------"
$Pages = @("Index", "LoginPage", "PeriodPage", "HealthPage", "KidsPage", "ReminderPage", 
           "NotificationCenterPage", "LocationPage", "AlbumPage", "ShoppingPage", 
           "MemoPage", "FamilySetupPage", "SettingsPage", "AccountingPage",
           "PreviewPage", "MapPickerPage")

foreach ($page in $Pages) {
    Check-File "entry/src/main/ets/pages/${page}.ets"
}

Write-Host ""
Write-Host "🧩 4. 检查ViewModel..." -ForegroundColor Yellow
Write-Host "----------------------------------------"
$Viewmodels = @("FamilyViewModel", "PeriodViewModel", "HealthViewModel", 
                "KidsViewModel", "ModuleManager", "AccountingViewModel")

foreach ($vm in $Viewmodels) {
    Check-File "entry/src/main/ets/viewmodel/${vm}.ets"
}

Write-Host ""
Write-Host "💾 5. 检查Model..." -ForegroundColor Yellow
Write-Host "----------------------------------------"
$Models = @("BaseRecord", "Family", "FamilyMember", "FamilyInvitation", 
            "PeriodRecord", "Medication", "HealthMetric", "KidEvent", 
            "Reminder", "ShoppingItem", "Photo", "Memo", "AccountingRecord")

foreach ($model in $Models) {
    Check-File "entry/src/main/ets/model/${model}.ets"
}

Write-Host ""
Write-Host "🔧 6. 检查组件..." -ForegroundColor Yellow
Write-Host "----------------------------------------"
$Components = @("TabBar", "CalendarView", "CardItem", "EmptyState", 
                "MemberTag", "VisibilityPicker", "TrendChart")

foreach ($comp in $Components) {
    Check-File "entry/src/main/ets/components/${comp}.ets"
}

Write-Host ""
Write-Host "⚙️ 7. 检查资源文件..." -ForegroundColor Yellow
Write-Host "----------------------------------------"
Check-File "entry/src/main/resources/base/profile/main_pages.json"
Check-File "entry/src/main/resources/base/element/string.json"

Write-Host ""
Write-Host "🔐 8. 检查签名配置..." -ForegroundColor Yellow
Write-Host "----------------------------------------"
$content = Get-Content "build-profile.json5" -Raw
if ($content -match '"signingConfigs": \[\]') {
    Write-Host "⚠️  未配置签名证书 (调试模式可忽略)" -ForegroundColor DarkYellow
    $WarnCount++
} else {
    Write-Host "✅ 已配置签名" -ForegroundColor Green
}

Write-Host ""
Write-Host "📊 9. 统计代码量..." -ForegroundColor Yellow
Write-Host "----------------------------------------"
$etsFiles = Get-ChildItem -Path "entry/src/main/ets" -Filter "*.ets" -Recurse
$etsCount = $etsFiles.Count
$totalLines = ($etsFiles | ForEach-Object { Get-Content $_.FullName }).Count
Write-Host "📄 ETS文件数: $etsCount"
Write-Host "📝 总代码行数: $totalLines"

Write-Host ""
Write-Host "=========================================="
if ($ErrorCount -eq 0) {
    Write-Host "✅ 检查通过！可以开始构建和调试" -ForegroundColor Green
} else {
    Write-Host "❌ 发现 $ErrorCount 个错误，请先修复" -ForegroundColor Red
}
if ($WarnCount -gt 0) {
    Write-Host "⚠️  $WarnCount 个警告" -ForegroundColor DarkYellow
}
Write-Host "=========================================="
Write-Host ""
Write-Host "🚀 下一步操作：" -ForegroundColor Cyan
Write-Host "   1. 用 DevEco Studio 打开项目: c:\Users\Andy\kabao"
Write-Host "   2. File → Project Structure → 配置签名"
Write-Host "   3. 连接设备/模拟器"
Write-Host "   4. 点击 ▶ 运行按钮开始调试"
Write-Host ""
