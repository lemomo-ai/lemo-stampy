# 小章 安全问题报告 · Stampy security policy

[中文](#中文) · [English](#english)

## 中文

### 怎么报告

发现安全问题，请不要开公开 issue。在本仓库的 **Security** 页点 **Report a vulnerability** 私下提交（[直达链接](https://github.com/lemomo-ai/lemo-stampy/security/advisories/new)）。写上小章的版本号、macOS 版本、怎么复现。

### 哪些算安全问题

- 你的文件、页面内容或盖章记录被发到 Mac 以外。小章只在你点“检查更新…”时读取公开的 version.json，别的时候不联网。
- 原件被改动，或者副本存到了你没选的地方。
- 加了密码的文件，密码被保存下来，或者盖好的副本没有用同一个密码锁上。
- 辅助功能权限被用来做看预览里是哪份文件、你点在哪儿以外的事。
- 下载到的安装包签名或公证不对。

盖得不好看、功能 bug 照常开 issue。

### 支持的版本

只修最新发布的版本。修好后发新版，在发布说明里写清楚修了什么。

## English

### How to report

Please don't open a public issue for a security problem. Report it privately: on this repo's **Security** page, click **Report a vulnerability** ([direct link](https://github.com/lemomo-ai/lemo-stampy/security/advisories/new)). Include the Stampy version, your macOS version, and how to reproduce it.

### What counts

- Your files, page contents or stamp history leaving your Mac. Stampy only reads the public version.json when you click "Check for Updates…", and is offline the rest of the time.
- Your original file being changed, or a copy being saved somewhere you didn't choose.
- For a password-protected file: the password being stored, or the stamped copy not being locked with the same password.
- The Accessibility permission being used for anything beyond seeing which file is open in Preview and where you clicked.
- A downloaded installer with a wrong signature or notarization.

Open a normal issue for stamps that look wrong and for feature bugs.

### Supported versions

Only the latest release gets fixes. A fix ships as a new release, and the release notes say what was fixed.
