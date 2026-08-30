#!/bin/bash
# ============================================
# 卡宝Home 发布前自动检查脚本
# 使用方式: bash check-before-build.sh
# ============================================

echo "=========================================="
echo "🔍 卡宝Home - 发布前自动检查"
echo "=========================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERROR_COUNT=0
WARN_COUNT=0

check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✅ $1${NC}"
    else
        echo -e "${RED}❌ $1 (缺失)${NC}"
        ((ERROR_COUNT++))
    fi
}

check_dir() {
    if [ -d "$1" ]; then
        echo -e "${GREEN}✅ $1/${NC}"
    else
        echo -e "${RED}❌ $1/ (缺失)${NC}"
        ((ERROR_COUNT++))
    fi
}

echo "📁 1. 检查项目结构..."
echo "----------------------------------------"
check_file "build-profile.json5"
check_file "oh-package.json5"
check_file "hvigorfile.ts"
check_dir "entry/src/main/ets"
check_dir "entry/src/main/ets/pages"
check_dir "entry/src/main/ets/viewmodel"
check_dir "entry/src/main/ets/service"
check_dir "entry/src/main/ets/model"
check_dir "entry/src/main/ets/components"
check_dir "entry/src/main/resources"

echo ""
echo "📄 2. 检查核心文件..."
echo "----------------------------------------"
check_file "entry/src/main/module.json5"
check_file "entry/src/main/ets/entryability/EntryAbility.ets"
check_file "entry/src/main/ets/common/Constants.ets"
check_file "entry/src/main/ets/common/Utils.ets"
check_file "entry/src/main/ets/service/LocalDbService.ets"
check_file "entry/src/main/ets/service/AuthService.ets"
check_file "entry/src/main/ets/pages/Index.ets"
check_file "entry/src/main/ets/pages/FamilySetupPage.ets"
check_file "entry/src/main/ets/pages/SettingsPage.ets"

echo ""
echo "📱 3. 检查页面文件..."
echo "----------------------------------------"
PAGES=("Index" "LoginPage" "PeriodPage" "HealthPage" "KidsPage" "ReminderPage" 
       "NotificationCenterPage" "LocationPage" "AlbumPage" "ShoppingPage" 
       "MemoPage" "FamilySetupPage" "SettingsPage" "AccountingPage"
       "PreviewPage" "MapPickerPage")

for page in "${PAGES[@]}"; do
    check_file "entry/src/main/ets/pages/${page}.ets"
done

echo ""
echo "🧩 4. 检查ViewModel..."
echo "----------------------------------------"
VIEWMODELS=("FamilyViewModel" "PeriodViewModel" "HealthViewModel" 
            "KidsViewModel" "ModuleManager" "AccountingViewModel")

for vm in "${VIEWMODELS[@]}"; do
    check_file "entry/src/main/ets/viewmodel/${vm}.ets"
done

echo ""
echo "💾 5. 检查Model..."
echo "----------------------------------------"
MODELS=("BaseRecord" "Family" "FamilyMember" "FamilyInvitation" 
        "PeriodRecord" "Medication" "HealthMetric" "KidEvent" 
        "Reminder" "ShoppingItem" "Photo" "Memo" "AccountingRecord")

for model in "${MODELS[@]}"; do
    check_file "entry/src/main/ets/model/${model}.ets"
done

echo ""
echo "🔧 6. 检查组件..."
echo "----------------------------------------"
COMPONENTS=("TabBar" "CalendarView" "CardItem" "EmptyState" 
            "MemberTag" "VisibilityPicker" "TrendChart")

for comp in "${COMPONENTS[@]}"; do
    check_file "entry/src/main/ets/components/${comp}.ets"
done

echo ""
echo "⚙️ 7. 检查资源文件..."
echo "----------------------------------------"
check_file "entry/src/main/resources/base/profile/main_pages.json"
check_file "entry/src/main/resources/base/element/string.json"

echo ""
echo "🔐 8. 检查签名配置..."
echo "----------------------------------------"
if grep -q '"signingConfigs": \[\]' build-profile.json5; then
    echo -e "${YELLOW}⚠️  未配置签名证书 (调试模式可忽略)${NC}"
    ((WARN_COUNT++))
else
    echo -e "${GREEN}✅ 已配置签名${NC}"
fi

echo ""
echo "📊 9. 统计代码量..."
echo "----------------------------------------"
ETS_COUNT=$(find entry/src/main/ets -name "*.ets" | wc -l)
TOTAL_LINES=$(find entry/src/main/ets -name "*.ets" -exec cat {} \; | wc -l)
echo "📄 ETS文件数: ${ETS_COUNT}"
echo "📝 总代码行数: ${TOTAL_LINES}"

echo ""
echo "=========================================="
if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ 检查通过！可以开始构建和调试${NC}"
else
    echo -e "${RED}❌ 发现 ${ERROR_COUNT} 个错误，请先修复${NC}"
fi
if [ $WARN_COUNT -gt 0 ]; then
    echo -e "${YELLOW}⚠️  ${WARN_COUNT} 个警告${NC}"
fi
echo "=========================================="
echo ""
echo "🚀 下一步操作："
echo "   1. 用 DevEco Studio 打开项目: c:/Users/Andy/kabao"
echo "   2. File → Project Structure → 配置签名"
echo "   3. 连接设备/模拟器"
echo "   4. 点击 ▶ 运行按钮开始调试"
echo ""
