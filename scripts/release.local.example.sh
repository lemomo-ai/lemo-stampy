# 抄成 scripts/release.local.sh（不进仓库）再填，release.sh 会读它。
# 证书全名在「钥匙串访问」里看，或运行：security find-identity -v -p codesigning
TEAM_ID="ABCDE12345"
SIGNING_IDENTITY="Developer ID Application: Your Name (ABCDE12345)"
# 公证凭据：xcrun notarytool store-credentials <NOTARY_PROFILE> --apple-id <APPLE_ID> --team-id <TEAM_ID>
NOTARY_PROFILE="my-notary"   # 也可以写好几个候选，空格隔开，用第一个能用的
APPLE_ID="you@example.com"
