# 项目主页

静态介绍页，面向用户的产品页，不是应用本体。

- 页面：[`index.html`](./index.html)
- 图标：[`icon.svg`](./icon.svg)
- 自定义域名：[`CNAME`](./CNAME) → `wdmm.senkjm.top`

## 发布

1. 源码在本目录，随 `main` 维护；改完网页先提交这一份源码。
2. GitHub Pages 从 **`gh-pages` 分支根目录**发布。`gh-pages` 是部署产物分支，不是源码：根目录只放
   `index.html` / `404.html` / `icon.svg` / `CNAME` / `.nojekyll`，本 `README.md` 不上线。
   （`gh-pages` 分支被删掉后 Pages 会整个 404 —— 域名下返回 “There isn't a GitHub Pages site here.”，
   仓库设置里的 Pages 配置也会一并消失，需要重建分支后重新启用。）
3. Cloudflare DNS 将 `wdmm.senkjm.top` CNAME 到 `senkjm.github.io`（DNS only，便于 GitHub 签发证书）。

### 重新部署（`site/` → `gh-pages`）

`gh-pages` 是**部署产物分支**：根目录直接对应当前 `site/` 里的站点文件，本 `README.md` 不上线。
用 git 底层命令从 `site/` 的 blob 直接造一个无历史的提交，不动工作区：

```bash
# 1. 确认 site/ 已提交，记下当前提交
h=$(git rev-parse HEAD)

# 2. 用 site/ 里要上线的 5 个文件组装 gh-pages 根 tree（只含 LF 路径，别用 PowerShell 管道拼）
printf '100644 blob %s\t%s\n' \
  "$(git rev-parse $h:site/index.html)" index.html \
  "$(git rev-parse $h:site/404.html)"  404.html \
  "$(git rev-parse $h:site/icon.svg)"  icon.svg \
  "$(git rev-parse $h:site/CNAME)"     CNAME \
  "$(git rev-parse $h:site/.nojekyll)" .nojekyll > /tmp/entries
tree=$(git mktree < /tmp/entries)

# 3. 造提交并指向 gh-pages
printf 'site: deploy homepage\n\nGenerated from site/ on main (%s).\n' "$h" > /tmp/msg
commit=$(git commit-tree "$tree" < /tmp/msg)
git update-ref refs/heads/gh-pages "$commit"
git push <remote> refs/heads/gh-pages:refs/heads/gh-pages

# 4. 核验
gh api repos/<owner>/<repo>/pages                 # source.branch 应为 gh-pages、status 为 built
curl -sI https://wdmm.senkjm.top/                 # 200
```

注意：用 PowerShell 的 `$entries | git mktree` 会把 CRLF 带进 tree 记录，生成名为 `".nojekyll\r"`
的条目、`.nojekyll` 实际缺失；要用 `cmd /c "git mktree < file"` 或直接在 Bash 里跑。

`.github/workflows/pages.yml` 是手动触发的**备用**通道（把 `site/` 作为 Actions Pages 源再发一次），
只在 Pages 的构建源被切成「GitHub Actions」时才用得上；当前构建源是 `gh-pages` 分支。
