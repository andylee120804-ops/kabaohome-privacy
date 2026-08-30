# Hyper-V 手动启用指南 - 卡宝Home开发环境

## 如果 bat 脚本执行失败，请按此文档手动操作

---

## 步骤1：打开管理员PowerShell

1. 按 `Win + X` 键
2. 选择 **"Windows PowerShell (管理员)"** 或 **"终端(管理员)"**
3. 如果弹出UAC确认框，点击 **"是"**

---

## 步骤2：依次执行以下命令

### 命令1：检查Hyper-V状态
```powershell
Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All | Select-Object FeatureName, State
```

**预期输出示例：**
```
FeatureName                    State
------------                    -----
Microsoft-Hyper-V-All          Disabled
```
如果显示 `Disabled` 说明未启用，需要继续下面的步骤。

---

### 命令2：启用Hyper-V（核心）
```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart
```

**等待时间：** 约2-5分钟  
**预期输出末尾：** `Operation completed successfully` 或 `在线重新启动操作已完成`

---

### 命令3：启用虚拟机平台
```powershell
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
```

---

### 命令4：启用Hypervisor平台
```powershell
Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -NoRestart
```

---

### 命令5：重启电脑
```powershell
Restart-Computer
```

或者手动重启：开始菜单 → 电源 → 重启

---

## 重启后验证

电脑重启完成后，再次打开PowerShell运行：

```powershell
Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All | Select-Object State
```

如果输出显示 `Enabled` 则说明成功！

---

## 常见问题排查

### 问题1：命令显示"找不到 cmdlet"
**原因：** PowerShell版本过低或系统不完整
**解决：** 尝试使用DISM命令（见下方）

---

### 问题2：显示"请求的操作需要提升"
**原因：** 没有使用管理员权限
**解决：** 确保右键选择"以管理员身份运行"

---

### 问题3：显示"无法完成请求"或错误代码
**可能原因：**
- CPU不支持虚拟化（但你的CPU支持，所以不太可能是这个）
- BIOS中虚拟化未开启
- Windows版本限制

**解决方案：使用DISM命令（更通用）**

---

## 备用方案：使用DISM命令（如果上面命令都失败）

在管理员PowerShell中运行：

```powershell
# 方式1: 使用 DISM (适用于所有Windows版本)
dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V-All /all /norestart

# 如果上面成功，继续执行：
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

dism.exe /online /enable-feature /featurename:HypervisorPlatform /all /norestart

# 最后重启
shutdown /r /t 0
```

---

## 如果所有方法都失败？

### 选项1：BIOS开启虚拟化（进阶）

1. 重启电脑
2. 开机时按 `F2` / `Del` / `F10` / `F12` （不同品牌按键不同）
   - 华硕/联想: F2 或 Del
   - 戴尔: F12
   - HP: F10 或 Esc
3. 找到以下选项并设置为 **Enabled**:
   - Intel VT-x 或 AMD-V
   - Virtualization Technology
   - SVM Mode
   - Intel Virtualization Technology
4. 保存退出 (通常是 F10)
5. 回到Windows后重试上面的命令

---

### 选项2：放弃本地模拟器，改用真机或远程模拟器

详见主指南中的方案二和方案三。

---

## 成功标志

✅ 启用成功后，你应该能看到：

1. **开始菜单新增应用：**
   - Hyper-V Manager
   - Quick Create (快速创建)

2. **DevEco Studio能正常启动模拟器**

3. **任务管理器 → 性能标签页显示 "虚拟化: 已启用"**

---

祝你好运！如果还有问题，请把完整错误信息发给AI助手。
