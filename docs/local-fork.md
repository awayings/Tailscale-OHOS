# 本地分叉维护说明

本仓库是 `awayings/Tailscale-OHOS` 的本地分叉，只用于自己设备上的小改动，**不发布到应用市场**。这份说明记录怎么长期低成本地维护它。

## 为什么不上架

- 当前签名是**调试证书 + 调试 Profile**（`~/.ohos/config/default_Tailscale-OHOS__*.p7b`，`type: debug`），华为规定调试签名仅用于真机调试，不能用于上架发布。
- 该 Profile 的 `debug-info.device-ids` 只绑定了一台设备：`67B908EB269CAB3EE6CD23AC30D5612F4106E2C7B0D46841E9EC5ECC1BE64623`。这个 HAP 装不到别的机器上。
- 上架还要发布证书 / 发布 Profile、实名认证、APP 备案、VPN 类应用资质，成本远超一个自用小改动。

## 分支策略

| 引用 | 含义 |
|---|---|
| `origin` | `git@github.com:awayings/Tailscale-OHOS.git`（上游） |
| `origin/main` | 上游主线，基准提交 `fd49406` |
| `dev`（当前） | 本地分叉，`27773c5 fix.`：自定义 DNS + 私有化 bundleName |

同步上游（建议每隔一段时间做一次，避免分叉越拉越远）：

```bash
git fetch origin
git merge origin/main          # 在 dev 上；有冲突时优先保留本地私有化部分
scripts/dev-install.sh         # 合并后重新构建装机
```

## 日常使用

```bash
scripts/dev-install.sh              # 快速路径：只重编 ArkTS，装到 USB 真机
scripts/dev-install.sh --full       # 改了 native/Go 代码时用，会跑 scripts/build.sh
scripts/dev-install.sh --launch     # 装完顺手拉起应用
scripts/dev-install.sh --no-install # 只构建不装机
```

脚本会自己从 `AppScope/app.json5` 读取 bundleName，不要在任何脚本里再写死包名。装完仍需手动完成 Tailscale 浏览器登录、点「连接」、并在系统 VPN 授权框点允许。

单元测试：`node --test scripts/*.mjs`（应为 52/52）。

## 签名与设备

- `build-profile.json5` 被 `.gitignore` 排除（`/build-profile.json5`），含本地证书路径和密码，**不要提交**；模板见 `build-profile.example.json5`。
- 调试证书和 Profile 有效期至 **2027-11-06**，到期前在 AGC 重新申请并替换 `~/.ohos/config/` 下对应文件。
- 想给第二台设备装：在 AGC「设备」里注册它的 UDID（`hdc shell bm get --udid`），编辑调试 Profile 把设备加进去，重新下载 `.p7b` 并重签构建。一个账号每年最多注册 100 台设备，年内删除仍占额度。
- 真要分发给别人但不上架，可考虑 AGC 的 AppTest 邀请测试 / 指定设备发布，但那需要换成发布证书并完成备案。

## 不要带进上游 PR 的改动

这些是本地私有化或为修本地改名问题而生的，提 PR 时必须剔除：

- `AppScope/app.json5` 的 `bundleName`（本地为 `io.github.tailscale.homer`）
- `entry/src/main/ets/services/AppIdentity.ets` 及引用它的 4 处运行时代码、`scripts/test-bundle-name.mjs`、8 个 `scripts/device-*.ps1` 探针
- `build-profile.json5`、`.clangd`、`hvigor/hvigor-config.json5`、`scripts/build-go.sh`、`.gitignore` 里的 `.workbuddy/`
- `scripts/dev-install.sh` 与本文档

功能本身（自定义 DNS）应单独提到上游，见下方 PR 工作树。

## PR 工作树

已准备独立工作树，与 `dev` 互不干扰：

| 项 | 值 |
|---|---|
| 路径 | `/Users/edy/projects/me/tech/Tailscale-OHOS-pr` |
| 分支 | `feat/custom-dns-settings`（基于 `origin/main`） |
| 内容 | 仅 DNS 功能 + 测试 + README/docs 说明，9 个文件 |
| PR 描述草稿 | `.workbuddy/PR_DESCRIPTION.md` |

验证状态：`node --test scripts/*.mjs` 47/47 通过；DevEco Studio `assembleHap` **BUILD SUCCESSFUL**（CompileArkTS / PackageHap / SignHap 全过）。改动尚未 commit、未 push。确认 diff 后自行提交并推送到自己的 fork 再开 PR。

在 PR 工作树里做本地编译时，需要补上被 `.gitignore` 排除的本地产物：`build-profile.json5`、`native/go_bridge/dist/arm64-v8a/libtailscale_go.{h,so}`、`entry/oh_modules/@tailscale/common` 软链（指向 `../../../common`）。这些都不会进入 PR。
