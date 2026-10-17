# flutter_lynx 常用命令
#
# 本仓库此前没有构建脚本，A2UI 预览链路的 dart-define 由这里统一注入，
# 避免每次手工敲一长串 --dart-define（漏一个就表现为「扫了没反应」，难排查）。
#
# 契约见 koklam-docs features/a2ui-card-qr-open/03_contract.md。

.PHONY: help preview-run preview-run-local preview-build preview-publish

EXAMPLE_DIR := example
BUCKET ?=
PUBLIC_BASE ?=
DEVICE ?=

# 白名单从 PUBLIC_BASE 自动派生，与 `npm run a2ui:preview` 的实际产物路径对齐
# （产物落在 ${PUBLIC_BASE}/preview/<version>/）。手工分别配置两边必然漂移。
ALLOWLIST := $(if $(PUBLIC_BASE),$(PUBLIC_BASE)/preview/,)

help:
	@echo "可用命令:"
	@echo "  make preview-run          - 运行 example App 并注入预览白名单"
	@echo "  make preview-run-local    - 同上，但额外放行明文 http（本机静态服务器联调）"
	@echo "  make preview-build        - 构建 example App 并注入预览白名单"
	@echo "  make preview-publish      - 发布预览产物并打印可扫二维码（需先设 A2UI_* 环境变量）"
	@echo ""
	@echo "必需环境变量:"
	@echo "  PUBLIC_BASE  客户端可见 HTTPS 基址，如 https://bucket.oss-cn-x.aliyuncs.com/<prefix>/a2ui"
	@echo "               白名单会自动派生为 \$$PUBLIC_BASE/preview/"
	@echo "  DEVICE       flutter 设备 ID（run/build 时必填）"

require_public_base:
	@test -n "$(PUBLIC_BASE)" || \
		(echo "✗ 缺少 PUBLIC_BASE。" && \
		 echo "  例：make preview-run PUBLIC_BASE=https://bucket.oss-cn-x.aliyuncs.com/<prefix>/a2ui DEVICE=<id>" && \
		 exit 1)

# 运行 example App，注入预览白名单。
# 不传 A2UI_PREVIEW_ALLOW_HTTP —— 默认只认 https。
preview-run: require_public_base
	@echo "▶ 注入白名单：$(ALLOWLIST)"
	cd $(EXAMPLE_DIR) && flutter run -d "$(DEVICE)" \
		--dart-define=A2UI_PREVIEW_ALLOWED="$(ALLOWLIST)"

# 仅本机联调：额外放行明文 http。
# 绝不可用于评审或发布环境——http 产物可被中间人替换。
preview-run-local: require_public_base
	@echo "▶ 注入白名单：$(ALLOWLIST)（含明文 http，仅限本机联调）"
	cd $(EXAMPLE_DIR) && flutter run -d "$(DEVICE)" \
		--dart-define=A2UI_PREVIEW_ALLOWED="$(ALLOWLIST)" \
		--dart-define=A2UI_PREVIEW_ALLOW_HTTP=true

preview-build: require_public_base
	@echo "▶ 注入白名单：$(ALLOWLIST)"
	cd $(EXAMPLE_DIR) && flutter build \
		--dart-define=A2UI_PREVIEW_ALLOWED="$(ALLOWLIST)"

# 发布预览产物并打印可扫二维码。
# A2UI_OSS_BUCKET / A2UI_PUBLIC_BASE 由 npm 脚本读取，此处只做前置校验与转发。
preview-publish:
	@test -n "$(BUCKET)" || \
		(echo "✗ 缺少 BUCKET（传给 A2UI_OSS_BUCKET 的值，如 oss://<bucket>/<prefix>/a2ui）" && exit 1)
	@test -n "$(PUBLIC_BASE)" || \
		(echo "✗ 缺少 PUBLIC_BASE" && exit 1)
	cd lynx_miniapp_template && A2UI_OSS_BUCKET="$(BUCKET)" A2UI_PUBLIC_BASE="$(PUBLIC_BASE)" \
		npm run a2ui:preview -- --kind $(or $(KIND),confirm)