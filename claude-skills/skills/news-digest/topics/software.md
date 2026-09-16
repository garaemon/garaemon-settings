---
emoji: "💻"
label_ja: "ソフトウェアニュース"
history_file: "software-news.md"
history_limit: 100
scope_ja: "クラウド/SaaS の障害、言語ランタイム・フレームワーク・ライブラリ・開発ツール・インフラ系プロダクトのリリース、セキュリティ脆弱性、および Hacker News 上位や SNS 拡散など実際に話題になっている技術ブログ・解説記事"
exclude_ja: "AI 関連のニュースは news-digest ai で扱うため除外"
queries:
  - "software news today {today}"
  - "cloud outage incident today {today}"
  - "major framework library release {today}"
  - "developer tool release {today}"
  - "programming language release update {today}"
  - "security vulnerability patch CVE {today}"
  - "top hacker news posts {today}"
categories:
  - emoji: "🚨"
    label_ja: "障害・インシデント"
    hint: "AWS, GCP, Azure, Cloudflare, GitHub, Vercel などクラウド/SaaS の障害・メンテ"
  - emoji: "📦"
    label_ja: "リリース・アップデート"
    hint: "Python, Node.js, Rust, Go などの言語ランタイム、React, Next.js, Django などのフレームワーク・ライブラリのリリース"
  - emoji: "🛠️"
    label_ja: "開発ツール・インフラ"
    hint: "VS Code, Neovim, Git, Docker, Kubernetes, Terraform, GitHub Actions など IDE/CLI/DevOps/インフラ系プロダクトの更新"
  - emoji: "🔐"
    label_ja: "セキュリティ"
    hint: "CVE, パッチ, 脆弱性"
  - emoji: "📝"
    label_ja: "話題の記事・ブログ"
    hint: "Hacker News 上位、企業/個人エンジニアの技術ブログ、SNS で拡散している技術解説記事など、実際に話題になっているもの。単なるニュースサイトの転載は除外"
  - emoji: "🏢"
    label_ja: "企業・OSS 動向"
    hint: "主要 IT 企業や OSS 財団の重要ニュース"
---

# Software news topic

Cloud, SaaS, language/framework releases, developer tools,
infrastructure, security, and trending engineering blog posts (Hacker
News top stories, widely-shared technical write-ups). Explicitly
excludes AI — that's the `ai` topic.
