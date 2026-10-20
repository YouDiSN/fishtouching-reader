# 开发社区插件

社区插件是 **UTF-8 JSON 数据规则**，不是可执行脚本。所有外部安装的插件均标记为“社区插件”，作者字段由发布者填写，不代表网站官方或身份认证。TXT、PDF、EPUB 是宿主内置官方插件。

> 当前发布版本暂时隐藏社区插件列表、安装和网址导入入口。官方 TXT、PDF、EPUB 插件默认启用，仍可在“管理导入插件…”中管理。以下社区安装步骤仅供开发者在本地开启入口后验证，不表示已面向用户开放。

## 支持范围

- v1：为本地纯文本新增扩展名，使用宿主 TXT 解码器。
- v2：选择宿主已有的网站适配器 `fanqie`、`qimao`、`qidian`。规则不能自定义域名、选择器、脚本、请求头、Cookie 或接口。
- 新增网站解析逻辑必须修改 `Resources/web-plugins.js` 并经过代码审查、测试和应用更新，不能靠下载插件执行任意代码。当前不是通用爬虫插件 SDK。
- ZIP 只是清单的分发方式，不包含程序、依赖或小说。

## 清单格式

JSON 不允许注释、尾逗号或未知字段；清单不超过 64 KiB。字段使用下列英文键，字符串内容可以是中文。

```json
{
  "schemaVersion": 2,
  "id": "community.my-fanqie",
  "name": "我的番茄书源",
  "version": "1.0.0",
  "author": "你的名字",
  "description": "实验性社区适配器，非网站官方；仅提取公开可解析正文。",
  "extensions": [],
  "parser": "website",
  "adapter": "fanqie"
}
```

| 字段 | 约束 |
| --- | --- |
| `schemaVersion` | 本地文本为 `1`，网站为 `2` |
| `id` | `community.` 开头；其后为 1–63 个小写字母、数字、点、横线，首字符为字母或数字；更新时保持不变 |
| `name` | 非空，最多 60 字符 |
| `version` | 三段数字，如 `1.0.0`，每段 1–4 位；不支持预发布后缀 |
| `author` | 非空，最多 80 字符；不要填写他人身份 |
| `description` | 最多 300 字符；v2 不可为空，说明限制和来源 |
| `extensions` | v2 必须是 `[]`；v1 为 1–8 个不带点的小写后缀，每项 1–10 位，字母开头；不可重复、占用官方 TXT/PDF/EPUB 或冲突 |
| `parser` | v1 固定 `txt`；v2 固定 `website` |
| `adapter` | 仅 v2 必填：`fanqie`、`qimao` 或 `qidian`；v1 不得出现 |

本地文本例子见 [community-markdown.json](community-markdown.json)；书源例子见 [番茄](sources/fanqie.json)、[七猫](sources/qimao.json)、[起点](sources/qidian.json)。官方身份和权限由宿主计算，不能在清单里填写 `origin`、`permissions` 或 `script`。

## 打包与分发

ZIP **只允许根目录一个 `manifest.json`**，不允许嵌套目录、注释、加密 ZIP、额外文件或可执行代码。压缩包最多 256 KiB，解压后清单最多 64 KiB。不支持整个 GitHub 仓库 ZIP。

```text
my-plugin.zip
└── manifest.json
```

在清单所在文件夹运行：

```sh
python3 -c 'import zipfile; z=zipfile.ZipFile("my-plugin.zip", "w", zipfile.ZIP_DEFLATED); z.write("manifest.json", "manifest.json"); z.close()'
```

可将 JSON 或 ZIP 放在个人 GitHub 仓库的原始文件地址，或者自己维护的 HTTPS 静态服务上。地址必须直接返回文件，不能是 GitHub 文件预览页面。当前不跟随重定向，不接受查询参数、鉴权、非默认端口或 URL 编码路径；使用简单英文文件名。不要附带书籍、日志、密码、密钥和个人阅读记录。

预打包的规则包：[番茄 ZIP](packages/fanqie.zip)、[七猫 ZIP](packages/qimao.zip)、[起点 ZIP](packages/qidian.zip)。维护者修改清单后运行 `python3 scripts/package-community-plugins.py` 同步随附规则和 ZIP。

## 安装

1. 在书库打开 **管理导入插件…**。
2. 粘贴 JSON / ZIP 的 HTTPS 直链，点击 **从地址安装**；或者点击 **从 ZIP / JSON 安装…** 选择本地文件。
3. 查看来源、作者、版本和权限，再确认安装。
4. 安装及更新后均默认停用，手动点击 **启用**。
5. 网站插件启用后，从书库 **从网址导入…** 选择书源、粘贴书籍链接并预览目录，选择最多 100 章后开始验证和导入。

同 ID 安装会替换现有规则，不会自动更新。停用或移除不删除书籍和阅读进度。随应用提供的三个书源也需要手动安装并启用，且始终显示社区身份。

开发时可将 `Resources/index.html` 中的 `communityPluginsVisible` 改为 `true`，再构建运行；Windows 还需运行 `node windows/scripts/prepare-assets.js`。发布构建保持 `false`。这个开关只控制界面入口，不删除已安装的插件配置或书籍，也不是宿主权限隔离开关。

## 网站实际限制（2026-10-20）

| 适配器 | 限定主机 | 本次抽查 |
| --- | --- | --- |
| `fanqie` | `fanqienovel.com`，字体资源 `lf6-awef.bytetos.com` | 两本书各抽查 3 个未标锁章节，解析、入库、读回成功；未知字体仍拒绝 |
| `qimao` | `www.qimao.com` | 使用网页公开目录接口及 Nuxt 中的正文字符串；两本书各抽查 3 个免费章节，解析、入库、读回成功 |
| `qidian` | `www.qidian.com`、`book.qidian.com`、`read.qidian.com` | 当前环境返回访问验证页面，无法证明真实导入成功 |

遇到系统 DNS 返回 `198.18/15` Fake-IP 时，宿主通过固定地址、TLS 校验的 Cloudflare DNS-over-HTTPS 查询真实 A 记录，只发送域名，不发送书名、章节路径或内容；结果仍须是公网 IPv4，并固定到实际 HTTPS 连接。其他本机、私网和保留地址继续拒绝。查询结果仅在当前任务内缓存 60 秒，不修改系统 DNS 或代理设置。

三个适配器均为实验性，**不承诺当前能下载全书**。免费 App 可阅读不等于网页可抓取。不会调用隐藏解密接口、绕过验证码、登录、订阅或付费限制。请仅导入你有权保存且站点允许自动访问的内容。

目录读取所有匹配分组，番茄明确带锁的目录条目会排除，并显示排除数量。目录数是发现的未标锁链接数，仍不能视为已验证正文或全书章节数。短章节不会仅因字数不足被拒绝，正文提到“验证码”也不会直接判为验证页；提示页按结构和专用提示识别。每次最多 100 章、每章响应最多 2 MiB、累计响应最多 16 MiB，章间至少 1 秒，单次 HTTP 请求最多 20 秒（DNS 回退可能增加一次请求）；失败不自动重试。本批次全部解析成功才入库，书名带目录范围，不把部分内容标成全书。切换书库、停用插件、关闭窗口或失焦会取消并清除待导入状态；不支持断点续传。

## 开发与验证

- 本地规则用 v1，已有网站适配器用 v2。保持字段含义不变，更新时递增版本。
- 如果修改宿主适配器：使用纯数据解析函数，不执行下载页面中的代码；返回纯文本，未知结构和疑似受限内容应报错，不能把提示页当正文。
- 解析器共享在 `Resources/web-plugins.js`；Windows 构建通过 `windows/scripts/prepare-assets.js` 复制。macOS 由独立 JavaScriptCore 上下文调用，不向该上下文开放文件、网络或书库对象。
- 网络只允许 HTTPS；验证 DNS 的公网 IPv4 并固定到实际连接，不跟随重定向，不使用代理、Cookie 或登录会话。IPv6-only 主机当前不支持。
- 七猫在 Node HTTP/1 解析器下出现响应头兼容问题，因此使用系统 curl 进行固定公网 IP、TLS 校验的传输。Windows 需要系统自带的 `System32/curl.exe`，缺失时明确报错，不下载或执行第三方程序。
- 番茄的公开字体先按 SHA-256 校验，再应用与 Source Han Sans 2.002 精确字形比对生成的字符映射；任意未知字体或未知字符会停止，不猜字。映射重建脚本为 `scripts/build-public-font-map.py`（开发依赖 `fonttools`），不随包附带字体或书籍。许可见 `licenses/source-han-sans-LICENSE.txt`。
- 七猫只解析 Nuxt 源码里唯一的 JSON 正文字符串字面量，不执行 Nuxt JavaScript；目录接口仅允许固定路径和数字 `book_id` 参数，不开放任意查询。
- ZIP 安装只读取清单，不解压任意路径，不执行安装钩子。
- 书籍内容只由宿主保存；加密书库沿用加密存储。下载正文在内存中处理，不落明文临时书籍文件。插件配置不保存用户粘贴的书籍链接。
- 测试只使用虚构素材和临时目录，不读取真实书库。验证正常解析，以及身份冒充、路径穿越、ZIP 膨胀、局域网地址、付费提示、乱码、取消和禁用。

```sh
node windows/scripts/prepare-assets.js
npm test --prefix windows
swift build -c release
.build/release/LocalLibrary --self-test
```

功能测试通过不代表第三方网站实时可用。适配器变更后需少量抽查真实公开目录和正文；测试报告记录状态，不把真实小说内容提交到仓库。
