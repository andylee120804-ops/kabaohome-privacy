# Release 1.04 真值归档(RELEASE-TRUTH-1.04)

> **此文件是 2026-09-08 事故后建立的可信基线**,防止大更新被误删/误重置后无法复原。
> 目标是:任何时刻都能从本归档 + git tag 快速恢复到与已上架二进制完全一致的源码。

## 已验证的 Release 二进制

| 项 | 值 |
|----|----|
| 文件 | `C:\Users\Andy\Downloads\kabao-default-signed (3).app` |
| 大小 | 1,377,791 字节 |
| SHA256 | `a7ee587e3436ddcbaec38303d6bf6fab769f9deb7dac3f79dc763127adb6a715` |
| 内部版本 | **1.04**(versionCode `1040000`,与 git HEAD 的 commit message「1.05」不同——以二进制为准) |
| 生成时间 | 2026-09-08 01:45 |
| 签名产品 | `release`(signingConfig `kabao`,正式证书,AppGallery 分发) |

> ⚠️ `Downloads/` 下另有 4 个旧版 `.app`(无后缀/`(1)`/`(2)`/`appTest-*`),**不要混淆**。
> 本归档只认 **`(3).app`** 及上述 SHA256。

## 如何验证源码与 Release 真值一致(三集合归零)

源码正确性的判据是:用当前源码构建出的 HAP 反汇编后,与 `(3).app` 反汇编对比,三个集合完全一致:

1. **模块集合**:解包 `.app` → 内嵌 `entry-default.hap` → 再解包得 `ets/modules.abc`,反汇编后取模块名列表
2. **符号集合**:disasm 文本中出现的所有 symbol 名
3. **字符串集合**:disasm 中所有字符串字面量

工具:`node /c/Users/Andy/Downloads/final-accept.cjs`(输出三项归零即通过)。
refresh:`node /c/Users/Andy/Downloads/refresh-final.cjs`。

## 复原步骤(源码丢失/被重置时)

```bash
# 方法 A:git 快照(已入仓)
git fetch origin
git checkout gh-pages
git reset --hard v1.04-release-truth    # tag = 1.04 真值快照 commit
git clean -ndx                           # 先看会删什么,确认再 -fdx

# 方法 B:从 Release .app 反推(仅当 git 快照也不可用时,工作量大,咨询后执行)
# 解包 .app → entry-default.hap → modules.abc → ark_disasm → 逐符号重建
```

## git 快照内容(commit 3c38e0d / tag v1.04-release-truth)

- 78 个文件:AppScope(含 5 密度 app_icon)+ entry app 源码/资源/图标 + 构建配置
- 与 release 二进制**三集合归零**验证通过
- 版本锁定 1.04,未 bump(commit message 写的 1.05 是误标,勿回滚到旧源码)

## 防误删防线(2026-09-08 事故后)

1. **git tag** `v1.04-release-truth`(push 后全仓可用)
2. **PreToolUse hook**:`.claude/scripts/git-guard.cjs` + `.claude/settings.json`
   — 在**工作区有未提交改动**时阻止 `git reset --hard` / `git clean -fdx` / `git checkout .` /
   `git stash drop/clear` 等破坏性命令;工作区干净时放行,不误伤正常操作。
   绕过需显式加 `git-guard-bypass`(会丢改动,慎用)。
3. **.gitignore 加固**:新增 AI 工具目录(.codebuddy/.cursor/.arts 等)、`.npmrc/.ohpmrc`、
   签名备份 `build-profile.json5.bak`、临时产物(hs_err_pid*.log/*.xlsx/contrast_*.py)
4. **安全边界**:`build-profile.json5`/`entry/build-profile.json5`/`agconnect-services.json`/
   `*.p12/.p7b/.cer`/cloud credential JSON **永不提交**(均已 gitignore)

## 铁律(避免重蹈覆辙)

- **执行 `git reset --hard` / `git clean -fdx` / `git checkout .` 前,先确认工作区无未提交改动**
  (用 `git status --porcelain` 看,非空就先 `git add -A && git commit -m "wip snapshot"`)。
- **大版本更新中,每个可工作阶段打一次 commit**(小步提交 > 一次性大提交)。
- **不要信任 commit message 的版本号**——以二进制内部 versionCode 为准。
- 未经三集合归零验证的源码改动,不得声称「与 release 一致」。
