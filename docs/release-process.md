# iOS 源码发布流程

亦可 YK iOS 的 GitHub Release 从 `main` 打标签产生。首次公开版本是 `YK-v1.0.0-alpha.1`。

**预发布（`alpha` / `beta` / `rc`）只含源码。** 不要上传 ipa、xcarchive、dSYM 或其它二进制安装包。GitHub 会自动附带该标签对应的 Source code zip / tar.gz，这就够了。

## 版本号

标签必须匹配：

```text
YK-v<major>.<minor>.<patch>
YK-v<major>.<minor>.<patch>-alpha.<n>
YK-v<major>.<minor>.<patch>-beta.<n>
YK-v<major>.<minor>.<patch>-rc.<n>
```

示例：`YK-v1.0.0-alpha.1`、`YK-v1.0.0-rc.1`、`YK-v1.0.0`。

- `YK-` 前缀表示这是亦可 YK 的发行标签，避免和内部 Xcode `MARKETING_VERSION` 混用。
- 含 `alpha` / `beta` / `rc` 的标签会创建 **pre-release**。
- 不含预发布后缀的标签创建正式 Release，当前阶段同样只发源码，除非发布清单里明确写了二进制方案。

Xcode 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 是安装包显示版本，可以和 GitHub 标签并行演进；改安装包版本要在发版说明里写清楚。

## 发一版要做的事

1. 从已核验的 `origin/main` 拉出 `yukiryou/` 分支。
2. 在 [`CHANGELOG.md`](../CHANGELOG.md) 顶部增加该版本一节。
3. 新增 [`docs/releases/<tag>.md`](releases/)，写给 GitHub Release 看的说明。**不要在文件开头再写一级标题**——GitHub 页面顶部已经有发行标题，正文从第一段开始即可。Alpha 要写清：只发源码、覆盖哪些功能、已知限制。
4. 如有需要，更新 [`README.md`](../README.md) 里的「当前公开版本」。
5. 合入 `main` 并推送。确认 `origin/main` 已包含发版提交。
6. 工作区干净、当前就在 `main` 上时执行：

```bash
bash scripts/create-source-release.sh YK-v1.0.0-alpha.1
```

脚本会：

- 检查标签格式、工作区干净、当前分支是 `main` 且包含 `origin/main`
- 检查 `CHANGELOG.md` 和 `docs/releases/<tag>.md` 存在
- 创建附注标签并推送
- 用 `gh release create` 建 Release，预发布加 `--prerelease`
- **不附加任何本地文件**，因此不会把安装包传上去

7. 打开 GitHub Release 页，确认只有 Source code 两个自动附件，标题和说明正确。

## 禁止事项

- 不要在 GitHub 网页上手工上传 ipa / xcarchive 到 alpha、beta、rc。
- 不要从脏工作区或非 `main` 提交打发版标签。
- 不要改已发布标签指向的提交。修错就发下一个版本号。
- 不要跳过 `docs/releases/<tag>.md`。没有说明文件，脚本会失败。
- 公开 README、Changelog 和 Release 说明不要链接私有仓库、私有 Actions 或未公开的内部项目地址。

## 以后若要发安装包

稳定版若要附带编译产物，需要另写二进制发布清单（签名、公证、产物哈希、与源码标签对应关系），并改脚本 / workflow。在那之前，所有 GitHub Release 都按源码发布处理。
