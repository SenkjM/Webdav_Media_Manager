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

```bash
# 1. 造一个只含站点文件的提交，推到 gh-pages
tmp=$(mktemp -d)
git worktree add --detach "$tmp"
cd "$tmp"
git checkout --orphan gh-pages
git rm -r --cached . >/dev/null
cp "<repo>/site/index.html" "<repo>/site/404.html" "<repo>/site/icon.svg" \
   "<repo>/site/CNAME"      "<repo>/site/.nojekyll" .
git add -A
git commit -m "site: redeploy homepage"
git push origin gh-pages
cd - && git worktree remove "$tmp"

# 2. 确认 Pages 仍然挂在这个分支上（分支曾被删除时需要重新启用）
gh api repos/SenkjM/Webdav_Media_Manager/pages
```

`.github/workflows/pages.yml` 是手动触发的**备用**通道，只在 Pages 的构建源被切成「GitHub Actions」
时可用；当前构建源是 `gh-pages` 分支，所以日常发布走上面的流程。
